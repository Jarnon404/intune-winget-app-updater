# Changelog

## v10.3

- Fixed Windows PowerShell 5.1 compatibility.
- Removed dependency on `ProcessStartInfo.ArgumentList.Add(...)`.
- Uses the compatible `ProcessStartInfo.Arguments` model.
- Fixes a case where source update could return wrapper code `9999`.
- Markers:
  - `WINGET_DETECTION_V10_3`
  - `WINGET_REMEDIATION_V10_3`

## v10.2

- Fixed a PowerShell parser issue involving a variable followed by a colon.
- Corrected format:
  - `$AppId:` -> `$($AppId):`

## v10.1

- Added log folder size management.
- Removes log files older than 14 days.
- Keeps the log folder below 50 MB.

## v10

- Major baseline.
- Hybrid detection and remediation.
- RegistryOnly detection.
- Clear Intune output.
- Offline technician tool.