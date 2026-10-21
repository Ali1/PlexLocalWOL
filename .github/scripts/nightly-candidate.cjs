// Shared source for app-local copies. Never receives deployment credentials.
'use strict';
const {appendFileSync} = require('node:fs');

function hasAttempt(run, jobs, {sha, title, anchors}) {
  if (run.head_sha !== sha || run.display_title !== title) return false;
  if (run.status !== 'completed') return true;
  const fullJobs = jobs.filter(job => anchors.includes(job.name));
  return fullJobs.some(job => job.conclusion === 'failure')
    || anchors.every(name => fullJobs.some(job => job.name === name && job.conclusion === 'success'));
}

async function select(env = process.env, request = fetch) {
  const sha = env.CANDIDATE_SHA || env.GITHUB_SHA;
  if (!/^[a-f0-9]{40}$/.test(sha || '')) throw Error('Expected an exact candidate SHA.');
  if (env.GITHUB_EVENT_NAME !== 'schedule') return {sha, run_full: 'true', reason: 'Manual full verification'};
  const anchors = (env.NIGHTLY_ANCHOR_JOBS || '').split('|').filter(Boolean);
  if (!anchors.length) throw Error('No full-suite anchor jobs configured.');
  const api = async path => {
    const response = await request(`${env.GITHUB_API_URL || 'https://api.github.com'}/repos/${env.GITHUB_REPOSITORY}/${path}`, {
      headers: {Authorization: `Bearer ${env.GH_TOKEN}`, Accept: 'application/vnd.github+json'},
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) throw Error(`Actions evidence lookup failed (${response.status}).`);
    return response.json();
  };
  const current = await api(`actions/runs/${env.GITHUB_RUN_ID}`);
  // Split scheduled coverage must not advertise a complete manual/release gate.
  // A genuine full attempt still covers the nightly subset, but a weekly style
  // run must never suppress nightly static analysis or behavioural tests.
  const split = env.SCHEDULED_COVERAGE === 'nightly';
  const title = `${split ? 'nightly-checks' : 'full-checks'}:${sha}`;
  const titles = new Set([title, `full-checks:${sha}`, ...(split ? [`core-checks:${sha}`] : [])]);
  // Filter by SHA server-side. Paginate so cheap skipped nights cannot hide the
  // original full attempt. Incomplete/cancelled full attempts are retryable.
  for (let page = 1; ; page++) {
    const {workflow_runs: runs} = await api(`actions/workflows/${current.workflow_id}/runs?head_sha=${sha}&per_page=100&page=${page}`);
    for (const run of runs) {
      if (String(run.id) === String(env.GITHUB_RUN_ID) || !titles.has(run.display_title)) continue;
      const jobs = [];
      if (run.status === 'completed') {
        for (let jobPage = 1; ; jobPage++) {
          const data = await api(`actions/runs/${run.id}/jobs?per_page=100&page=${jobPage}`);
          jobs.push(...data.jobs);
          if (data.jobs.length < 100) break;
        }
      }
      if (hasAttempt(run, jobs, {sha, title: run.display_title, anchors})) {
        return {sha, run_full: 'false', reason: `Existing ${split ? 'nightly coverage' : 'full'} attempt: ${run.html_url} (${run.conclusion || run.status}); no automatic retry of unchanged source`};
      }
    }
    if (runs.length < 100) break;
  }
  return {sha, run_full: 'true', reason: `New source without a completed ${split ? 'nightly coverage' : 'full-suite'} attempt`};
}

if (require.main === module) {
  select().then(result => {
    for (const [key, value] of Object.entries(result)) {
      if (key !== 'reason') appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);
    }
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `${result.sha}: ${result.reason}. A preflight success is not a full verification pass.\n`);
    console.log(result.reason);
  }).catch(error => { console.error(error.message); process.exitCode = 1; });
}
module.exports = {hasAttempt, select};
