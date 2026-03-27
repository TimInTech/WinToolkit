# 🛠️ WinToolkit — Windows 11 Optimierungs-Suite

<div align="right">
  <a href="README.md">
    <img src="https://img.shields.io/badge/🇬🇧_English-Switch to English-blue?style=for-the-badge" alt="English version"/>
  </a>
</div>

> **Entwickelt von [TimInTech](https://github.com/TimInTech)**

Ein modulares PowerShell-Toolkit, das Ihren Windows-11-PC schneller, aufgeräumter und privatsphärefreundlicher macht — automatisch, sicher und mit vollständiger Wiederherstellungsoption.

---

## ✨ Was macht dieses Toolkit?

Dieses Toolkit entfernt unnötige Bloatware, die Microsoft vorinstalliert hat, deaktiviert Telemetriefunktionen, installiert alle verfügbaren Updates und repariert häufige Windows-Probleme — alles mit wenigen Klicks, ohne technische Kenntnisse.

- **Keine Daten werden gesendet** — läuft vollständig lokal auf Ihrem PC
- **Automatische Wiederherstellung** — vor jeder Änderung wird ein Wiederherstellungspunkt erstellt
- **Modulares Design** — alle Module oder genau das ausführen, was Sie brauchen

---

## 🚀 Schnellstart (3 Schritte)

**Schritt 1:** Rechtsklick auf `Start-Launcher.ps1` → **„Mit PowerShell ausführen"**

**Schritt 2:** Windows fragt nach Administratorrechten → **„Ja"** klicken

**Schritt 3:** Im Fenster auf **„Alle Module ausführen"** klicken — oder die Module einzeln starten

> **Tipp:** Wenn Windows fragt, ob das Skript vertrauenswürdig ist, klicken Sie auf „Weitere Informationen" → „Trotzdem ausführen".

---

## 📦 Module

| Modul | Aufgabe | Wann verwenden |
|-------|---------|----------------|
| **00 – Bootstrap** | Systemcheck & Hardware-Erkennung | Immer zuerst ausführen |
| **10 – Updates** | Windows- & Treiber-Updates | Neuinstallation oder monatliche Wartung |
| **20 – Maintenance** | Bloatware-Entfernung, Datenschutz, Optimierung | Langsamer PC oder Neuinstallation |
| **30 – Repair** | Systemdateiprüfung, Diagnose, Wiederherstellung | Abstürze oder Windows-Fehler |

### Empfohlene Reihenfolge
```
Neuinstallation / Neuer PC:    00 → 10 → 20 → 30
Langsamer PC:                  20 (Bereinigung & Datenschutz)
Windows-Fehler / Abstürze:     30 (Reparatur & Diagnose)
```

---

## 🔒 Was wird entfernt – was bleibt?

| Kategorie | Wird entfernt ✗ | Bleibt erhalten ✓ |
|-----------|----------------|-------------------|
| **Microsoft-Apps** | Xbox-Spiele, Bing-Wetter, Bing-News, Solitaire, Zune, Cortana | Edge, Rechner, Notepad, Paint, Fotos, Store |
| **Kommunikation** | Teams (Privat), Skype, Handylink | Outlook (falls installiert) |
| **Unterhaltung** | Netflix, Disney+, Spotify, Candy Crush (vorinstalliert) | — |
| **HP-spezifisch** | SupportAssist-Werbung, HP Wolf Security (Consumer) | HP-Druckertreiber |
| **Windows-Dienste** | Telemetrie, Xbox-Netzwerkdienste, Faxdienst | Windows Update, Defender, Druckerdienst |
| **Werbung** | Werbung im Startmenü, Vorschläge, Bing-Suche im Startmenü | — |

> **Wichtig:** Ihre persönlichen Dateien (Fotos, Dokumente, Downloads) werden **niemals angefasst**. Das Toolkit verändert nur Windows-Systemeinstellungen und vorinstallierte Apps.

---

## ↩️ Wie kann ich Änderungen rückgängig machen?

### Wiederherstellungspunkt
Das Toolkit erstellt **automatisch einen Wiederherstellungspunkt**, bevor es Änderungen vornimmt.

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

## ❓ Häufig gestellte Fragen (FAQ)

**F: Muss ich den Computer danach neu starten?**
Ja, ein Neustart nach der Optimierung ist empfehlenswert, damit alle Änderungen vollständig übernommen werden.

**F: Wie lange dauert das?**
- Bootstrap: 1–2 Minuten
- Updates: 15–60 Minuten (je nach Anzahl der Updates)
- Bereinigung: 10–30 Minuten
- Reparatur/Diagnose: 5–20 Minuten

**F: Wird mein Internet langsamer?**
Nein, im Gegenteil. Das Toolkit optimiert Netzwerkeinstellungen und deaktiviert Hintergrunddienste, die Bandbreite verbrauchen.

**F: Werden meine Programme gelöscht?**
Nein. Es werden nur vorinstallierte Windows-Apps entfernt, die Microsoft ohne Ihre Zustimmung installiert hat (wie Xbox-Spiele oder Candy Crush). Alle Programme, die Sie selbst installiert haben, bleiben unberührt.

**F: Kann ich einzelne Module mehrfach ausführen?**
Ja. Alle Module sind so gestaltet, dass sie mehrfach ausgeführt werden können, ohne Schaden anzurichten.

**F: Was passiert, wenn ein Fehler auftritt?**
Das Toolkit protokolliert alle Aktionen im Ordner `logs\`. Bei Fehlern können Sie die Log-Datei öffnen und das Problem mit diesen Informationen melden.

**F: Funktioniert das Toolkit auch mit Windows 10?**
Das Toolkit ist für Windows 11 optimiert. Einzelne Module können auf Windows 10 funktionieren, sind aber nicht getestet.

---

## 📁 Dateistruktur

```
WinToolkit\
├── Start-Launcher.ps1      ← Einstiegspunkt (GUI)
├── 00-Bootstrap.ps1        ← Systemcheck & Hardware-Erkennung
├── 10-Updates.ps1          ← Windows-Updates & Treiber
├── 20-Maintenance.ps1      ← Bereinigung, Datenschutz & Optimierung
├── 30-Repair.ps1           ← Reparatur & Diagnose
│
├── lib\
│   └── Common.ps1          ← Gemeinsame Funktionsbibliothek
│
├── logs\                   ← Automatische Protokolle
├── state\                  ← Laufzeit-Zustandsdateien (Bootstrap, Updates, etc.)
├── backup\                 ← Registry-Backups vor Änderungen
└── reports\                ← HTML-Berichte nach der Bereinigung
```

---

## ⚙️ Systemvoraussetzungen

- Windows 11 (Build 22000 oder neuer)
- Administrator-Konto
- PowerShell 5.0 oder neuer (in Windows 11 vorinstalliert)
- Mindestens 5 GB freier Speicherplatz auf `C:\`
- Internetverbindung (für Updates empfohlen)

---

<div align="center">

**WinToolkit v1.0.0**

Entwickelt mit ❤️ von [TimInTech](https://github.com/TimInTech)

</div>
