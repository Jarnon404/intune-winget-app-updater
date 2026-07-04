# Intune-asennusohje

## Paketti 1: Winget - Approved App Updates

Detection script:

```text
scripts/approved-app-updates/Intune-Winget-AppUpdates-Detection-v10.3-HybridRegistry.ps1
```

Remediation script:

```text
scripts/approved-app-updates/Intune-Winget-AppUpdates-Remediation-v10.3-HybridRegistry-AllNonFatal.ps1
```

Asetukset:

```text
Run this script using the logged-on credentials: No
Enforce script signature check: No
Run script in 64-bit PowerShell: Yes
```

Pilotissa:

```text
Hourly
```

Tuotannossa:

```text
Daily
```

## Paketti 2: Winget - Log Summary

Detection script:

```text
scripts/log-summary/Winget-LogSummary-Detection-v10.ps1
```

Remediation script:

```text
scripts/log-summary/Winget-LogSummary-NoOp-Remediation-v10.ps1
```

## Exportista seurattavat kentät

```text
WINGET_DETECTION_V10_3
WINGET_REMEDIATION_V10_3
WINGET_LOG_SUMMARY_V10
Status=
SourceUpdateStatus=
WingetInstalledApps=
RegistryOnlyApps=
UpdatedApps=
WarningApps=
RebootPending=
```
