

## Scheduled checks — 17 October 2026

Existing mandatory PR/change/release gates are unchanged. New checks-only default-branch schedules do not deploy or issue full-release receipts. UTC lanes:

- `nightly-core.yml`: `31 1 * * *` (core); existing contained/synthetic commands only.
- Local prepush/premerge checks are impact-based: changed-PHP PHPCS; affected PHPStan/dependencies (full project where tooling requires); affected unit/integration/shared callers and browser journeys. Focused evidence is not full regression. Package compatibility remains development/package-change-only.

Nightly unchanged-source safeguard (21 October 2026): the preflight checks actual
same-workflow jobs for the frozen default-branch SHA. Completed successes and
failures, or an in-flight attempt, suppress automatic repeats; cancelled or
incomplete attempts may retry. Manual dispatch deliberately retries. Weekly
coverage remains independent and runs even when source is unchanged. A skipped
nightly is not a verification pass. Selector regression checks: `node --test
.github/scripts/nightly-candidate.test.cjs`.
