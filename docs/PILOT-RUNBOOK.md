# Pilot runbook

## Before wider rollout

Confirm from Intune exports:

```text
WINGET_DETECTION_V10_4
SourceUpdateStatus=OK
```

Confirm that the detection output shows expected app discovery states:

```text
WingetInstalledApps=
RegistryOnlyApps=
NotInstalledApps=
UnknownApps=
```

The following errors should not appear:

```text
Variable reference is not valid
You cannot call a method on a null-valued expression
TechnicalFailure_9999
Add-Content : Stream was not readable
```

## Successful update

Example:

```text
UpdatedApps=Google.Chrome
```

If the output shows:

```text
UpdatedApps=None
```

no applications were updated.

## RegistryOnly applications

If an application is detected as RegistryOnly, it means it was found from the Windows uninstall registry but was not confidently matched by winget.

Default behavior:

```text
RegistryOnly applications are skipped
No forced update is attempted
No missing application install is performed
```

Review RegistryOnly results before deciding whether an application should be handled differently.

## Missing applications

If an approved application is not installed, the package does not install it.

Expected behavior:

```text
NotInstalledApps=
```

This package is for controlled updates, not application deployment.

## Reboot pending

```text
RebootPending=True
```

Restart the device before interpreting installer failures.

## Script technical codes

```text
9998 = command timeout
9999 = wrapper or process launch technical failure
```

## Recommended pilot flow

```text
1. Deploy to a small pilot group.
2. Run hourly for one business day.
3. Review detection and remediation exports.
4. Confirm WINGET_DETECTION_V10_4 and WINGET_REMEDIATION_V10_4 output.
5. Confirm SourceUpdateStatus=OK.
6. Review UpdatedApps, WarningApps, RegistryOnlyApps and RebootPending.
7. Move to daily schedule only after stable pilot results.
```