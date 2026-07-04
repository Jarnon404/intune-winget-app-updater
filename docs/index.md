# Intune Winget App Updater

Controlled Microsoft Intune Proactive Remediation package for updating approved Windows applications with `winget`.

This repository is different from a read-only audit repository: the remediation script can update applications on managed devices.

## Documentation

- [Intune setup](INTUNE-SETUP.md)
- [Pilot runbook](PILOT-RUNBOOK.md)
- [Quality and safety model](quality-and-safety.md)
- [Changelog](CHANGELOG.md)

## Main scripts

- Approved App Updates detection
- Approved App Updates remediation
- Log Summary detection
- Log Summary no-op remediation
- Offline technician tool

## Safety note

Deploy first to a small pilot group. Do not use broad production targeting until detection, remediation and log summary output are reviewed.
