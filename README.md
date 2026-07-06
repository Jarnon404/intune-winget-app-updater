![PSScriptAnalyzer](https://github.com/Jarnon404/intune-winget-app-updater/actions/workflows/psscriptanalyzer.yml/badge.svg)
![Secret Scan](https://github.com/Jarnon404/intune-winget-app-updater/actions/workflows/gitleaks.yml/badge.svg)
![Pester Tests](https://github.com/Jarnon404/intune-winget-app-updater/actions/workflows/pester.yml/badge.svg)
![Public Safety Check](https://github.com/Jarnon404/intune-winget-app-updater/actions/workflows/public-safety-check.yml/badge.svg)
![License](https://img.shields.io/github/license/Jarnon404/intune-winget-app-updater)
![Release](https://img.shields.io/github/v/release/Jarnon404/intune-winget-app-updater)
![Repo Size](https://img.shields.io/github/repo-size/Jarnon404/intune-winget-app-updater)

# Intune Winget App Updater

Controlled Microsoft Intune Proactive Remediation package for updating approved Windows applications with `winget`.

This project is not a read-only audit repository. It detects, reports and attempts to update a limited allowlist of applications with `winget`.

## Purpose

The purpose of this repository is to provide a controlled way to pilot and run application updates through Microsoft Intune without using:

```powershell
winget upgrade --all
```

The package:

- detects installed applications with `winget list`
- uses the Windows uninstall registry as a fallback detection source
- separates states such as `WingetInstalled`, `RegistryOnly`, `NotInstalled` and `Unknown`
- updates only approved allowlist applications that are manageable by `winget`
- does not install missing applications
- does not run `winget upgrade --all`
- writes local log files
- provides compact Intune export output
- includes an offline technician tool for manual validation

## Main components

| Component | Version | File |
|---|---:|---|
| Approved App Updates Detection | v10.3 | `scripts/approved-app-updates/Intune-Winget-AppUpdates-Detection-v10.3-HybridRegistry.ps1` |
| Approved App Updates Remediation | v10.3 | `scripts/approved-app-updates/Intune-Winget-AppUpdates-Remediation-v10.3-HybridRegistry-AllNonFatal.ps1` |
| Log Summary Detection | v10 | `scripts/log-summary/Winget-LogSummary-Detection-v10.ps1` |
| Log Summary No-Op Remediation | v10 | `scripts/log-summary/Winget-LogSummary-NoOp-Remediation-v10.ps1` |
| Offline Technician Tool | v10.3 | `tools/Intune-Winget-Offline-Technician-Tool-v10.3.ps1` |

## Approved application allowlist

```text
7zip.7zip
Notepad++.Notepad++
Mozilla.Firefox
Google.Chrome
Adobe.Acrobat.Reader.32-bit
Adobe.Acrobat.Reader.64-bit
```

## Intune packages

### Winget - Approved App Updates

Detection script:

```text
Intune-Winget-AppUpdates-Detection-v10.3-HybridRegistry.ps1
```

Remediation script:

```text
Intune-Winget-AppUpdates-Remediation-v10.3-HybridRegistry-AllNonFatal.ps1
```

Recommended settings:

```text
Run this script using the logged-on credentials: No
Enforce script signature check: No
Run script in 64-bit PowerShell: Yes
```

### Winget - Log Summary

Detection script:

```text
Winget-LogSummary-Detection-v10.ps1
```

Remediation script:

```text
Winget-LogSummary-NoOp-Remediation-v10.ps1
```

## Logs

```text
C:\ProgramData\IntuneWingetUpdates\Logs
```

The scripts remove log files older than 14 days and keep the log folder below 50 MB.

## Intune output markers

```text
WINGET_DETECTION_V10_3
WINGET_REMEDIATION_V10_3
WINGET_LOG_SUMMARY_V10
```

## Offline technician tool

Detection mode:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Intune-Winget-Offline-Technician-Tool-v10.3.ps1 -Mode Detection
```

Full mode:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Intune-Winget-Offline-Technician-Tool-v10.3.ps1
```

If PowerShell is not elevated, the tool starts a UAC elevation prompt.

## Repository documentation

- [GitHub Pages documentation](https://jarnon404.github.io/intune-winget-app-updater/)
- [Intune setup](docs/INTUNE-SETUP.md)
- [Pilot runbook](docs/PILOT-RUNBOOK.md)
- [Quality and safety model](docs/quality-and-safety.md)
- [Changelog](docs/CHANGELOG.md)

## Quality and safety checks

This repository uses GitHub Actions and branch protection to keep public repository quality under control.

| Check | Purpose |
|---|---|
| PSScriptAnalyzer | Static analysis for PowerShell scripts |
| Secret Scan / Gitleaks | Detects accidentally committed secrets |
| Pester Tests | Repository smoke tests and script parsing validation |
| Public Safety Check | Detects generated output files and unsafe public markers |

## Pilot guidance

Recommended rollout flow:

1. Deploy first to a small pilot device group.
2. Run hourly for one business day.
3. Review Intune exports and Log Summary output.
4. Confirm that no unexpected applications are updated.
5. Move to a daily schedule after stable pilot results.

## Registry-only applications

`winget` may not always recognize an application that exists in the Windows uninstall registry.

In that case the application is reported as `RegistryOnly` and is not force-updated.

## License

This repository is licensed under the [MIT License](LICENSE).

## Security note

This repository contains remediation scripts that can update approved applications on managed Windows devices.

Do not commit:

- real Intune exports
- real device names
- user names
- customer names
- tenant identifiers
- internal hostnames
- private IP addresses
- generated logs or reports
- secrets, tokens or credentials
## Current script baseline

Current approved app update scripts:

- Detection: Intune-Winget-AppUpdates-Detection-v10.4-HybridRegistry-Discovery.ps1
- Remediation: Intune-Winget-AppUpdates-Remediation-v10.4-HybridRegistry-AllNonFatal.ps1

Baseline: v10.4.0
