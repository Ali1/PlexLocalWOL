'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {hasAttempt, select} = require('./nightly-candidate.cjs');
const sha = 'a'.repeat(40);
const options = {sha, title: `full-checks:${sha}`, anchors: ['Full suite']};
const run = {head_sha: sha, display_title: options.title, status: 'completed'};
test('unchanged passing and failed full suites suppress nightly repeats', () => {
  for (const conclusion of ['success', 'failure']) {
    assert.equal(hasAttempt(run, [{name: 'Full suite', conclusion}], options), true);
  }
});
test('skipped nights and cancelled tests cannot masquerade as full attempts', () => {
  for (const conclusion of ['skipped', 'cancelled', null]) {
    assert.equal(hasAttempt(run, [{name: 'Full suite', conclusion}], options), false);
  }
  assert.equal(hasAttempt(run, [{name: 'Nightly preflight', conclusion: 'success'}], options), false);
});
test('different source and dispatcher-only evidence do not suppress checks', () => {
  const jobs = [{name: 'Full suite', conclusion: 'success'}];
  assert.equal(hasAttempt({...run, head_sha: 'b'.repeat(40)}, jobs, options), false);
  assert.equal(hasAttempt({...run, display_title: 'ordinary dispatch'}, jobs, options), false);
});
test('matching in-flight full run suppresses a duplicate', () => {
  assert.equal(hasAttempt({...run, status: 'in_progress'}, [], options), true);
});
test('one passing component cannot hide an incomplete combined suite', () => {
  assert.equal(hasAttempt(run, [{name: 'Backend', conclusion: 'success'}, {name: 'Mobile', conclusion: 'cancelled'}],
    {...options, anchors: ['Backend', 'Mobile']}), false);
});
test('manual dispatch deliberately permits retry without API calls', async () => {
  const result = await select({GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_SHA: sha}, () => {throw Error('unexpected API');});
  assert.equal(result.run_full, 'true');
});
test('API failure fails closed before expensive jobs', async () => {
  await assert.rejects(select({GITHUB_EVENT_NAME: 'schedule', GITHUB_SHA: sha, NIGHTLY_ANCHOR_JOBS: 'Full suite'}, async () => ({ok: false, status: 403})), /lookup failed/);
});
const env={GITHUB_EVENT_NAME:'schedule',GITHUB_SHA:sha,GITHUB_RUN_ID:'10',GITHUB_REPOSITORY:'fixture/app',NIGHTLY_ANCHOR_JOBS:'Full suite'};
function fixture(runs,jobLists={}) {
  return async url=>({ok:true,json:async()=>{
    if(url.endsWith('/actions/runs/10'))return {workflow_id:7};
    if(url.includes('/actions/workflows/7/runs?'))return {workflow_runs:runs};
    const match=url.match(/actions\/runs\/(\d+)\/jobs/);
    if(match)return {jobs:jobLists[match[1]]||[]};
    throw Error('Unexpected evidence request');
  }});
}
test('nightly new source selects a complete run',async()=>{
  assert.equal((await select(env,fixture([]))).run_full,'true');
});
test('nightly unchanged failure stays failed without another suite',async()=>{
  const previous={...run,id:9,conclusion:'failure',html_url:'https://example.test/run/9'};
  const result=await select(env,fixture([previous],{9:[{name:'Full suite',conclusion:'failure'}]}));
  assert.equal(result.run_full,'false');assert.match(result.reason,/run\/9/);
});
test('a skipped recent night cannot hide the previous full attempt',async()=>{
  const latest={...run,id:9,conclusion:'success'};
  const earlier={...run,id:8,conclusion:'success'};
  const result=await select(env,fixture([latest,earlier],{9:[{name:'Full suite',conclusion:'skipped'}],8:[{name:'Full suite',conclusion:'success'}]}));
  assert.equal(result.run_full,'false');
});

test('split nightly coverage deduplicates its own subset without requiring weekly style', async () => {
  const previous = {...run, display_title:`nightly-checks:${sha}`, id:9, conclusion:'success'};
  const result = await select({...env,SCHEDULED_COVERAGE:'nightly'},fixture([previous],{9:[{name:'Full suite',conclusion:'success'},{name:'Weekly style',conclusion:'skipped'}]}));
  assert.equal(result.run_full,'false');
  assert.match(result.reason,/nightly coverage/);
});

test('weekly style evidence never suppresses nightly regression or static analysis', async () => {
  const previous = {...run, display_title:`weekly-style:${sha}`,id:9,conclusion:'success'};
  const result = await select({...env,SCHEDULED_COVERAGE:'nightly'},fixture([previous],{9:[{name:'Full suite',conclusion:'success'}]}));
  assert.equal(result.run_full,'true');
});

test('a genuine full attempt continues to cover the split nightly subset', async () => {
  const previous = {...run,id:9,conclusion:'failure'};
  const result = await select({...env,SCHEDULED_COVERAGE:'nightly'},fixture([previous],{9:[{name:'Full suite',conclusion:'failure'}]}));
  assert.equal(result.run_full,'false');
});

test('split scheduling does not weaken or deduplicate manual, PR, push or release checks', async () => {
  for (const event of ['workflow_dispatch','pull_request','push','release']) {
    const result = await select({...env,GITHUB_EVENT_NAME:event,SCHEDULED_COVERAGE:'nightly'},()=>{throw Error('Unexpected API');});
    assert.equal(result.run_full,'true');
  }
});


test('legacy core-checks evidence prevents unchanged nightly repeats', async () => {
  const previous = {...run, display_title:`core-checks:${sha}`,id:9,conclusion:'failure'};
  const result = await select({...env,SCHEDULED_COVERAGE:'nightly'},fixture([previous],{9:[{name:'Full suite',conclusion:'failure'}]}));
  assert.equal(result.run_full,'false');
});
