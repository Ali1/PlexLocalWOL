param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{40}$')][string]$SourceSha,
    [Parameter(Mandatory=$true)][string[]]$Check,
    [switch]$Approved,
    [switch]$Publish
)
$ErrorActionPreference = 'Stop'
if (-not $Approved) { throw 'Offer the frozen deployed SHA/categories first. Run only after applicable user approval; pass -Approved to acknowledge it.' }
$root = Split-Path $PSScriptRoot -Parent
$helper = Join-Path $root '.github/scripts/local-evidence.cjs'
$policy = Get-Content (Join-Path $root '.github/local-certification-v2.json') -Raw | ConvertFrom-Json
Push-Location $root
$previousSha = $env:LOCAL_EVIDENCE_SHA
try {
    if ((& git rev-parse HEAD).Trim() -ne $SourceSha) { throw 'Check out the frozen deployed SHA in a clean isolated checkout; do not chase main.' }
    & git diff --quiet HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Tracked checkout edits prevent certification.' }
    if ($Check -contains 'all' -or $Check.Count -eq 0) { throw 'Select explicit complete categories from the approved offer.' }
    $origin = (& git remote get-url origin).Trim()
    if ($LASTEXITCODE -ne 0 -or $origin -notmatch ('github\.com[:/]' + [regex]::Escape($policy.repository) + '(\.git)?$')) { throw 'Repository origin mismatch.' }
    $default = (& gh api "repos/$($policy.repository)" --jq '.default_branch').Trim()
    if ($LASTEXITCODE -ne 0 -or $default -notmatch '^[A-Za-z0-9_/-]+$') { throw 'Cannot establish default history.' }
    & git fetch origin $default
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read current default history.' }
    & git merge-base --is-ancestor $SourceSha FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Only an integrated default-history source can receive postdeployment certificates; arbitrary PR heads are refused.' }
    $env:LOCAL_EVIDENCE_SHA = $SourceSha
    $descriptions = @{}
    foreach ($category in $Check) {
        $json = & node $helper describe $category
        if ($LASTEXITCODE -ne 0) { throw "No compatible complete recipe for $category" }
        $descriptions[$category] = $json | ConvertFrom-Json
        if ($descriptions[$category].scope.runtime -eq 'php-8.4') {
            $runtime = (& php -r 'echo PHP_VERSION;').Trim()
            if ($LASTEXITCODE -ne 0 -or $runtime -notmatch '^8\.4\.') { throw 'PHP 8.4 required by category scope.' }
        } elseif ($descriptions[$category].scope.runtime -eq 'node-22') {
            $runtime = (& node --version).Trim()
            if ($LASTEXITCODE -ne 0 -or $runtime -notmatch '^v22\.') { throw 'Node 22 required by category scope.' }
        } else { throw 'Unsupported runtime scope.' }
    }
    if ($Publish) {
        $identity = (& gh api user | ConvertFrom-Json)
        if ($LASTEXITCODE -ne 0 -or $identity.login -ne 'Ali1' -or $identity.id -ne 218558) { throw 'Trusted Ali1 publisher required.' }
        & gh api "repos/$($policy.repository)/commits/$SourceSha" --silent
        if ($LASTEXITCODE -ne 0) { throw 'Source must already exist on GitHub; no push is performed.' }
    }
    function Set-Result($Description, [string]$State) {
        & gh api --method POST "repos/$($policy.repository)/statuses/$SourceSha" -f "state=$State" -f "context=$($Description.context)" -f "description=$($Description.description)" --silent
        if ($LASTEXITCODE -ne 0) { throw 'Could not confirm certificate publication.' }
    }
    foreach ($category in $Check) {
        $description = $descriptions[$category]
        if ($Publish) { Set-Result $description 'pending' }
        $state = 'failed'
        try {
            # Reuse the existing fresh-archive, synthetic-env, complete-suite runner.
            # Its legacy -Publish/-Push options are deliberately never forwarded.
            & (Join-Path $root 'bin/certify-local.ps1') -Check @($description.local_check)
            if ((& git rev-parse HEAD).Trim() -ne $SourceSha) { throw 'Source moved during certification.' }
            & git diff --quiet HEAD
            if ($LASTEXITCODE -ne 0) { throw 'Tracked edits appeared during certification.' }
            $after = & node $helper describe $category
            if ($LASTEXITCODE -ne 0 -or ($after | ConvertFrom-Json).fingerprint -ne $description.fingerprint) { throw 'Recipe/test inputs changed during certification.' }
            $state = 'passed'
            if ($Publish) { Set-Result $description 'success' }
        } catch {
            if ($Publish) { Set-Result $description 'failure' }
            throw
        } finally {
            $parent = Join-Path $env:LOCALAPPDATA 'Ali/PostDeployVerification/results'
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
            $description | Add-Member -NotePropertyName verification_state -NotePropertyValue $state
            $description | Add-Member -NotePropertyName finished_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o'))
            $description | Add-Member -NotePropertyName published -NotePropertyValue ([bool]$Publish)
            $description | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $parent "$($policy.repository.Replace('/','-'))-$SourceSha-$category.json") -Encoding UTF8
        }
    }
} finally {
    $env:LOCAL_EVIDENCE_SHA = $previousSha
    Pop-Location
}
