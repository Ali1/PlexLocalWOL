# Agent instructions

## Post-deployment local verification

Follow the current [offer-first certification contract](https://github.com/Ali1/personal-ops/blob/main/runbooks/local-release-certification.md).
Use judgment during rapid iterations: merges and deployments do not each require
an offer or certification run. Keep deployment receipts and the uncertified queue,
then at a natural stopping point ask whether Ali is done and offer one consolidated
local verification pass. After his okay, freeze the latest intended committed SHA
and run only missing approved complete compatible categories. Silence or elapsed
time is not approval; do not keep reasking while an offer is pending or declined.
Retain ownership until outcome or accepted handoff. Superseded intermediate commits
need no repeated certification unless still independently deployed or relevant.
Quiet maintenance must not lose this follow-up; changed code needs new exact-SHA
evidence. Declined/unavailable coverage remains queued, never green. Use
`bin/certify-local-v2.ps1` for the supported categories in
`.github/local-certification-v2.json`; all other categories remain explicitly missing.
Legacy v1 statuses do not skip nightly work. Linux/database/browser/native results
require their actual scope; portable static analysis is separately declared.
