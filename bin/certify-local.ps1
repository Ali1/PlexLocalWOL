param(
    [string[]]$Check = @('all'),
    [switch]$Push,
    [switch]$Publish,
    [switch]$List,
    [switch]$KeepWorkspace
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$recipe = Get-Content (Join-Path $repoRoot '.github/local-checks.json') -Raw | ConvertFrom-Json
$available = @($recipe.checks.PSObject.Properties.Name)
if ($List) { $available; return }
$selected = if ($Check -contains 'all') { $available } else { @($Check | Select-Object -Unique) }
foreach ($suite in $selected) {
    if ($suite -notin $available) { throw "No local recipe for $suite; leave this check on GitHub." }
}

function Invoke-Checked([string]$Program, [string[]]$CommandArgs) {
    & $Program @CommandArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE)" }
}
function Restore-TestEnvironment {
    foreach ($key in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previousEnvironment[$key], 'Process')
    }
}
function Set-Certificate([string]$Suite, [string]$State) {
    # No further recipe subprocess may run after restoring the publisher context.
    # Pending writes precede isolation; success/failure writes follow all tests.
    Restore-TestEnvironment
    $publisher = (& gh api user --jq '.login').Trim()
    if ($LASTEXITCODE -ne 0 -or $publisher -ne 'Ali1') { throw 'Certification requires the trusted Ali1 publisher.' }
    $context = "local-release/v1/$Suite"
    Invoke-Checked 'gh' @('api', '--method', 'POST', "repos/$($recipe.repository)/statuses/$commitSha",
        '-f', "state=$State", '-f', "context=$context", '-f', "description=$context $commitSha", '--silent')
}
function Invoke-RecipeCommand($Command) {
    $cwd = if ($Command.cwd) { Join-Path $sourceRoot $Command.cwd } else { $sourceRoot }
    Push-Location $cwd
    try {
        $commandArgs = @($Command.args | ForEach-Object { $_.Replace('{junit}', $junitPath) })
        Invoke-Checked $Command.program $commandArgs
    } finally { Pop-Location }
}

function Assert-TestWorkspacePath([string]$RunRoot, [string]$RunParent, [string]$RunName) {
    # Only this invocation's newly created directory is eligible. Never traverse
    # a junction/symlink, including one introduced by a dependency or test.
    $expected = [IO.Path]::GetFullPath((Join-Path $RunParent $RunName))
    if ($RunName -notmatch '^[0-9a-f]{40}-[0-9a-f]{32}$' -or
        [IO.Path]::GetFullPath($RunRoot) -ne $expected) { throw 'Unsafe test workspace path.' }
    $ancestor = Get-Item -LiteralPath $RunRoot -Force
    while ($null -ne $ancestor) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing cleanup through a reparse point: $($ancestor.FullName)"
        }
        $ancestor = $ancestor.Parent
    }
}

function Remove-TestSource([string]$RunRoot, [string]$RunParent, [string]$RunName) {
    Assert-TestWorkspacePath $RunRoot $RunParent $RunName
    function Remove-TreeWithoutFollowingLinks([string]$Path) {
        $entry = Get-Item -LiteralPath $Path -Force
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($entry.PSIsContainer) { [IO.Directory]::Delete($entry.FullName, $false) }
            else { [IO.File]::Delete($entry.FullName) }
            return
        }
        if ($entry.PSIsContainer) {
            foreach ($child in Get-ChildItem -LiteralPath $Path -Force) {
                Remove-TreeWithoutFollowingLinks $child.FullName
            }
            [IO.Directory]::Delete($entry.FullName, $false)
        } else {
            $entry.IsReadOnly = $false
            [IO.File]::Delete($entry.FullName)
        }
    }
    foreach ($name in @('source', 'source.zip')) {
        $path = Join-Path $RunRoot $name
        if (Test-Path -LiteralPath $path) { Remove-TreeWithoutFollowingLinks $path }
    }
}

