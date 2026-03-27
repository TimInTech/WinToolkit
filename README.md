# 🛠 Windows 11 Optimierungs-Toolkit

## Was macht dieses Toolkit?

Dieses Toolkit macht Ihren Windows-11-Computer schneller, sicherer und aufgeräumter. Es entfernt unnötige Programme, die Microsoft vorinstalliert hat, schaltet Funktionen aus, die Daten an Microsoft senden, installiert alle verfügbaren Updates und repariert häufige Windows-Probleme – alles mit wenigen Klicks, ohne technische Kenntnisse.

---

## So starten Sie es (3 Schritte)

**Schritt 1:** Rechtsklick auf `Start-Launcher.ps1` → **„Mit PowerShell ausführen"**

**Schritt 2:** Windows fragt nach Administratorrechten → **„Ja"** klicken

**Schritt 3:** Im Fenster auf **„Alle Module ausführen"** klicken – oder die Module einzeln starten

> **Tipp:** Wenn Windows fragt ob das Skript vertrauenswürdig ist, klicken Sie auf „Ausführen" oder „Weitere Informationen" → „Trotzdem ausführen".

---

## Wann nutze ich welches Modul?

### Frisch installiertes Windows / Neuer PC
Führen Sie alle Module der Reihe nach aus:
1. **00 – Bootstrap:** Erkennt Ihren PC und prüft ob alles bereit ist
2. **10 – Updates:** Installiert alle Windows-Updates und aktualisiert Programme
3. **20 – Bereinigung:** Entfernt Bloatware, optimiert Einstellungen

### Langsamer PC
Starten Sie direkt **20 – Bereinigung & Datenschutz**. Es räumt temporäre Dateien auf, entfernt unnötige Autostart-Programme und optimiert die Windows-Einstellungen.

### Windows-Fehler / Abstürze
Starten Sie **30 – Reparatur & Diagnose**. Das Programm prüft Systemdateien, analysiert Fehlerprotokolle und kann die häufigsten Probleme automatisch beheben.

---

## Was wird entfernt – was bleibt?

| Kategorie | Wird entfernt ✗ | Bleibt erhalten ✓ |
|-----------|----------------|-------------------|
| **Microsoft-Apps** | Xbox-Spiele, Bing-Wetter, Bing-News, Solitaire, Zune Music/Video, Cortana | Edge, Rechner, Notepad, Paint, Fotos, Store |
| **Kommunikation** | Teams (Privat), Skype, Handylink | Outlook (falls installiert) |
| **Unterhaltung** | Netflix, Disney+, Spotify, Candy Crush (wenn vorinstalliert) | — |
| **HP-spezifisch** | SupportAssist-Werbung, HP Wolf Security (Consumer-Version) | HP-Druckertreiber |
| **Windows-Dienste** | Telemetrie, Xbox-Netzwerkdienste, Faxdienst | Windows Update, Defender, Druckerdienst |
| **Werbung** | Werbung im Startmenü, Vorschläge, Bing-Suche im Startmenü | — |

> **Wichtig:** Keine Ihrer persönlichen Dateien (Fotos, Dokumente, Downloads) werden angefasst. Das Toolkit verändert nur Windows-Systemeinstellungen und vorinstallierte Apps.

---

## Wie kann ich Änderungen rückgängig machen?

### Wiederherstellungspunkt
Das Toolkit erstellt **automatisch einen Wiederherstellungspunkt** bevor es Änderungen vornimmt. Das ist wie ein Foto von Ihrem Windows-Zustand zu diesem Zeitpunkt.

**So stellen Sie Windows wieder her:**

1. Starten Sie **30 – Reparatur & Diagnose**
2. Wählen Sie **Option [4] – Wiederherstellungspunkt laden**
3. Wählen Sie den Punkt vor dem gewünschten Datum
4. Windows startet neu und ist wieder im alten Zustand

**Alternativ über Windows:**
- Startmenü → „Wiederherstellungspunkt erstellen" → Tab „Systemschutz" → „Systemwiederherstellung"

### Registry-Backups
Vor jeder Registry-Änderung speichert das Toolkit automatisch eine Sicherungskopie im Ordner `backup\`. Diese `.reg`-Dateien können Sie per Doppelklick wieder einspielen.

---

## Häufig gestellte Fragen (FAQ)

**F: Muss ich den Computer danach neu starten?**
Ja, ein Neustart nach der Optimierung ist empfehlenswert, damit alle Änderungen vollständig übernommen werden.

**F: Wie lange dauert das?**
- Bootstrap: 1–2 Minuten
- Updates: 15–60 Minuten (je nach Anzahl der Updates)
- Bereinigung: 10–30 Minuten
- Reparatur/Diagnose: 5–20 Minuten

**F: Wird mein Internet langsamer?**
Nein, im Gegenteil. Das Toolkit optimiert Netzwerkeinstellungen für schnellere Verbindungen und deaktiviert Hintergrunddienste, die Bandbreite verbrauchen.

**F: Werden meine Programme gelöscht?**
Nein. Es werden nur vorinstallierte Windows-Apps entfernt, die Microsoft ohne Ihre Zustimmung installiert hat (wie Xbox-Spiele oder Candy Crush). Alle Programme, die Sie selbst installiert haben, bleiben unberührt.

**F: Kann ich einzelne Module mehrfach ausführen?**
Ja. Alle Module sind so gestaltet, dass sie mehrfach ausgeführt werden können, ohne Schaden anzurichten.

**F: Was passiert, wenn ein Fehler auftritt?**
Das Toolkit protokolliert alle Aktionen im Ordner `logs\`. Bei Fehlern können Sie die Log-Datei öffnen und sich an den Support wenden.

**F: Funktioniert das Toolkit auch mit Windows 10?**
Das Toolkit ist für Windows 11 optimiert. Einzelne Module können auf Windows 10 funktionieren, sind aber nicht getestet.

**F: Was bedeutet „Als Administrator ausführen"?**
Viele Windows-Optimierungen erfordern erhöhte Rechte. Das ist vergleichbar damit, dass ein Hausbesitzer mehr Rechte in seinem Haus hat als ein Besucher. Das Toolkit fordert diese Rechte automatisch an.

**F: Werden Daten an Dritte gesendet?**
Nein. Das Toolkit arbeitet vollständig lokal auf Ihrem PC. Es werden keine Daten gesendet oder gesammelt.

---

## Dateistruktur

```
WinToolkit\
├── Start-Launcher.ps1      ← Hier starten (GUI)
├── 00-Bootstrap.ps1        ← Systemcheck & Hardware-Erkennung
├── 10-Updates.ps1          ← Windows-Updates & Treiber
├── 20-Maintenance.ps1      ← Bereinigung & Datenschutz
├── 30-Repair.ps1           ← Reparatur & Diagnose
│
├── lib\
│   └── Common.ps1          ← Gemeinsame Bibliothek
│
├── logs\                   ← Automatische Protokolle
├── state\                  ← Zustandsdateien (Bootstrap, Updates, etc.)
├── backup\                 ← Registry-Backups vor Änderungen
└── reports\                ← HTML-Berichte nach der Bereinigung
```

---

## Systemvoraussetzungen

- Windows 11 (Build 22000 oder neuer)
- Administrator-Konto
- PowerShell 5.0 oder neuer (in Windows 11 vorinstalliert)
- Mindestens 5 GB freier Speicherplatz auf C:\
- Internetverbindung (für Updates empfohlen)

---

*Windows 11 Optimierungs-Toolkit v1.0.0 – Erstellt für HP Z2 Tower G4 und andere Windows-11-Systeme*
