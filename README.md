# 🛠️ WinToolkit — Windows 11 Optimization Suite

<div align="right">
  <a href="README.de.md">
    <img src="https://img.shields.io/badge/🇩🇪_Deutsch-Zur deutschen Version-blue?style=for-the-badge" alt="Deutsche Version"/>
  </a>
</div>

> **Developed by [TimInTech](https://github.com/TimInTech)**

A modular PowerShell toolkit that makes your Windows 11 PC faster, cleaner and more private — automatically, safely, and with full rollback support.

---

## ✨ What does this toolkit do?

This toolkit removes unnecessary bloatware pre-installed by Microsoft, disables telemetry features, installs all available updates, and repairs common Windows issues — all with a few clicks and no technical knowledge required.

- **No data is sent** — runs fully locally on your PC
- **Automatic rollback** — a restore point is created before every change
- **Modular design** — run all modules or pick exactly what you need

---

## 🚀 Quick Start (3 Steps)

**Step 1:** Right-click `Start-Launcher.ps1` → **"Run with PowerShell"**

**Step 2:** Windows asks for administrator rights → click **"Yes"**

**Step 3:** Click **"Run all modules"** — or start individual modules as needed

> **Tip:** If Windows asks whether the script is trusted, click "More info" → "Run anyway".

---

## 📦 Modules

| Module | Purpose | When to use |
|--------|---------|-------------|
| **00 – Bootstrap** | System check & hardware detection | Always run first |
| **10 – Updates** | Windows & driver updates | Fresh install or monthly maintenance |
| **20 – Maintenance** | Bloatware removal, privacy, optimization | Slow PC or new installation |
| **30 – Repair** | System file check, diagnostics, restore | Crashes or Windows errors |

### Recommended order
```
Fresh install / New PC:    00 → 10 → 20 → 30
Slow PC:                   20 (Maintenance)
Windows errors / Crashes:  30 (Repair & Diagnostics)
```

---

## 🔒 What gets removed — what stays?

| Category | Removed ✗ | Kept ✓ |
|----------|-----------|--------|
| **Microsoft apps** | Xbox Games, Bing Weather, Bing News, Solitaire, Zune, Cortana | Edge, Calculator, Notepad, Paint, Photos, Store |
| **Communication** | Teams (Personal), Skype, Phone Link | Outlook (if installed) |
| **Entertainment** | Netflix, Disney+, Spotify, Candy Crush (pre-installed) | — |
| **HP-specific** | SupportAssist ads, HP Wolf Security (consumer) | HP printer drivers |
| **Windows services** | Telemetry, Xbox network services, Fax service | Windows Update, Defender, Print service |
| **Advertising** | Start menu ads, suggestions, Bing search in Start | — |

> **Important:** Your personal files (photos, documents, downloads) are **never touched**. The toolkit only modifies Windows system settings and pre-installed apps.

---

## ↩️ How to undo changes

### Restore Point
The toolkit **automatically creates a restore point** before making any changes.

**To restore Windows:**
1. Run **30 – Repair & Diagnostics**
2. Select **Option [4] – Load Restore Point**
3. Choose the point before the desired date
4. Windows restarts and reverts to the previous state

**Alternatively via Windows:**
- Start Menu → "Create a restore point" → "System Protection" tab → "System Restore"

### Registry Backups
Before every registry change, the toolkit saves a backup in the `backup\` folder. These `.reg` files can be re-applied with a double-click.

---

## ❓ FAQ

**Q: Do I need to restart after optimization?**
Yes, a restart is recommended so all changes take full effect.

**Q: How long does it take?**
- Bootstrap: 1–2 minutes
- Updates: 15–60 minutes (depending on pending updates)
- Maintenance: 10–30 minutes
- Repair/Diagnostics: 5–20 minutes

**Q: Will my internet get slower?**
No — the opposite. The toolkit optimizes network settings and disables background services that consume bandwidth.

**Q: Will my programs be deleted?**
No. Only pre-installed Windows apps that Microsoft added without your consent (like Xbox Games or Candy Crush) are removed. All programs you installed yourself remain untouched.

**Q: Can I run individual modules multiple times?**
Yes. All modules are designed to be run multiple times without causing harm.

**Q: What happens if an error occurs?**
All actions are logged in the `logs\` folder. You can open the log file and report the issue with that information.

**Q: Does this work on Windows 10?**
The toolkit is optimized for Windows 11. Some modules may work on Windows 10, but they are untested.

---

## 📁 File Structure

```
WinToolkit\
├── Start-Launcher.ps1      ← Entry point (GUI)
├── 00-Bootstrap.ps1        ← System check & hardware detection
├── 10-Updates.ps1          ← Windows updates & drivers
├── 20-Maintenance.ps1      ← Cleanup, privacy & optimization
├── 30-Repair.ps1           ← Repair & diagnostics
│
├── lib\
│   └── Common.ps1          ← Shared function library
│
├── logs\                   ← Automatic run logs
├── state\                  ← Runtime state files (bootstrap, updates, etc.)
├── backup\                 ← Registry backups before changes
└── reports\                ← HTML reports after maintenance
```

---

## ⚙️ System Requirements

- Windows 11 (Build 22000 or newer)
- Administrator account
- PowerShell 5.0 or newer (pre-installed in Windows 11)
- At least 5 GB free space on `C:\`
- Internet connection (recommended for updates)

---

<div align="center">

**WinToolkit v1.0.0**

Made with ❤️ by [TimInTech](https://github.com/TimInTech)

</div>
