# Intune setup guide

## Package 1: Winget - Approved App Updates

Detection script:

```text
scripts/approved-app-updates/Intune-Winget-AppUpdates-Detection-v10.4-HybridRegistry-Discovery.ps1
```

Remediation script:

```text
scripts/approved-app-updates/Intune-Winget-AppUpdates-Remediation-v10.4-HybridRegistry-AllNonFatal.ps1
```

Recommended settings:

```text
Run this script using the logged-on credentials: No
Enforce script signature check: No
Run script in 64-bit PowerShell: Yes
```

Pilot schedule:

```text
Hourly
```

Production schedule:

```text
Daily
```

## Package 2: Winget - Log Summary

Detection script:

```text
scripts/log-summary/Winget-LogSummary-Detection-v10.ps1
```

Remediation script:

```text
scripts/log-summary/Winget-LogSummary-NoOp-Remediation-v10.ps1
```

## Export fields to review

```text
WINGET_DETECTION_V10_4
WINGET_REMEDIATION_V10_4
WINGET_LOG_SUMMARY_V10
Status=
SourceUpdateStatus=
WingetInstalledApps=
RegistryOnlyApps=
NotInstalledApps=
UnknownApps=
UpdatedApps=
WarningApps=
RebootPending=
```

## v10.4 notes

v10.4 adds Hybrid Registry Discovery detection logic and diagnostic winget --name fallback discovery.

The remediation package remains controlled:

```text
Approved application list only
Missing applications are not installed
RegistryOnly applications are skipped by default
Application-level remediation failures are handled as non-fatal warnings
```