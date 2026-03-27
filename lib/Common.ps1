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
            'Info'    { '[INFO]   ' }
            'Warn'    { '[WARN]   ' }
            'Error'   { '[FEHLER] ' }
            'Success' { '[OK]     ' }
            'Debug'   { '[DEBUG]  ' }
            default   { '[INFO]   ' }
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

    $hinweis = if ($Standard_Ja) { '[J/n]' } else { '[j/N]' }

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

    Clear-Host
    Write-Host ""
    Write-Host "  ██╗    ██╗██╗███╗   ██╗    ████████╗ ██████╗  ██████╗ ██╗     ██╗  ██╗██╗████████╗" -ForegroundColor Cyan
    Write-Host "  ██║    ██║██║████╗  ██║    ╚══██╔══╝██╔═══██╗██╔═══██╗██║     ██║ ██╔╝██║╚══██╔══╝" -ForegroundColor Cyan
    Write-Host "  ██║ █╗ ██║██║██╔██╗ ██║       ██║   ██║   ██║██║   ██║██║     █████╔╝ ██║   ██║   " -ForegroundColor Cyan
    Write-Host "  ██║███╗██║██║██║╚██╗██║       ██║   ██║   ██║██║   ██║██║     ██╔═██╗ ██║   ██║   " -ForegroundColor Cyan
    Write-Host "  ╚███╔███╔╝██║██║ ╚████║       ██║   ╚██████╔╝╚██████╔╝███████╗██║  ██╗██║   ██║   " -ForegroundColor Cyan
    Write-Host "   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝       ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝   ╚═╝   " -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Windows 11 Optimierungs-Toolkit v$Version" -ForegroundColor White
    if ($Modul) {
        Write-Host "  Modul: $Modul" -ForegroundColor Gray
    }
    Write-Trennlinie
    Write-Host ""
}

Write-Verbose "Common.ps1 geladen (ToolkitRoot: $Script:ToolkitRoot)"
