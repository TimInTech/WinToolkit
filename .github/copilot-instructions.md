# Project Guidelines

## Code Style
- Sprache: PowerShell 5.0+, Skripte laufen auf Windows 11 mit Administratorrechten.
- In allen Skripten `Set-StrictMode -Version Latest` beibehalten.
- Fuer Modulskripte ist resilientes Fehlerverhalten Standard: `$ErrorActionPreference = 'Continue'`, einzelne Operationen mit Logging absichern.
- Gemeinsame Hilfsfunktionen nicht duplizieren, stattdessen `lib/Common.ps1` nutzen.

## Architecture
- Das Toolkit ist eine modulare Pipeline mit GUI-Launcher:
  - `Start-Launcher.ps1`: WPF-GUI, Modulstart, Statusanzeige.
  - `00-Bootstrap.ps1`: Voraussetzungen, Hardware-Profil, Basis-Setup.
  - `10-Updates.ps1`: Windows-/Treiber-Updates, optionaler Reboot-Resume-Task.
  - `20-Maintenance.ps1`: Bereinigung, Datenschutz, Dienste, Optimierungen.
  - `30-Repair.ps1`: Interaktive Diagnose und Reparaturmenue.
- `lib/Common.ps1` ist die zentrale Bibliothek fuer Logging, Prompts, Wiederherstellungspunkt, Pending-Reboot-Check und Hardware-Profil.
- Persistente Laufzeitdaten:
  - `state/*.json`: Modulstatus und Hardwaredaten.
  - `logs/*.log`: Audit- und Fehlerprotokolle.
  - `backup/*.reg`: Registry-Backups vor Aenderungen.

## Build and Test
- Kein klassischer Build-Prozess (Skript-Toolkit, kein Kompilat).
- VS Code Task `build` mit `msbuild` ist fuer dieses Repository nicht relevant.
- Ausfuehrung lokal (PowerShell als Administrator):
  - `./Start-Launcher.ps1`
  - `./00-Bootstrap.ps1`
  - `./10-Updates.ps1 [-IncludeDrivers] [-KeineReboot] [-Skip]`
  - `./20-Maintenance.ps1 [-AllesOhneAbfrage] [-NurBericht]`
  - `./30-Repair.ps1`
- Reihenfolge fuer Vollablauf: `00` -> `10` -> `20` -> `30`.

## Conventions
- Vor destruktiven Registry-Aenderungen `Backup-Registry` aus `lib/Common.ps1` verwenden.
- Neue Schritte immer ueber `Write-Log` protokollieren und bestehende Log-Level (`Info`, `Warn`, `Error`, `Success`, `Debug`) nutzen.
- Hardwareabhaengige Entscheidungen auf Basis von `state/hardware.json` treffen (`Get-HardwareProfile`).
- Kritische App-/Paket-Schutzlisten (z. B. in `20-Maintenance.ps1`) nur gezielt erweitern, nicht pauschal entfernen.
- Neue Dateipfade am vorhandenen Layout ausrichten (`logs/`, `state/`, `reports/`, `backup/`).

## Pitfalls
- `00-Bootstrap.ps1` muss zuerst laufen, sonst fehlen `state/bootstrap-ok.json` und ggf. `state/hardware.json`.
- ExecutionPolicy kann durch GPO ueberschrieben werden; nur Process-Scope setzen und Dateien ggf. `Unblock-File`.
- Update-Fortsetzung nach Neustart haengt von geplanter Aufgabe `WinToolkit_UpdateFortsetzung` ab.
- Dieses Toolkit ist fuer Windows 11 ausgelegt; keine Linux/macOS-Kommandos einfuehren.

## Documentation
- Siehe `README.md` fuer Benutzerablauf, FAQ, Dateistruktur und Systemvoraussetzungen.
- Details zu wiederverwendbaren Funktionen stehen in `lib/Common.ps1`.
