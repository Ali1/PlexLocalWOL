# Agent instructions

## Post-deployment local verification

The delivery owner must follow the current [offer-first certification contract](https://github.com/Ali1/personal-ops/blob/main/runbooks/local-release-certification.md).
Deploy promptly with focused safeguards; freeze the actually deployed SHA, retain
ownership and the uncertified queue, and **offer** local certification for missing
categories afterward. Quiet maintenance does not suppress this offer; consolidate
related deployments in one offer. An offer is not permission to start full suites.
Run only approved complete compatible recipes, then record outcomes or an accepted
handoff. Declined/unavailable coverage remains queued, never green. Use
`bin/certify-local-v2.ps1` for the supported categories in
`.github/local-certification-v2.json`; all other categories remain explicitly missing.
Legacy v1 statuses do not skip nightly work. Linux/database/browser/native results
require their actual scope; portable static analysis is separately declared.
