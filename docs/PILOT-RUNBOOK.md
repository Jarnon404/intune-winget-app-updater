# Pilot runbook

## Before wider rollout

Confirm from Intune exports:

```text
WINGET_DETECTION_V10_3
SourceUpdateStatus=OK
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