# Pilot-runbook

## Ennen laajennusta

Varmista exporteista:

```text
WINGET_DETECTION_V10_3
SourceUpdateStatus=OK
```

Ei pitäisi näkyä:

```text
Variable reference is not valid
You cannot call a method on a null-valued expression
TechnicalFailure_9999
Add-Content : Stream was not readable
```

## Onnistunut päivitys

```text
UpdatedApps=Google.Chrome
```

Jos näkyy:

```text
UpdatedApps=None
```

sovelluksia ei päivittynyt.

## Reboot pending

```text
RebootPending=True
```

Käynnistä laite uudelleen ennen installer-virheiden tulkintaa.

## Skriptin omat tekniset koodit

```text
9998 = command timeout
9999 = wrapper/prosessikäynnistyksen tekninen virhe
```
