#Requires -Version 5.0
<#
.SYNOPSIS
    Bootstrap-Skript fuer das Windows 11 Optimierungs-Toolkit.
.DESCRIPTION
    Prueft Voraussetzungen, erkennt Hardware, legt Ordnerstruktur an und
    erstellt einen Wiederherstellungspunkt. Muss als erstes ausgefuehrt werden.
.NOTES
    Datei   : 00-Bootstrap.ps1
    Version : 1.0.0
    Ausfuehren als Administrator erforderlich.
#>

[CmdletBinding()]
param(
    [switch]$Stumm,          # Keine interaktiven Abfragen
    [switch]$KeineWiederherstellung   # Wiederherstellungspunkt ueberspringen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# Pfade setzen BEVOR Common.ps1 geladen wird
# ─────────────────────────────────────────────────────────────────────────────
$ToolkitRoot = $PSScriptRoot

# Common.ps1 einbinden
. "$ToolkitRoot\lib\Common.ps1"
Set-ToolkitRoot -Pfad $ToolkitRoot

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 1: Self-Elevation (Admin-Rechte sicherstellen)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SelfElevation {
    if (-not (Test-AdminRechte)) {
        Write-Host ""
        Write-Host "  [!] Dieses Skript benoetigt Administrator-Rechte." -ForegroundColor Yellow
        Write-Host "      Starte neu mit erhöhten Rechten..." -ForegroundColor Yellow
        Write-Host ""

        try {
            $argListe = @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                          '-File', "`"$($MyInvocation.ScriptName)`"")
            if ($Stumm)               { $argListe += '-Stumm' }
            if ($KeineWiederherstellung) { $argListe += '-KeineWiederherstellung' }

            Start-Process -FilePath 'powershell.exe' `
                          -ArgumentList $argListe `
                          -Verb RunAs `
                          -Wait

            exit 0
        }
        catch {
            Write-Host "  [FEHLER] Konnte nicht mit Admin-Rechten starten: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Bitte rechtsklick -> 'Als Administrator ausfuehren'" -ForegroundColor Red
            if (-not $Stumm) { pause }
            exit 1
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 2: ExecutionPolicy konfigurieren
# ─────────────────────────────────────────────────────────────────────────────
function Set-AusfuehrungsRichtlinie {
    Write-Log -Nachricht "Prüfe ExecutionPolicy..." -Ebene 'Info'

    try {
        # GPO-gesetzte Richtlinien erkennen (MachinePolicy / UserPolicy haben Vorrang)
        $gpoRichtlinie = Get-ExecutionPolicy -Scope MachinePolicy -ErrorAction SilentlyContinue
        if ($gpoRichtlinie -and $gpoRichtlinie -ne 'Undefined') {
            Write-Log -Nachricht "ExecutionPolicy per GPO gesetzt: $gpoRichtlinie (wird nicht veraendert)" -Ebene 'Warn'
        }
        else {
            Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
            Write-Log -Nachricht "ExecutionPolicy fuer diesen Prozess: Bypass" -Ebene 'Success'
        }

        # Alle .ps1-Dateien im Toolkit entsperren (Zone.Identifier entfernen)
        $ps1Dateien = Get-ChildItem -Path $ToolkitRoot -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
        $entsperrt  = 0
        foreach ($datei in $ps1Dateien) {
            try {
                Unblock-File -Path $datei.FullName -ErrorAction SilentlyContinue
                $entsperrt++
            } catch {}
        }
        Write-Log -Nachricht "$entsperrt Skript-Dateien entsperrt (Unblock-File)" -Ebene 'Info'
    }
    catch {
        Write-Log -Nachricht "Fehler bei ExecutionPolicy: $($_.Exception.Message)" -Ebene 'Warn'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 3: Systemvoraussetzungen pruefen
# ─────────────────────────────────────────────────────────────────────────────
function Test-Voraussetzungen {
    Write-Log -Nachricht "Prüfe Systemvoraussetzungen..." -Ebene 'Info'
    Write-Trennlinie -Titel ' Systemcheck '

    $probleme = @()
    $warnungen = @()

    # --- PowerShell-Version ---
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5) {
        $probleme += "PowerShell $psVersion gefunden, mindestens 5.0 benoetigt"
        Write-Host "  [FEHLER] PowerShell: $psVersion (benoetigt >= 5.0)" -ForegroundColor Red
    }
    else {
        Write-Host "  [OK]     PowerShell $psVersion" -ForegroundColor Green
    }

    # --- Windows 11 Build ---
    try {
        $osBuild = [System.Environment]::OSVersion.Version.Build
        $osInfo  = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $ubr     = $osInfo.UBR
        $osBuildVoll = "$osBuild.$ubr"

        if ($osBuild -lt 22000) {
            $probleme += "Windows Build $osBuild gefunden, Windows 11 (>= 22000) benoetigt"
            Write-Host "  [FEHLER] Windows Build: $osBuildVoll (benoetigt >= 22000 fuer Win11)" -ForegroundColor Red
        }
        else {
            Write-Host "  [OK]     Windows 11 Build $osBuildVoll" -ForegroundColor Green
        }
    }
    catch {
        $warnungen += "OS-Version konnte nicht ermittelt werden: $($_.Exception.Message)"
        Write-Host "  [WARN]   OS-Version konnte nicht vollstaendig ermittelt werden" -ForegroundColor Yellow
    }

    # --- Windows Edition ---
    try {
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
        Write-Host "  [OK]     Windows Edition: $edition" -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN]   Edition konnte nicht ermittelt werden" -ForegroundColor Yellow
    }

    # --- Internetverbindung ---
    Write-Host "  [...]    Prüfe Internetverbindung (8.8.8.8)..." -ForegroundColor Cyan -NoNewline
    try {
        $ping = Test-Connection -ComputerName '8.8.8.8' -Count 2 -Quiet -ErrorAction Stop
        if ($ping) {
            Write-Host "`r  [OK]     Internetverbindung vorhanden           " -ForegroundColor Green
        }
        else {
            Write-Host "`r  [WARN]   Keine Internetverbindung (8.8.8.8 nicht erreichbar)" -ForegroundColor Yellow
            $warnungen += "Keine Internetverbindung - Updates koennen fehlschlagen"
        }
    }
    catch {
        Write-Host "`r  [WARN]   Internetcheck fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow
        $warnungen += "Internetcheck fehlgeschlagen"
    }

    # --- Freier Speicherplatz auf C:\ ---
    try {
        $laufwerk   = Get-PSDrive -Name 'C' -ErrorAction Stop
        $freiGB     = [Math]::Round($laufwerk.Free / 1GB, 1)
        $gesamtGB   = [Math]::Round(($laufwerk.Free + $laufwerk.Used) / 1GB, 1)

        if ($freiGB -lt 5) {
            $probleme += "Nur $freiGB GB auf C:\ frei (benoetigt >= 5 GB)"
            Write-Host "  [FEHLER] Freier Speicher C:\: ${freiGB} GB von ${gesamtGB} GB (benoetigt >= 5 GB)" -ForegroundColor Red
        }
        elseif ($freiGB -lt 15) {
            Write-Host "  [WARN]   Freier Speicher C:\: ${freiGB} GB von ${gesamtGB} GB (wenig Platz)" -ForegroundColor Yellow
            $warnungen += "Wenig freier Speicherplatz auf C:\ ($freiGB GB)"
        }
        else {
            Write-Host "  [OK]     Freier Speicher C:\: ${freiGB} GB von ${gesamtGB} GB" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  [WARN]   Speicherplatz konnte nicht geprueft werden" -ForegroundColor Yellow
    }

    # --- Pending Reboot Check ---
    try {
        $reboot = Test-PendingReboot
        if ($reboot.NeuStartNoetig) {
            Write-Host "  [WARN]   Ausstehender Neustart erkannt: $($reboot.Gruende -join ', ')" -ForegroundColor Yellow
            $warnungen += "Ausstehender Neustart: $($reboot.Gruende -join ', ')"
        }
        else {
            Write-Host "  [OK]     Kein ausstehender Neustart" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  [WARN]   Reboot-Status konnte nicht geprueft werden" -ForegroundColor Yellow
    }

    Write-Host ""

    # Ergebnis auswerten
    if ($probleme.Count -gt 0) {
        Write-Log -Nachricht "KRITISCHE PROBLEME gefunden:" -Ebene 'Error'
        foreach ($p in $probleme) {
            Write-Log -Nachricht "  - $p" -Ebene 'Error'
        }

        if (-not $Stumm) {
            Write-Host "  Kritische Voraussetzungen nicht erfuellt." -ForegroundColor Red
            Write-Host "  Das Toolkit koennte auf diesem System nicht korrekt funktionieren." -ForegroundColor Red
            $weiter = Confirm-Schritt -Frage "Trotzdem fortfahren?"
            if (-not $weiter) {
                Write-Log -Nachricht "Bootstrap vom Benutzer abgebrochen." -Ebene 'Warn'
                exit 1
            }
        }
        return $false
    }

    if ($warnungen.Count -gt 0) {
        foreach ($w in $warnungen) {
            Write-Log -Nachricht "Warnung: $w" -Ebene 'Warn'
        }
    }

    Write-Log -Nachricht "Systemvoraussetzungen: OK ($($warnungen.Count) Warnungen)" -Ebene 'Success'
    return $true
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 4: Hardware-Erkennung
# ─────────────────────────────────────────────────────────────────────────────
function Get-HardwareErmittlung {
    Write-Log -Nachricht "Ermittle Hardware-Informationen..." -Ebene 'Info'
    Write-Trennlinie -Titel ' Hardware-Erkennung '

    $hw = [ordered]@{
        OEM        = 'Unbekannt'
        Model      = 'Unbekannt'
        FormFactor = 'Desktop'
        CPU        = 'Unbekannt'
        GPU_Vendor = 'Intel'
        GPU_Model  = 'Unbekannt'
        RAM_GB     = 0
        HasBattery = $false
        IsSSD      = $false
        OS_Build   = 0
        OS_Edition = 'Unbekannt'
    }

    # --- OEM & Modell ---
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $hw['OEM']   = if ($cs.Manufacturer) { $cs.Manufacturer.Trim() } else { 'Unbekannt' }
        $hw['Model'] = if ($cs.Model)        { $cs.Model.Trim()        } else { 'Unbekannt' }
        Write-Host "  OEM   : $($hw['OEM'])" -ForegroundColor Cyan
        Write-Host "  Modell: $($hw['Model'])" -ForegroundColor Cyan
    }
    catch {
        Write-Log -Nachricht "OEM/Modell-Erkennung fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Warn'
    }

    # --- Formfaktor (Desktop/Laptop) via ChassisType ---
    try {
        $enc = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop
        $chassisTypes = $enc.ChassisTypes

        # Desktop: 3=Desktop, 4=Low Profile Desktop, 5=Pizza Box, 6=Mini Tower,
        #          7=Tower, 15=Space-Saving, 16=Lunch Box, 35=Mini PC
        # Laptop:  8=Portable, 9=Laptop, 10=Notebook, 11=Sub Notebook,
        #          12=Sub-Compact, 13=Sub-Notebook, 14=Space-Saving
        $laptopTypen  = @(8, 9, 10, 11, 12, 13, 14, 30, 31, 32)
        $desktopTypen = @(3, 4, 5, 6, 7, 15, 16, 35, 36)

        $istLaptop = ($chassisTypes | Where-Object { $_ -in $laptopTypen }).Count -gt 0
        $hw['FormFactor'] = if ($istLaptop) { 'Laptop' } else { 'Desktop' }
        Write-Host "  Form  : $($hw['FormFactor']) (ChassisType: $($chassisTypes -join ','))" -ForegroundColor Cyan
    }
    catch {
        Write-Log -Nachricht "FormFactor-Erkennung fehlgeschlagen" -Ebene 'Warn'
    }

    # --- CPU ---
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $hw['CPU'] = $cpu.Name.Trim() -replace '\s{2,}', ' '
        Write-Host "  CPU   : $($hw['CPU'])" -ForegroundColor Cyan
    }
    catch {
        Write-Log -Nachricht "CPU-Erkennung fehlgeschlagen" -Ebene 'Warn'
    }

    # --- GPU (Hersteller + Modell) ---
    try {
        $gpus      = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop
        $primaerGpu = $gpus | Where-Object {
            $_.Name -notmatch 'Microsoft|Basic|Remote|Virtual' -and
            $_.AdapterRAM -gt 0
        } | Sort-Object AdapterRAM -Descending | Select-Object -First 1

        if (-not $primaerGpu) { $primaerGpu = $gpus | Select-Object -First 1 }

        if ($primaerGpu) {
            $gpuName = $primaerGpu.Name.Trim()
            $hw['GPU_Model'] = $gpuName

            $hw['GPU_Vendor'] = switch -Regex ($gpuName) {
                'AMD|Radeon|ATI'     { 'AMD'    }
                'NVIDIA|GeForce|RTX|GTX' { 'NVIDIA' }
                default              { 'Intel'  }
            }
            Write-Host "  GPU   : $gpuName ($($hw['GPU_Vendor']))" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Log -Nachricht "GPU-Erkennung fehlgeschlagen" -Ebene 'Warn'
    }

    # --- RAM ---
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $hw['RAM_GB'] = [Math]::Round($cs.TotalPhysicalMemory / 1GB)
        Write-Host "  RAM   : $($hw['RAM_GB']) GB" -ForegroundColor Cyan
    }
    catch {
        Write-Log -Nachricht "RAM-Erkennung fehlgeschlagen" -Ebene 'Warn'
    }

    # --- Akku ---
    try {
        $batterie = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
        $hw['HasBattery'] = ($null -ne $batterie -and @($batterie).Count -gt 0)
        Write-Host "  Akku  : $(if ($hw['HasBattery']) { 'Ja (Laptop)' } else { 'Nein (Desktop)' })" -ForegroundColor Cyan
    }
    catch {
        $hw['HasBattery'] = $false
    }

    # --- SSD-Erkennung ---
    try {
        $datentraeger = Get-PhysicalDisk -ErrorAction Stop
        $ssdVorhanden = $datentraeger | Where-Object {
            $_.MediaType -in @('SSD', 'NVMe') -or
            $_.BusType   -in @('NVMe', 'SATA') -and $_.MediaType -ne 'HDD'
        }
        $hw['IsSSD'] = ($null -ne $ssdVorhanden -and @($ssdVorhanden).Count -gt 0)
        Write-Host "  SSD   : $(if ($hw['IsSSD']) { 'Ja' } else { 'Nein (HDD)' })" -ForegroundColor Cyan
    }
    catch {
        # Fallback: MediaType via WMI
        try {
            $diskDrives = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop
            $hw['IsSSD'] = ($diskDrives | Where-Object { $_.MediaType -match 'SSD|Solid' }).Count -gt 0
        }
        catch {
            Write-Log -Nachricht "SSD-Erkennung fehlgeschlagen" -Ebene 'Warn'
        }
    }

    # --- OS Build & Edition ---
    try {
        $osReg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $hw['OS_Build']   = [int]$osReg.CurrentBuildNumber
        $hw['OS_Edition'] = $osReg.EditionID
        Write-Host "  OS    : Windows 11 Build $($hw['OS_Build']) ($($hw['OS_Edition']))" -ForegroundColor Cyan
    }
    catch {
        Write-Log -Nachricht "OS-Info-Erkennung fehlgeschlagen" -Ebene 'Warn'
    }

    Write-Host ""
    return $hw
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 5: Ordnerstruktur anlegen
# ─────────────────────────────────────────────────────────────────────────────
function New-OrdnerStruktur {
    Write-Log -Nachricht "Lege Ordnerstruktur an..." -Ebene 'Info'

    $ordner = @(
        (Join-Path $ToolkitRoot 'logs'),
        (Join-Path $ToolkitRoot 'state'),
        (Join-Path $ToolkitRoot 'backup'),
        (Join-Path $ToolkitRoot 'reports')
    )

    foreach ($pfad in $ordner) {
        try {
            if (-not (Test-Path $pfad)) {
                New-Item -ItemType Directory -Path $pfad -Force | Out-Null
                Write-Log -Nachricht "Ordner erstellt: $pfad" -Ebene 'Info'
            }
        }
        catch {
            Write-Log -Nachricht "Ordner konnte nicht erstellt werden: $pfad - $($_.Exception.Message)" -Ebene 'Warn'
        }
    }

    # .gitignore fuer state\-Ordner (falls unter Versionskontrolle)
    $gitignorePfad = Join-Path $ToolkitRoot 'state\.gitignore'
    if (-not (Test-Path $gitignorePfad)) {
        try {
            "*" | Out-File -FilePath $gitignorePfad -Encoding UTF8
        } catch {}
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HAUPTPROGRAMM
# ─────────────────────────────────────────────────────────────────────────────

# Log initialisieren
Initialize-Log -Praefix 'Bootstrap'

Show-ToolkitBanner -Modul '00 - Bootstrap & Systemcheck'

# Schritt 1: Admin-Elevation pruefen
Invoke-SelfElevation

# Ab hier: Wir haben Admin-Rechte
Write-Log -Nachricht "Administrator-Rechte bestaetigt" -Ebene 'Success'

# Schritt 2: ExecutionPolicy
Set-AusfuehrungsRichtlinie

# Schritt 5 (vorgezogen): Ordner anlegen (damit state\ existiert)
New-OrdnerStruktur

# Schritt 3: Voraussetzungen pruefen
$vorausOK = Test-Voraussetzungen

# Schritt 4: Hardware ermitteln
$hw = Get-HardwareErmittlung

# Hardware-Profil speichern
$statePfad    = Join-Path $ToolkitRoot 'state'
$hardwarePfad = Join-Path $statePfad 'hardware.json'

try {
    $hwObjekt = [PSCustomObject]$hw
    $hwObjekt | ConvertTo-Json -Depth 5 | Out-File -FilePath $hardwarePfad -Encoding UTF8 -Force
    Write-Log -Nachricht "Hardware-Profil gespeichert: $hardwarePfad" -Ebene 'Success'
}
catch {
    Write-Log -Nachricht "Hardware-Profil konnte nicht gespeichert werden: $($_.Exception.Message)" -Ebene 'Error'
}

# Schritt 6: Systemwiederherstellungspunkt
if (-not $KeineWiederherstellung) {
    Write-Trennlinie -Titel ' Wiederherstellungspunkt '
    Write-Log -Nachricht "Erstelle Systemwiederherstellungspunkt vor Optimierungen..." -Ebene 'Info'
    $wpErfolg = New-Wiederherstellungspunkt -Beschreibung "Win11-Toolkit Bootstrap $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
    if (-not $wpErfolg) {
        Write-Log -Nachricht "Wiederherstellungspunkt nicht erstellt (evtl. bereits heute erstellt oder VSS deaktiviert)" -Ebene 'Warn'
    }
}

# Schritt 7: bootstrap-ok.json schreiben
$bootstrapOkPfad = Join-Path $statePfad 'bootstrap-ok.json'
try {
    $bootstrapInfo = [PSCustomObject]@{
        Timestamp       = (Get-Date -Format 'o')
        TimestampAnzeige = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
        PS_Version       = $PSVersionTable.PSVersion.ToString()
        OS_Build         = $hw['OS_Build']
        OS_Edition       = $hw['OS_Edition']
        OEM              = $hw['OEM']
        Model            = $hw['Model']
        FormFactor       = $hw['FormFactor']
        CPU              = $hw['CPU']
        GPU_Vendor       = $hw['GPU_Vendor']
        GPU_Model        = $hw['GPU_Model']
        RAM_GB           = $hw['RAM_GB']
        HasBattery       = $hw['HasBattery']
        IsSSD            = $hw['IsSSD']
        Voraussetzungen  = $vorausOK
        Benutzer         = $env:USERNAME
        Rechner          = $env:COMPUTERNAME
    }

    $bootstrapInfo | ConvertTo-Json -Depth 5 | Out-File -FilePath $bootstrapOkPfad -Encoding UTF8 -Force
    Write-Log -Nachricht "Bootstrap-Status gespeichert: $bootstrapOkPfad" -Ebene 'Success'
}
catch {
    Write-Log -Nachricht "Bootstrap-Status konnte nicht gespeichert werden: $($_.Exception.Message)" -Ebene 'Error'
}

# Abschluss
Write-Host ""
Write-Trennlinie -Titel ' Bootstrap abgeschlossen '
Write-Host ""
Write-Host "  Hardware erkannt:" -ForegroundColor White
Write-Host "    OEM/Modell : $($hw['OEM']) $($hw['Model'])" -ForegroundColor Gray
Write-Host "    CPU        : $($hw['CPU'])" -ForegroundColor Gray
Write-Host "    GPU        : $($hw['GPU_Model']) ($($hw['GPU_Vendor']))" -ForegroundColor Gray
Write-Host "    RAM        : $($hw['RAM_GB']) GB" -ForegroundColor Gray
Write-Host "    SSD        : $(if ($hw['IsSSD']) { 'Ja' } else { 'Nein' })" -ForegroundColor Gray
Write-Host "    Akku       : $(if ($hw['HasBattery']) { 'Ja' } else { 'Nein' })" -ForegroundColor Gray
Write-Host ""
Write-Log -Nachricht "Bootstrap erfolgreich abgeschlossen." -Ebene 'Success'
Write-Host ""
Write-Host "  Naechster Schritt:" -ForegroundColor White
Write-Host "    Starte: 10-Updates.ps1" -ForegroundColor Cyan
Write-Host "    oder:   20-Maintenance.ps1" -ForegroundColor Cyan
Write-Host ""

if (-not $Stumm) {
    Write-Host "  Druecke eine Taste zum Beenden..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
