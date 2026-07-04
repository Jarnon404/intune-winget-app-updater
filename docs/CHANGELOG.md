# Changelog

## v10.3

- Korjattu Windows PowerShell 5.1 -yhteensopivuusongelma.
- Ei käytetä enää `ProcessStartInfo.ArgumentList.Add(...)`.
- Käytetään yhteensopivaa `ProcessStartInfo.Arguments`-mallia.
- Korjaa tilanteen, jossa source update päätyi wrapper-koodiin `9999`.
- Markerit:
  - `WINGET_DETECTION_V10_3`
  - `WINGET_REMEDIATION_V10_3`

## v10.2

- Korjattu PowerShell-parserivirhe muuttujan ja kaksoispisteen kanssa.
- Korjattu muoto:
  - `$AppId:` -> `$($AppId):`

## v10.1

- Lisätty logikansion koonhallinta.
- Poistaa yli 14 päivää vanhat lokit.
- Pitää logikansion alle 50 MB.

## v10

- Major baseline.
- Hybrid detection/remediation.
- RegistryOnly-tunnistus.
- Selkeä Intune-output.
- Offline technician tool.
