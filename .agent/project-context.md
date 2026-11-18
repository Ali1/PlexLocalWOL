# Local test context

Existing PHP log-reader tests use temporary synthetic files. No device, network, database or production logs are used.

## Native local certification — 17 November 2026

Run `bin/certify-local.ps1 -Check unit` for the complete existing native unit recipe from a fresh committed archive. `bin/certify-local-v2.ps1` publishes approved exact-source categories under the shared Personal Ops contract. These database-free fixtures require no Docker, MariaDB or separate environment. Package compatibility fixtures remain available locally; publication controls remain separate from application testing.
