![PSScriptAnalyzer](https://github.com/Jarnon404/intune-winget-app-updater/actions/workflows/psscriptanalyzer.yml/badge.svg)
![Secret Scan](https://github.com/Jarnon404/intune-winget-app-updater/actions/workflows/gitleaks.yml/badge.svg)
![Pester Tests](https://github.com/Jarnon404/intune-winget-app-updater/actions/workflows/pester.yml/badge.svg)
![Public Safety Check](https://github.com/Jarnon404/intune-winget-app-updater/actions/workflows/public-safety-check.yml/badge.svg)
![License](https://img.shields.io/github/license/Jarnon404/intune-winget-app-updater)
![Release](https://img.shields.io/github/v/release/Jarnon404/intune-winget-app-updater)
![Repo Size](https://img.shields.io/github/repo-size/Jarnon404/intune-winget-app-updater)

# Intune Winget App Updater

PowerShell-skriptipaketti Microsoft Intune Proactive Remediations -käyttöön.

Tämä projekti ei ole pelkkä auditointi: se tunnistaa, raportoi ja yrittää päivittää rajatun allowlistin sovelluksia `winget`illä.

## Tarkoitus

Tarkoitus on tarjota hallittu tapa pilotoida ja ajaa sovelluspäivityksiä Intunen kautta ilman komentoa:

```powershell
winget upgrade --all
```

Paketti:

- tunnistaa asennetut sovellukset `winget list` -komennolla
- käyttää Windowsin uninstall-rekisteriä fallback-tarkistuksena
- erottaa tilat `WingetInstalled`, `RegistryOnly`, `NotInstalled` ja `Unknown`
- päivittää vain winget-hallittavat allowlist-sovellukset
- ei asenna puuttuvia sovelluksia
- ei aja `winget upgrade --all`
- kirjaa tulokset paikalliseen lokikansioon
- antaa Intune-exporttiin tiiviit tulosrivit
- sisältää offline-työkalun teknikon käsiajoa varten

## Pääversiot

| Osa | Versio | Tiedosto |
|---|---:|---|
| Approved App Updates Detection | v10.3 | `scripts/approved-app-updates/Intune-Winget-AppUpdates-Detection-v10.3-HybridRegistry.ps1` |
| Approved App Updates Remediation | v10.3 | `scripts/approved-app-updates/Intune-Winget-AppUpdates-Remediation-v10.3-HybridRegistry-AllNonFatal.ps1` |
| Log Summary Detection | v10 | `scripts/log-summary/Winget-LogSummary-Detection-v10.ps1` |
| Log Summary NoOp Remediation | v10 | `scripts/log-summary/Winget-LogSummary-NoOp-Remediation-v10.ps1` |
| Offline Technician Tool | v10.3 | `tools/Intune-Winget-Offline-Technician-Tool-v10.3.ps1` |

## Allowlist-sovellukset

```text
7zip.7zip
Notepad++.Notepad++
Mozilla.Firefox
Google.Chrome
Adobe.Acrobat.Reader.32-bit
Adobe.Acrobat.Reader.64-bit
```

## Intune-paketit

### Winget - Approved App Updates

Detection:

```text
Intune-Winget-AppUpdates-Detection-v10.3-HybridRegistry.ps1
```

Remediation:

```text
Intune-Winget-AppUpdates-Remediation-v10.3-HybridRegistry-AllNonFatal.ps1
```

Asetukset:

```text
Run this script using the logged-on credentials: No
Enforce script signature check: No
Run script in 64-bit PowerShell: Yes
```

### Winget - Log Summary

Detection:

```text
Winget-LogSummary-Detection-v10.ps1
```

Remediation:

```text
Winget-LogSummary-NoOp-Remediation-v10.ps1
```

## Lokit

```text
C:\ProgramData\IntuneWingetUpdates\Logs
```

Skriptit poistavat yli 14 päivää vanhat lokit ja rajoittavat logikansion koon 50 MB:iin.

## Intune-output markerit

```text
WINGET_DETECTION_V10_3
WINGET_REMEDIATION_V10_3
WINGET_LOG_SUMMARY_V10
```

## Offline-työkalu

Detection:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Intune-Winget-Offline-Technician-Tool-v10.3.ps1 -Mode Detection
```

Kaikki:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\tools\Intune-Winget-Offline-Technician-Tool-v10.3.ps1
```

Jos PowerShell ei ole elevated, työkalu avaa UAC-kyselyn.

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
| Pester Tests | Repository smoke tests and script validation |
| Public Safety Check | Detects generated output files and unsafe public markers |

## Important safety note

This repository contains remediation scripts that can update approved applications on managed Windows devices. Test with a small pilot group before wider production deployment.

## Pilotointi

1. Aloita 5-10 IT/pilot-laitteella.
2. Aja Hourly yhden työpäivän ajan.
3. Tarkista Intune-exportit ja Log Summary.
4. Laajenna 20-30 laitteeseen.
5. Kun tulokset ovat tasaisia, siirrä Daily-ajoon.

## Huomio

`winget` ei aina tunnista rekisteristä löytyvää sovellusta hallittavaksi paketiksi. Näissä tapauksissa sovellus raportoidaan `RegistryOnly`-tilaan eikä sitä yritetä päivittää väkisin.
