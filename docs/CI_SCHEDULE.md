

## Scheduled checks — 17 October 2026

Existing mandatory PR/change/release gates are unchanged. New checks-only default-branch schedules do not deploy or issue full-release receipts. UTC lanes:

- `nightly-core.yml`: `31 1 * * *` (core); existing contained/synthetic commands only.
- Local prepush/premerge checks are impact-based: changed-PHP PHPCS; affected PHPStan/dependencies (full project where tooling requires); affected unit/integration/shared callers and browser journeys. Focused evidence is not full regression. Package compatibility remains development/package-change-only.
