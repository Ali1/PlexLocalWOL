# Agent instructions

## Local application testing

Application tests, static analysis and style checks run in the developing agent's workspace, not GitHub Actions. Follow the [shared delivery workflow](https://github.com/Ali1/personal-ops/blob/main/runbooks/delivery-workflow.md) for affected checks and the [local certification policy](https://github.com/Ali1/personal-ops/blob/main/runbooks/local-release-certification.md) for an explicitly approved comprehensive pass. Keep exact-source and scope receipts honest; no automatic comprehensive follow-up is implied by deployment.

The existing local runners and `.github/local-certification-v2.json` remain available. Build, release, security and operational controls are separate from application testing.