Push-Location $repoRoot
$previousEnvironment = @{}
$remoteCommitExists = $false
$workspaceCreated = $false
$runState = 'failed'
try {
    $commitSha = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify commit' }
    $branch = (& git symbolic-ref --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Use a named branch' }
    & git diff --quiet HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Commit tracked edits before certification; only committed content is tested.' }
    $origin = (& git remote get-url origin).Trim()
    if ($LASTEXITCODE -ne 0 -or $origin -notmatch ('github\.com[:/]' + [regex]::Escape($recipe.repository) + '(\.git)?$')) {
        throw 'Origin does not match the checked-in certification recipe.'
    }
    if ($Publish) {
        $publisher = (& gh api user --jq '.login').Trim()
        if ($LASTEXITCODE -ne 0 -or $publisher -ne 'Ali1') { throw 'Certification requires the trusted Ali1 publisher.' }
        & gh api "repos/$($recipe.repository)/commits/$commitSha" --silent 2>$null
        $remoteCommitExists = $LASTEXITCODE -eq 0
        if ($remoteCommitExists) { foreach ($suite in $selected) { Set-Certificate $suite 'pending' } }
    }
    $testParent = Join-Path $env:LOCALAPPDATA "Ali\LocalReleaseTests\$($recipe.repository.Split('/')[-1])"
    $testName = "$commitSha-$([guid]::NewGuid().ToString('N'))"
    $testRoot = Join-Path $testParent $testName
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $workspaceCreated = $true
    $zipPath = Join-Path $testRoot 'source.zip'
    $sourceRoot = Join-Path $testRoot 'source'
    Invoke-Checked 'git' @('archive', '--format=zip', "--output=$zipPath", $commitSha)
    Expand-Archive -LiteralPath $zipPath -DestinationPath $sourceRoot
    $sourceHashes = @{}
    Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | ForEach-Object {
        $sourceHashes[$_.FullName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    Write-Host "Testing exact commit $commitSha in $sourceRoot"
    # Never inherit an agent's production/provider credentials or database URL.
    $environmentNames = @((Get-ChildItem Env: | Where-Object {
        $_.Name -match '(^AWS_|^GOOGLE_|^EXPO_|^CLOUDFLARE_|^DB_|^DATABASE|^MYSQL_|^MARIADB_|^MAIL_|^STRIPE_|^HARLEYST_|^IMCAL_|TOKEN|SECRET|PASSWORD|CREDENTIAL)'
    }).Name) + @($recipe.environment.PSObject.Properties.Name)
    foreach ($key in ($environmentNames | Select-Object -Unique)) {
        $previousEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        [Environment]::SetEnvironmentVariable($key, $null, 'Process')
    }
    foreach ($setting in $recipe.environment.PSObject.Properties) {
        [Environment]::SetEnvironmentVariable($setting.Name, [string]$setting.Value, 'Process')
    }
    $prepared = @{}
    foreach ($suite in $selected) {
        $definition = $recipe.checks.$suite
        $junitPath = Join-Path $testRoot "$suite.xml"
        foreach ($setup in $definition.setup) {
            if (-not $prepared[$setup]) {
                if ($setup -eq 'php') {
                    $expectedPhp = if ($recipe.php_runtime) { [string]$recipe.php_runtime } else { '8.4' }
                    if ($expectedPhp -notin @('8.4', '8.5')) { throw 'Unsupported recipe PHP runtime.' }
                    $version = (& php -r 'echo PHP_VERSION;').Trim()
                    if ($LASTEXITCODE -ne 0 -or $version -notmatch ('^' + [regex]::Escape($expectedPhp) + '\.')) { throw "PHP $expectedPhp is required." }
                }
                if ($setup -like 'node*') {
                    $version = (& node --version).Trim()
                    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^v22\.') { throw 'Node 22 is required.' }
                }
                foreach ($command in $recipe.setup.$setup) { Invoke-RecipeCommand $command }
                $prepared[$setup] = $true
            }
        }
        Write-Host "Running complete $suite recipe"
        foreach ($command in $definition.commands) { Invoke-RecipeCommand $command }
        if ($definition.junit) {
            [xml]$junit = Get-Content -LiteralPath $junitPath -Raw
            if ($junit.SelectNodes('//testcase').Count -eq 0) { throw 'No PHPUnit tests ran.' }
            if ($junit.SelectNodes('//testcase[skipped or failure or error]').Count -gt 0) {
                throw 'Incomplete PHPUnit result: skipped, failed or errored tests cannot be certified.'
            }
        }
    }
    foreach ($path in $sourceHashes.Keys) {
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $sourceHashes[$path]) {
            throw "Committed source changed while testing: $path"
        }
    }
    if ((& git rev-parse HEAD).Trim() -ne $commitSha) { throw 'HEAD moved during tests; retest the new commit.' }
    & git diff --quiet HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Tracked edits appeared during tests; commit and retest.' }
    Restore-TestEnvironment
    if ($Push) { Invoke-Checked 'git' @('push', 'origin', "${commitSha}:refs/heads/$branch") }
    if ($Publish) { foreach ($suite in $selected) { Set-Certificate $suite 'success' } }
    $runState = 'passed'
    Write-Host "Passed: $($selected -join ', ') for $commitSha"
} catch {
    if ($remoteCommitExists) { foreach ($suite in $selected) { Set-Certificate $suite 'failure' } }
    throw
} finally {
    Restore-TestEnvironment
    Pop-Location
    if ($workspaceCreated) {
        try {
            Assert-TestWorkspacePath $testRoot $testParent $testName
            # Keep JUnit reports and a small outcome record for diagnosis.
            @{ commit = $commitSha; checks = $selected; state = $runState;
                finishedUtc = [DateTime]::UtcNow.ToString('o') } |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testRoot 'result.json') -Encoding UTF8
            if ($KeepWorkspace) { Write-Host "Retained test workspace: $testRoot" }
            else { Remove-TestSource $testRoot $testParent $testName }
        } catch {
            Write-Warning "Test workspace cleanup failed; retained at ${testRoot}: $_"
        }
    }
}
