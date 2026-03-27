#Requires -Version 5.0
<#
.SYNOPSIS
    Gemeinsame Bibliotheksfunktionen fuer das Windows 11 Optimierungs-Toolkit.
.DESCRIPTION
    Stellt zentrale Hilfsfunktionen bereit: Logging, Fortschrittsanzeige,
    Hardware-Profile, Bestaetigungsabfragen und Wiederherstellungspunkte.
.NOTES
    Datei   : lib\Common.ps1
    Version : 1.0.0
    Autor   : TimInTech (https://github.com/TimInTech)
#>

# ─────────────────────────────────────────────────────────────────────────────
# Globale Variablen
# ─────────────────────────────────────────────────────────────────────────────
$Script:LogPfad     = $null
$Script:ToolkitRoot = Split-Path -Parent $PSScriptRoot   # lib\ -> root
$Script:LangCode        = 'de'   # Default, overwritten by Initialize-Language
$Script:LangInitialized = $false

# ─────────────────────────────────────────────────────────────────────────────
# Sprach-Strings (EN / DE)
# ─────────────────────────────────────────────────────────────────────────────
$Script:Strings = @{
    en = @{
        log_info         = '[INFO]   '
        log_warn         = '[WARN]   '
        log_error        = '[ERROR]  '
        log_ok           = '[OK]     '
        log_debug        = '[DEBUG]  '
        confirm_yes      = '[Y/n]'
        confirm_no       = '[y/N]'
        press_key        = '  Press any key to exit...'
        mod_bootstrap    = '00 - Bootstrap & System Check'
        mod_updates      = '10 - Updates & Drivers'
        mod_maintenance  = '20 - Maintenance & Privacy'
        mod_repair       = '30 - Repair & Diagnostics'
        bs_next          = '  Next step:'
        bs_opt1          = '    Run:  10-Updates.ps1'
        bs_opt2          = '    or:   20-Maintenance.ps1'
        bs_complete      = 'Bootstrap completed successfully.'
        bs_hw            = '  Hardware detected:'
        bs_ssd_yes       = 'Yes'
        bs_ssd_no        = 'No'
        bs_bat_yes       = 'Yes'
        bs_bat_no        = 'No'
        bs_done_title    = ' Bootstrap completed '
        upd_skip         = '-Skip set: update steps will be skipped.'
        upd_driver_q     = 'Install driver updates now?'
        upd_reboot_30    = '  RESTART IN 30 SECONDS'
        upd_reboot_auto  = '  Updates will continue after restart automatically.'
        upd_reboot_stop  = '  To cancel: Shutdown /a'
        upd_done_title   = ' Updates completed '
        upd_done_msg     = 'All update steps completed successfully.'
        upd_next         = '  Next step: 20-Maintenance.ps1'
        upd_reboot_q     = 'Restart now?'
        maint_done_title = ' Maintenance completed '
        maint_done_msg   = 'All maintenance steps completed.'
        maint_reboot_warn = '  IMPORTANT: A restart is recommended to apply all changes.'
        maint_reboot_q   = 'Restart now?'
        maint_report     = '  Report:'
        maint_report_hint = '  (Open in browser for formatted view)'
        repair_select    = 'Select: '
    }
    de = @{
        log_info         = '[INFO]   '
        log_warn         = '[WARN]   '
        log_error        = '[FEHLER] '
        log_ok           = '[OK]     '
        log_debug        = '[DEBUG]  '
        confirm_yes      = '[J/n]'
        confirm_no       = '[j/N]'
        press_key        = '  Druecke eine Taste zum Beenden...'
        mod_bootstrap    = '00 - Bootstrap & Systemcheck'
        mod_updates      = '10 - Updates & Treiber'
        mod_maintenance  = '20 - Bereinigung & Datenschutz'
        mod_repair       = '30 - Reparatur & Diagnose'
        bs_next          = '  Naechster Schritt:'
        bs_opt1          = '    Starte: 10-Updates.ps1'
        bs_opt2          = '    oder:   20-Maintenance.ps1'
        bs_complete      = 'Bootstrap erfolgreich abgeschlossen.'
        bs_hw            = '  Hardware erkannt:'
        bs_ssd_yes       = 'Ja'
        bs_ssd_no        = 'Nein'
        bs_bat_yes       = 'Ja'
        bs_bat_no        = 'Nein'
        bs_done_title    = ' Bootstrap abgeschlossen '
        upd_skip         = '-Skip gesetzt: Updates werden uebersprungen.'
        upd_driver_q     = 'Treiber-Updates jetzt installieren?'
        upd_reboot_30    = '  NEUSTART IN 30 SEKUNDEN'
        upd_reboot_auto  = '  Updates werden nach dem Neustart automatisch fortgesetzt.'
        upd_reboot_stop  = '  Zum Abbrechen: Shutdown /a'
        upd_done_title   = ' Updates abgeschlossen '
        upd_done_msg     = 'Alle Update-Schritte erfolgreich abgeschlossen.'
        upd_next         = '  Naechster Schritt: 20-Maintenance.ps1'
        upd_reboot_q     = 'Jetzt neu starten?'
        maint_done_title = ' Maintenance abgeschlossen '
        maint_done_msg   = 'Alle Wartungsschritte abgeschlossen.'
        maint_reboot_warn = '  WICHTIG: Ein Neustart wird empfohlen um alle Aenderungen anzuwenden.'
        maint_reboot_q   = 'Jetzt neu starten?'
        maint_report     = '  Bericht:'
        maint_report_hint = '  (Im Browser oeffnen fuer formatierte Ansicht)'
        repair_select    = 'Auswahl: '
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Initialize-Log
# Erstellt eine neue Log-Datei mit Zeitstempel im Namen unter logs\
# ─────────────────────────────────────────────────────────────────────────────
function Initialize-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Praefix   # z. B. "Bootstrap", "Updates", "Maintenance"
    )

    try {
        $logOrdner = Join-Path $Script:ToolkitRoot 'logs'
        if (-not (Test-Path $logOrdner)) {
            New-Item -ItemType Directory -Path $logOrdner -Force | Out-Null
        }

        $zeitstempel     = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $logDateiname    = "${Praefix}_${zeitstempel}.log"
        $Script:LogPfad  = Join-Path $logOrdner $logDateiname

        # Header in Log-Datei schreiben
        $header = @"
================================================================================
  Windows 11 Optimierungs-Toolkit - Log
  Modul    : $Praefix
  Gestartet: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
  Benutzer : $env:USERNAME  |  Rechner: $env:COMPUTERNAME
================================================================================
"@
        $header | Out-File -FilePath $Script:LogPfad -Encoding UTF8

        Write-Log -Nachricht "Log initialisiert: $Script:LogPfad" -Ebene 'Info'
        return $Script:LogPfad
    }
    catch {
        Write-Warning "Konnte Log-Datei nicht erstellen: $($_.Exception.Message)"
        $Script:LogPfad = $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-Log
# Schreibt eine Meldung mit Zeitstempel in Konsole und Log-Datei
# Ebene: Info | Warn | Error | Success | Debug
# ─────────────────────────────────────────────────────────────────────────────
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Nachricht,

        [Parameter(Position = 1)]
        [ValidateSet('Info', 'Warn', 'Error', 'Success', 'Debug')]
        [string]$Ebene = 'Info',

        [Parameter()]
        [switch]$OhneKonsole,

        [Parameter()]
        [switch]$OhneDatei
    )

    $zeitstempel = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $zeile       = "[$zeitstempel] [$Ebene] $Nachricht"

    # Konsole: Farbe nach Ebene
    if (-not $OhneKonsole) {
        $farbe = switch ($Ebene) {
            'Info'    { 'Cyan'    }
            'Warn'    { 'Yellow'  }
            'Error'   { 'Red'     }
            'Success' { 'Green'   }
            'Debug'   { 'Gray'    }
            default   { 'White'   }
        }

        $praefix = switch ($Ebene) {
            'Info'    { Get-LStr 'log_info'  }
            'Warn'    { Get-LStr 'log_warn'  }
            'Error'   { Get-LStr 'log_error' }
            'Success' { Get-LStr 'log_ok'    }
            'Debug'   { Get-LStr 'log_debug' }
            default   { Get-LStr 'log_info'  }
        }

        Write-Host "$praefix $Nachricht" -ForegroundColor $farbe
    }

    # In Datei schreiben
    if (-not $OhneDatei -and $Script:LogPfad) {
        try {
            $zeile | Out-File -FilePath $Script:LogPfad -Append -Encoding UTF8
        }
        catch {
            # Stille Fehlerbehandlung - Log-Schreiben darf Skript nicht stoppen
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Confirm-Schritt
# Zeigt eine J/N-Abfrage und gibt $true (Ja) oder $false (Nein) zurueck
# ─────────────────────────────────────────────────────────────────────────────
function Confirm-Schritt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Frage,

        [Parameter()]
        [switch]$Standard_Ja   # Bei Enter -> Ja (Standard: Nein)
    )

    $hinweis = if ($Standard_Ja) { Get-LStr 'confirm_yes' } else { Get-LStr 'confirm_no' }

    Write-Host ""
    Write-Host "  $Frage $hinweis " -ForegroundColor Yellow -NoNewline

    try {
        $antwort = Read-Host
    }
    catch {
        # Keine interaktive Konsole -> Standard verwenden
        Write-Log -Nachricht "Keine interaktive Eingabe moeglich, verwende Standard" -Ebene 'Warn'
        return $Standard_Ja.IsPresent
    }

    if ([string]::IsNullOrWhiteSpace($antwort)) {
        return $Standard_Ja.IsPresent
    }

    $jaAntworten = @('j', 'ja', 'y', 'yes', '1')
    return ($antwort.Trim().ToLower() -in $jaAntworten)
}

# ─────────────────────────────────────────────────────────────────────────────
# Show-Fortschritt
# Write-Progress-Wrapper mit optionaler Log-Ausgabe
# ─────────────────────────────────────────────────────────────────────────────
function Show-Fortschritt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Aktivitaet,        # Haupttitel der Fortschrittsleiste

        [Parameter(Mandatory = $true)]
        [string]$Status,            # Aktueller Status-Text

        [Parameter()]
        [int]$Prozent = -1,         # 0-100; -1 = unbestimmt

        [Parameter()]
        [int]$Id = 1,               # Fortschritts-ID (fuer verschachtelte Balken)

        [Parameter()]
        [int]$ParentId = -1,        # Uebergeordnete ID

        [Parameter()]
        [switch]$Abschliessen,      # Schliesst den Fortschrittsbalken

        [Parameter()]
        [switch]$Protokollieren     # Schreibt Status zusaetzlich ins Log
    )

    $params = @{
        Activity = $Aktivitaet
        Status   = $Status
        Id       = $Id
    }

    if ($ParentId -ge 0)    { $params['ParentId']          = $ParentId }
    if ($Prozent -ge 0)     { $params['PercentComplete']   = $Prozent  }
    if ($Abschliessen)      { $params['Completed']         = $true     }

    Write-Progress @params

    if ($Protokollieren) {
        Write-Log -Nachricht "$Aktivitaet - $Status" -Ebene 'Info'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# New-Wiederherstellungspunkt
# Erstellt einen Systemwiederherstellungspunkt mit Fallback-Behandlung
# ─────────────────────────────────────────────────────────────────────────────
function New-Wiederherstellungspunkt {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Beschreibung = "Windows 11 Optimierungs-Toolkit - $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
    )

    Write-Log -Nachricht "Erstelle Systemwiederherstellungspunkt..." -Ebene 'Info'

    try {
        # Systemwiederherstellung pruefen ob aktiviert
        $srStatus = Get-ItemProperty `
            -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' `
            -Name 'RPSessionInterval' -ErrorAction SilentlyContinue

        # Sicherstellen, dass Systemwiederherstellung fuer C:\ aktiv ist
        $vssService = Get-Service -Name 'VSS' -ErrorAction SilentlyContinue
        if ($vssService -and $vssService.Status -ne 'Running') {
            Start-Service -Name 'VSS' -ErrorAction SilentlyContinue
        }

        # Wiederherstellungspunkt anlegen
        $params = @{
            Description              = $Beschreibung
            RestorePointType         = 'MODIFY_SETTINGS'
            ErrorAction              = 'Stop'
        }
        Checkpoint-Computer @params

        Write-Log -Nachricht "Wiederherstellungspunkt erstellt: '$Beschreibung'" -Ebene 'Success'
        return $true
    }
    catch [System.Runtime.InteropServices.COMException] {
        # Zu frueh nach dem letzten Punkt (Windows-Limit: 1x pro 24h)
        if ($_.Exception.HResult -eq -2147023838) {
            Write-Log -Nachricht "Wiederherstellungspunkt bereits heute erstellt (Windows-Limit). Wird uebersprungen." -Ebene 'Warn'
        }
        else {
            Write-Log -Nachricht "COM-Fehler beim Erstellen des Wiederherstellungspunkts: $($_.Exception.Message)" -Ebene 'Warn'
        }
        return $false
    }
    catch {
        Write-Log -Nachricht "Wiederherstellungspunkt konnte nicht erstellt werden: $($_.Exception.Message)" -Ebene 'Warn'
        Write-Log -Nachricht "Tipp: Systemwiederherstellung muss fuer Laufwerk C:\ aktiviert sein." -Ebene 'Warn'
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-HardwareProfile
# Liest state\hardware.json und gibt ein PSObject zurueck
# ─────────────────────────────────────────────────────────────────────────────
function Get-HardwareProfile {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Stumm   # Keine Warnmeldung wenn Datei fehlt
    )

    $hardwarePfad = Join-Path $Script:ToolkitRoot 'state\hardware.json'

    try {
        if (-not (Test-Path $hardwarePfad)) {
            if (-not $Stumm) {
                Write-Log -Nachricht "Hardware-Profil nicht gefunden: $hardwarePfad" -Ebene 'Warn'
                Write-Log -Nachricht "Bitte zuerst 00-Bootstrap.ps1 ausfuehren!" -Ebene 'Warn'
            }

            # Leeres Standard-Profil zurueckgeben
            return [PSCustomObject]@{
                OEM        = 'Unbekannt'
                Model      = 'Unbekannt'
                FormFactor = 'Desktop'
                CPU        = 'Unbekannt'
                GPU_Vendor = 'Intel'
                GPU_Model  = 'Unbekannt'
                RAM_GB     = 0
                HasBattery = $false
                IsSSD      = $true
                OS_Build   = 0
                OS_Edition = 'Unbekannt'
            }
        }

        $json    = Get-Content -Path $hardwarePfad -Raw -Encoding UTF8
        $profil  = $json | ConvertFrom-Json

        Write-Log -Nachricht "Hardware-Profil geladen: $($profil.OEM) $($profil.Model)" -Ebene 'Info'
        return $profil
    }
    catch {
        Write-Log -Nachricht "Fehler beim Lesen des Hardware-Profils: $($_.Exception.Message)" -Ebene 'Error'
        return $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-Trennlinie
# Gibt eine horizontale Trennlinie in der Konsole aus
# ─────────────────────────────────────────────────────────────────────────────
function Write-Trennlinie {
    [CmdletBinding()]
    param(
        [Parameter()]
        [char]$Zeichen = [char]0x2500,   # ─ (Unicode Box Drawing)

        [Parameter()]
        [int]$Breite = 80,

        [Parameter()]
        [string]$Titel = '',

        [Parameter()]
        [ConsoleColor]$Farbe = 'DarkGray'
    )

    if ($Titel) {
        $seitenlaenge = [Math]::Max(0, ($Breite - $Titel.Length - 4) / 2)
        $linie        = ([string]$Zeichen * $seitenlaenge)
        $ausgabe      = "$linie  $Titel  $linie"

        # Auf korrekte Breite trimmen / auffuellen
        if ($ausgabe.Length -lt $Breite) {
            $ausgabe += [string]$Zeichen * ($Breite - $ausgabe.Length)
        }
        elseif ($ausgabe.Length -gt $Breite) {
            $ausgabe = $ausgabe.Substring(0, $Breite)
        }
    }
    else {
        $ausgabe = [string]$Zeichen * $Breite
    }

    Write-Host $ausgabe -ForegroundColor $Farbe
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-AdminRechte
# Prueft ob das aktuelle Skript mit Administrator-Rechten laeuft
# ─────────────────────────────────────────────────────────────────────────────
function Test-AdminRechte {
    $identitaet = [Security.Principal.WindowsIdentity]::GetCurrent()
    $prinzipal  = [Security.Principal.WindowsPrincipal]$identitaet
    return $prinzipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-PendingReboot
# Prueft ob ein Neustart aussteht (verschiedene Registry-Pfade)
# ─────────────────────────────────────────────────────────────────────────────
function Test-PendingReboot {
    [CmdletBinding()]
    param()

    $gruende = @()

    # Windows Update
    $wuPfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    if (Test-Path $wuPfad) { $gruende += 'Windows Update' }

    # Component Based Servicing
    $cbsPfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    if (Test-Path $cbsPfad) { $gruende += 'Component Based Servicing' }

    # Session Manager - PendingFileRenameOperations
    $smPfad  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $pfroWert = Get-ItemProperty -Path $smPfad -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($pfroWert) { $gruende += 'Datei-Umbenennung' }

    # Computer Rename
    $compPfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'
    $aktPfad  = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
    try {
        $neuer = (Get-ItemProperty $compPfad).ComputerName
        $alter = (Get-ItemProperty $aktPfad).ComputerName
        if ($neuer -ne $alter) { $gruende += 'Rechnername-Aenderung' }
    } catch {}

    return [PSCustomObject]@{
        NeuStartNoetig = ($gruende.Count -gt 0)
        Gruende        = $gruende
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Backup-Registry
# Exportiert einen Registry-Pfad als .reg-Datei ins backup\-Verzeichnis
# ─────────────────────────────────────────────────────────────────────────────
function Backup-Registry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPfad,

        [Parameter(Mandatory = $true)]
        [string]$Beschreibung
    )

    try {
        $backupOrdner = Join-Path $Script:ToolkitRoot 'backup'
        if (-not (Test-Path $backupOrdner)) {
            New-Item -ItemType Directory -Path $backupOrdner -Force | Out-Null
        }

        $sicherDateiname = "reg_$(($Beschreibung -replace '[^\w]','_'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
        $zielPfad        = Join-Path $backupOrdner $sicherDateiname

        # reg.exe export (funktioniert auch mit HKCU/HKLM)
        $regPfad = $RegistryPfad -replace '^HKLM:\\', 'HKEY_LOCAL_MACHINE\' `
                                 -replace '^HKCU:\\', 'HKEY_CURRENT_USER\' `
                                 -replace '^HKU:\\',  'HKEY_USERS\'

        $result = & reg.exe export "$regPfad" "$zielPfad" /y 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Nachricht "Registry-Backup erstellt: $sicherDateiname" -Ebene 'Success'
            return $true
        }
        else {
            Write-Log -Nachricht "Registry-Backup fehlgeschlagen fuer: $RegistryPfad" -Ebene 'Warn'
            return $false
        }
    }
    catch {
        Write-Log -Nachricht "Fehler beim Registry-Backup: $($_.Exception.Message)" -Ebene 'Warn'
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-ToolkitRoot
# Gibt den absoluten Pfad des Toolkit-Stammverzeichnisses zurueck
# ─────────────────────────────────────────────────────────────────────────────
function Get-ToolkitRoot {
    return $Script:ToolkitRoot
}

# ─────────────────────────────────────────────────────────────────────────────
# Set-ToolkitRoot
# Setzt den Toolkit-Root explizit (wird von Skripten im Root aufgerufen)
# ─────────────────────────────────────────────────────────────────────────────
function Set-ToolkitRoot {
    param([string]$Pfad)
    $Script:ToolkitRoot = $Pfad
}

# ─────────────────────────────────────────────────────────────────────────────
# Show-ToolkitBanner
# Zeigt den Toolkit-Header in der Konsole an
# ─────────────────────────────────────────────────────────────────────────────
function Show-ToolkitBanner {
    param(
        [string]$Modul = '',
        [string]$Version = '1.0.0'
    )

    Initialize-Language  # Idempotent – sets $Script:LangCode from state or prompt

    $langFlag = if ($Script:LangCode -eq 'en') { '[EN]' } else { '[DE]' }

    Clear-Host
    Write-Host ""
    Write-Host "  ██╗    ██╗██╗███╗   ██╗    ████████╗ ██████╗  ██████╗ ██╗     ██╗  ██╗██╗████████╗" -ForegroundColor Cyan
    Write-Host "  ██║    ██║██║████╗  ██║    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██║ ██╔╝██║╚══██╔══╝" -ForegroundColor Cyan
    Write-Host "  ██║ █╗ ██║██║██╔██╗ ██║       ██║   ██║   ██║██║   ██║██║     █████╔╝ ██║   ██║   " -ForegroundColor Cyan
    Write-Host "  ██║███╗██║██║██║╚██╗██║       ██║   ██║   ██║██║   ██║██║     ██╔═██╗ ██║   ██║   " -ForegroundColor Cyan
    Write-Host "  ╚███╔███╔╝██║██║ ╚████║       ██║   ╚██████╔╝╚██████╔╝███████╗██║  ██╗██║   ██║   " -ForegroundColor Cyan
    Write-Host "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝   ╚═╝   " -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Windows 11 Optimization Toolkit v$Version" -ForegroundColor White
    Write-Host "  by TimInTech  |  github.com/TimInTech/WinToolkit  |  $langFlag" -ForegroundColor DarkGray
    if ($Modul) {
        Write-Host "  Module: $Modul" -ForegroundColor Gray
    }
    Write-Trennlinie
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Initialize-Language
# Loads saved language choice or shows selector. Idempotent.
# ─────────────────────────────────────────────────────────────────────────────
function Initialize-Language {
    [CmdletBinding()]
    param()

    if ($Script:LangInitialized) { return }

    $langPfad = Join-Path $Script:ToolkitRoot 'state\language.json'

    if (Test-Path $langPfad) {
        try {
            $gespeichert = Get-Content $langPfad -Raw | ConvertFrom-Json
            if ($gespeichert.Code -in @('en', 'de')) {
                $Script:LangCode        = $gespeichert.Code
                $Script:LangInitialized = $true
                return
            }
        }
        catch {}
    }

    # Show language selector
    Write-Host ""
    Write-Host "  ──────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Select language  /  Sprache waehlen" -ForegroundColor White
    Write-Host "  ──────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  [1]  English" -ForegroundColor Cyan
    Write-Host "  [2]  Deutsch  (Standard / Default)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host -NoNewline "  Input / Eingabe [1/2, Enter = Deutsch]: " -ForegroundColor Yellow

    $wahl = ''
    try { $wahl = Read-Host } catch {}

    $Script:LangCode        = if ($wahl.Trim() -eq '1') { 'en' } else { 'de' }
    $Script:LangInitialized = $true

    # Persist choice in state\language.json
    try {
        $stateDir = Join-Path $Script:ToolkitRoot 'state'
        if (-not (Test-Path $stateDir)) {
            New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        }
        [PSCustomObject]@{
            Code      = $Script:LangCode
            Timestamp = (Get-Date -Format 'o')
        } | ConvertTo-Json | Out-File -FilePath $langPfad -Encoding UTF8 -Force
    }
    catch {}

    $bestaetigung = if ($Script:LangCode -eq 'en') { '  Language: English' } else { '  Sprache:  Deutsch' }
    Write-Host $bestaetigung -ForegroundColor Green
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-LStr
# Returns a localized string by key. Falls back to the key itself if not found.
# ─────────────────────────────────────────────────────────────────────────────
function Get-LStr {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    $lang = if ($Script:Strings.ContainsKey($Script:LangCode)) { $Script:LangCode } else { 'de' }
    if ($Script:Strings[$lang].ContainsKey($Key)) {
        return $Script:Strings[$lang][$Key]
    }
    return $Key
}

Write-Verbose "Common.ps1 geladen (ToolkitRoot: $Script:ToolkitRoot)"
