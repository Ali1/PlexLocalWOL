'use strict';
// Version 2 deliberately rejects legacy SHA-only statuses. No deployment credentials.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const shaPattern = /^[a-f0-9]{40}$/;
const contextFor = category => `local-cert/v2/${category}`;
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
  return value;
}
function git(root, ...args) { return execFileSync('git', ['-C', root, ...args], {encoding: 'utf8'}).trim(); }
function describe(policy, category, sha, readInput, verifier = fs.readFileSync(__filename)) {
  if (policy.schema_version !== 2 || !shaPattern.test(sha) || !/^Ali1\/[A-Za-z0-9_.-]+$/.test(policy.repository)) throw Error('Invalid source/policy');
  const definition = policy.categories[category];
  if (!definition || definition.reusable !== true || !definition.local_check || !definition.scope || !definition.inputs?.length) throw Error('Category has no supported complete local recipe');
  // Cross-platform static analysis is the only portable exception. Browser/native/Linux
  // and database results require their own faithful publisher, never Windows substitution.
  if (definition.scope.platform !== 'portable-static' || definition.scope.database !== 'none' || definition.scope.kind !== 'static' || !['php-8.4', 'node-22'].includes(definition.scope.runtime)) throw Error('Unsupported local scope');
  const inputs = Object.fromEntries(definition.inputs.map(file => {
    if (!/^[A-Za-z0-9_.\/-]+$/.test(file) || file.split('/').includes('..')) throw Error('Unsafe input path');
    return [file, digest(readInput(file))];
  }));
  // Git exports and Windows checkouts can differ only in checkout line endings.
  const verifierDigest = digest(Buffer.from(verifier).toString('utf8').replace(/\r\n/g, '\n'));
  const fingerprint = digest(JSON.stringify(canonical({protocol: 2, repository: policy.repository, source_sha: sha, category, definition, inputs, verifier: verifierDigest})));
  return {category, source_sha: sha, scope: definition.scope, fingerprint, context: contextFor(category), description: `v2:${fingerprint}`, local_check: definition.local_check};
}
function evaluate(expected, statuses, now = Date.now()) {
  if (!Array.isArray(statuses)) return false;
  const matches = statuses.filter(s => s.context === expected.context);
  // A malformed latest result must not expose an older green result.
  if (matches.some(s => !Number.isSafeInteger(s.id) || s.id < 1)) return false;
  const latest = matches.sort((a, b) => b.id - a.id)[0];
  const age = now - Date.parse(latest?.created_at || '');
  return latest?.state === 'success' && latest?.creator?.login === 'Ali1' && latest?.creator?.id === 218558 && latest?.creator?.type === 'User'
    && latest?.description === expected.description && Number.isFinite(age) && age >= -300000 && age <= 86400000;
}
async function lookup(repository, sha, token, request = fetch) {
  const statuses = [];
  for (let page = 1; page <= 100; page++) {
    const response = await request(`https://api.github.com/repos/${repository}/commits/${sha}/statuses?per_page=100&page=${page}`, {
      headers: {Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json'}, signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) throw Error(`Status lookup failed (${response.status})`);
    const rows = await response.json();
    if (!Array.isArray(rows)) throw Error('Malformed status lookup');
    statuses.push(...rows);
    if (rows.length < 100) return statuses;
  }
  throw Error('Status pagination incomplete');
}
function expectedFromCheckout(policy, category, sha, root) {
  return describe(policy, category, sha, file => execFileSync('git', ['-C', root, 'show', `${sha}:${file}`]));
}
async function select(policy, sha, root, env = process.env, request = fetch) {
  const result = {};
  let statuses = [];
  if (env.GITHUB_REPOSITORY !== policy.repository) throw Error('Repository mismatch');
  if (env.GITHUB_EVENT_NAME !== 'pull_request' && env.USE_LOCAL_CERTIFICATES !== 'false') {
    try { statuses = await lookup(policy.repository, sha, env.GH_TOKEN, request); }
    catch (error) { console.warn(`${error.message}; all unmatched categories execute.`); }
  }
  for (const [category, definition] of Object.entries(policy.categories)) {
    let expected;
    try { expected = expectedFromCheckout(policy, category, sha, root); } catch { /* Missing historical inputs cannot certify coverage. */ }
    result[category] = {covered: !!expected && evaluate(expected, statuses), scope: definition.scope, fingerprint: expected?.fingerprint || null};
  }
  return result;
}
async function main() {
  const root = path.resolve(process.env.LOCAL_EVIDENCE_SOURCE || process.cwd());
  const policyRoot = path.resolve(__dirname, '../..');
  const policy = JSON.parse(fs.readFileSync(path.join(policyRoot, '.github/local-certification-v2.json'), 'utf8'));
  const sha = process.env.LOCAL_EVIDENCE_SHA || git(root, 'rev-parse', 'HEAD');
  if (!shaPattern.test(sha) || git(root, 'rev-parse', 'HEAD') !== sha) throw Error('Exact checked out SHA required');
  if (process.argv[2] === 'describe') {
    console.log(JSON.stringify(expectedFromCheckout(policy, process.argv[3], sha, root)));
    return;
  }
  const results = await select(policy, sha, root);
  const receipt = {schema_version: 2, repository: policy.repository, source_sha: sha, workflow_sha: process.env.GITHUB_WORKFLOW_SHA || null, categories: results};
  fs.writeFileSync(path.join(root, '.local-evidence.json'), JSON.stringify(receipt, null, 2));
  for (const [category, result] of Object.entries(results)) {
    if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `lc_${category.replaceAll('-', '_')}=${result.covered}\n`);
  }
  const summary = `Local evidence for ${sha}: ${JSON.stringify(results)}. Only matching complete categories are reused; other checks remain required.\n`;
  if (process.env.GITHUB_STEP_SUMMARY) fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
  console.log(summary);
}
if (require.main === module) main().catch(error => {console.error(error.message); process.exitCode = 1;});
module.exports = {describe, evaluate, lookup, select, canonical, contextFor};
