# Quality and safety model

This repository contains Intune Proactive Remediation scripts that can update approved applications with `winget`.

This is not a read-only audit repository. The remediation scripts can make changes on managed Windows devices.

## Scope

The updater is intentionally limited to an approved application allowlist. It does not run `winget upgrade --all` and it does not install missing applications.

## Quality checks

| Check | Purpose |
|---|---|
| PSScriptAnalyzer | Static analysis for PowerShell scripts |
| Secret Scan / Gitleaks | Detects accidentally committed secrets |
| Pester Tests | Repository smoke tests and script parsing validation |
| Public Safety Check | Detects generated output files and unsafe public markers |

## Public-safe publishing rules

Do not commit:

- Intune export files
- real device names
- user names
- customer names
- tenant identifiers
- internal hostnames
- private IP addresses
- generated logs or reports
- secrets, tokens or credentials

## Operational safety

Before broad deployment:

1. Test with a small pilot group.
2. Review Intune detection and remediation output.
3. Check local logs from `C:\ProgramData\IntuneWingetUpdates\Logs`.
4. Confirm reboot-pending states before interpreting installer failures.
5. Expand gradually from pilot to wider production scope.