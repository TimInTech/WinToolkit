#Requires -Version 5.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bereinigung, Datenschutz und Optimierung fuer Windows 11.
.DESCRIPTION
    Fuehrt Systemwartung durch: Region/Zeit, Dienste, Bloatware, Bereinigung,
    Energieplaene, Telemetrie, visuelle Effekte, Netzwerk und Autostart.
    Alle Aktionen basieren auf dem Hardware-Profil aus state\hardware.json.
.PARAMETER AllesOhneAbfrage
    Alle Schritte ohne J/N-Bestaetigung ausfuehren.
.PARAMETER NurBericht
    Nur Analyse, keine Aenderungen vornehmen.
.NOTES
    Datei   : 20-Maintenance.ps1
    Version : 1.0.0
    Autor   : TimInTech (https://github.com/TimInTech)
    Abhaengigkeit: 00-Bootstrap.ps1 muss zuerst ausgefuehrt worden sein.
#>

[CmdletBinding()]
param(
    [switch]$AllesOhneAbfrage,
    [switch]$NurBericht
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# Initialisierung
# ─────────────────────────────────────────────────────────────────────────────
$ToolkitRoot = $PSScriptRoot
. "$ToolkitRoot\lib\Common.ps1"
Set-ToolkitRoot -Pfad $ToolkitRoot

Initialize-Log -Praefix 'Maintenance'
Initialize-Language
Show-ToolkitBanner -Modul (Get-LStr 'mod_maintenance')

# Hardware-Profil laden
$hw = Get-HardwareProfile
if (-not $hw) {
    Write-Log -Nachricht "Hardware-Profil nicht verfuegbar. Bitte 00-Bootstrap.ps1 zuerst ausfuehren." -Ebene 'Warn'
}

# Bootstrap-Check
$bootstrapOkPfad = Join-Path $ToolkitRoot 'state\bootstrap-ok.json'
if (-not (Test-Path $bootstrapOkPfad)) {
    Write-Log -Nachricht "Bootstrap wurde noch nicht ausgefuehrt (state\bootstrap-ok.json fehlt)." -Ebene 'Warn'
    if (-not $AllesOhneAbfrage) {
        $weiter = Confirm-Schritt -Frage "Trotzdem fortfahren?"
        if (-not $weiter) { exit 1 }
    }
}

# Hilfsfunktion: Schritt-Header ausgeben
function Show-SchrittHeader {
    param([string]$Titel, [int]$Nummer)
    Write-Host ""
    Write-Trennlinie -Titel " $Nummer - $Titel "
    Write-Host ""
}

# Hilfsfunktion: Schritt abfragen (bypass wenn AllesOhneAbfrage)
function Confirm-SchrittAusfuehren {
    param([string]$Frage)
    if ($AllesOhneAbfrage -or $NurBericht) { return $true }
    return Confirm-Schritt -Frage $Frage -Standard_Ja
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 1: Region / Zeit / NTP
# ─────────────────────────────────────────────────────────────────────────────
function Set-RegionUndZeit {
    Show-SchrittHeader -Titel "Region / Zeitzone / NTP" -Nummer 1

    if (-not (Confirm-SchrittAusfuehren -Frage "Zeitzone auf Europe/Berlin setzen und NTP konfigurieren?")) {
        Write-Log -Nachricht "Schritt 1 (Region/Zeit) uebersprungen." -Ebene 'Info'
        return
    }

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] Zeitzone / NTP wuerde konfiguriert werden." -Ebene 'Info'
        return
    }

    try {
        # Zeitzone setzen
        $aktuelleZone = (Get-TimeZone).Id
        if ($aktuelleZone -ne 'W. Europe Standard Time') {
            Set-TimeZone -Id 'W. Europe Standard Time' -ErrorAction Stop
            Write-Log -Nachricht "Zeitzone gesetzt: W. Europe Standard Time (war: $aktuelleZone)" -Ebene 'Success'
        }
        else {
            Write-Log -Nachricht "Zeitzone bereits korrekt: $aktuelleZone" -Ebene 'Info'
        }

        # Windows-Zeit-Dienst starten
        Set-Service -Name 'W32Time' -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name 'W32Time' -ErrorAction SilentlyContinue

        # NTP-Server konfigurieren
        $ntpServer = 'ptbtime1.ptb.de,0x9 ptbtime2.ptb.de,0x9 time.windows.com,0x9'
        & w32tm.exe /config /manualpeerlist:$ntpServer /syncfromflags:manual /reliable:YES /update 2>&1 | Out-Null
        & w32tm.exe /resync /force 2>&1 | Out-Null
        Write-Log -Nachricht "NTP-Server konfiguriert: PTB + time.windows.com" -Ebene 'Success'

        # Regionale Einstellungen (DE)
        try {
            Set-WinUILanguageOverride -Language 'de-DE' -ErrorAction SilentlyContinue
            Set-WinHomeLocation -GeoId 94 -ErrorAction SilentlyContinue  # Deutschland
            Set-Culture -CultureInfo 'de-DE' -ErrorAction SilentlyContinue
            Write-Log -Nachricht "Regionale Einstellungen: de-DE, Deutschland" -Ebene 'Success'
        }
        catch {
            Write-Log -Nachricht "Regionale Einstellungen konnten nicht vollstaendig gesetzt werden." -Ebene 'Warn'
        }
    }
    catch {
        Write-Log -Nachricht "Fehler bei Region/Zeit: $($_.Exception.Message)" -Ebene 'Error'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 2: Dienste deaktivieren
# ─────────────────────────────────────────────────────────────────────────────
function Disable-UnnoetigeDienste {
    Show-SchrittHeader -Titel "Unnoetige Dienste deaktivieren" -Nummer 2

    if (-not (Confirm-SchrittAusfuehren -Frage "Telemetrie-, Xbox- und andere unnoetige Dienste deaktivieren?")) {
        Write-Log -Nachricht "Schritt 2 (Dienste) uebersprungen." -Ebene 'Info'
        return
    }

    # Dienste: Name => Beschreibung
    $diensteListe = [ordered]@{
        # Telemetrie & Diagnose
        'DiagTrack'               = 'Diagnoseverfolgungsdienst (Telemetrie)'
        'dmwappushservice'        = 'WAP-Push-Dienst (Telemetrie)'
        'diagnosticshub.standardcollector.service' = 'Diagnosehub-Standardsammler'

        # Xbox (nicht benoetigt auf Desktop ohne Spielkonsole)
        'XblAuthManager'          = 'Xbox Live Authentifizierungsmanager'
        'XblGameSave'             = 'Xbox Live Spielsicherung'
        'XboxGipSvc'              = 'Xbox Zubehoerverwaltung'
        'XboxNetApiSvc'           = 'Xbox Live-Netzwerkdienst'

        # Fax
        'Fax'                     = 'Faxdienst'

        # SysMain (Superfetch - auf SSDs unnoetig, kann sogar schaden)
        'SysMain'                 = 'SysMain (Superfetch)'

        # Windows Maps
        'MapsBroker'              = 'Heruntergeladene Karten-Manager'

        # Druckdienste (nur wenn kein Drucker vorhanden - wird geprueft)
        # 'Spooler' -> absichtlich ausgelassen

        # Connected User Experiences (Telemetrie)
        'CDPUserSvc'              = 'Connected User Experiences and Telemetry (User-Instance)'

        # Remote Registry (Sicherheit)
        'RemoteRegistry'          = 'Remote-Registrierungsdienst'

        # Tablet-Dienste
        'TabletInputService'      = 'Stift- und Freihandeingabe-Dienst'
    }

    # SysMain nur auf SSD deaktivieren
    if ($hw -and -not $hw.IsSSD) {
        $diensteListe.Remove('SysMain')
        Write-Log -Nachricht "SysMain wird NICHT deaktiviert (HDD erkannt - Superfetch hilfreich)" -Ebene 'Info'
    }

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] Folgende Dienste wuerden deaktiviert:" -Ebene 'Info'
        foreach ($d in $diensteListe.Keys) {
            $svc = Get-Service -Name $d -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Log -Nachricht "  - $d ($($diensteListe[$d])) - Aktuell: $($svc.Status)" -Ebene 'Info'
            }
        }
        return
    }

    $deaktiviert = 0
    $nichtGefunden = 0

    foreach ($dienstName in $diensteListe.Keys) {
        try {
            $svc = Get-Service -Name $dienstName -ErrorAction SilentlyContinue
            if ($null -eq $svc) {
                $nichtGefunden++
                continue
            }

            # Dienst stoppen und deaktivieren
            if ($svc.Status -eq 'Running') {
                Stop-Service -Name $dienstName -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name $dienstName -StartupType Disabled -ErrorAction Stop
            $deaktiviert++
            Write-Log -Nachricht "Deaktiviert: $dienstName ($($diensteListe[$dienstName]))" -Ebene 'Success'
        }
        catch {
            Write-Log -Nachricht "Dienst $dienstName konnte nicht deaktiviert werden: $($_.Exception.Message)" -Ebene 'Warn'
        }
    }

    Write-Log -Nachricht "Dienste deaktiviert: $deaktiviert ($nichtGefunden nicht gefunden)" -Ebene 'Success'
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 3: Bloatware entfernen
# ─────────────────────────────────────────────────────────────────────────────
function Remove-Bloatware {
    Show-SchrittHeader -Titel "Bloatware entfernen" -Nummer 3

    if (-not (Confirm-SchrittAusfuehren -Frage "Unnoetige vorinstallierte Apps entfernen?")) {
        Write-Log -Nachricht "Schritt 3 (Bloatware) uebersprungen." -Ebene 'Info'
        return
    }

    # Apps die NIEMALS entfernt werden sollen (Sicherheitsliste)
    $schutzListe = @(
        '*MicrosoftEdge*',
        '*OutlookForWindows*',
        '*WindowsStore*',
        '*WindowsCalculator*',
        '*WindowsNotepad*',
        '*Paint*',
        '*ScreenSketch*',
        '*Photos*',
        '*WindowsTerminal*',
        '*WebView2*',
        '*DesktopAppInstaller*',   # WinGet
        '*VCLibs*',                # C++ Libraries
        '*UI.Xaml*'                # XAML Framework
    )

    # Standard Windows-Bloatware
    $bloatwareListe = @(
        # Xbox-Oekosystem
        'Microsoft.XboxApp',
        'Microsoft.XboxGameOverlay',
        'Microsoft.XboxGamingOverlay',
        'Microsoft.XboxIdentityProvider',
        'Microsoft.XboxSpeechToTextOverlay',
        'Microsoft.Xbox.TCUI',
        # Bing-Apps
        'Microsoft.BingWeather',
        'Microsoft.BingNews',
        'Microsoft.BingFinance',
        'Microsoft.BingSports',
        'Microsoft.BingSearch',
        'Microsoft.BingTranslator',
        # Unterhaltung
        'Microsoft.ZuneMusic',
        'Microsoft.ZuneVideo',
        'Microsoft.Solitaire',       # Solitaire Collection
        # Kommunikation
        'Microsoft.SkypeApp',
        'Microsoft.People',
        'Microsoft.Todos',
        'Microsoft.YourPhone',       # Phone Link Consumer
        'MicrosoftTeams',            # Teams Consumer (nicht Teams Work)
        'Microsoft.MicrosoftFamily',
        # Microsoft Store Apps
        'Microsoft.MixedReality.Portal',
        'Microsoft.Cortana',         # Cortana MSIX (549981C3F5F10)
        '549981C3F5F10',
        'Microsoft.WindowsFeedbackHub',
        'Microsoft.WindowsMaps',
        'Clipchamp.Clipchamp',
        'Microsoft.PowerAutomateDesktop',
        # Spiele & Partner-Apps (Wildcard-Pattern)
        '*Netflix*',
        '*Disney*',
        '*Spotify*',
        '*CandyCrush*',
        '*TikTok*',
        '*Amazon*',
        '*Facebook*',
        '*Twitter*',
        '*Instagram*'
    )

    # OEM-spezifische Bloatware basierend auf hardware.json
    $oemBloatware = @()
    if ($hw) {
        switch -Regex ($hw.OEM) {
            'HP|Hewlett' {
                $oemBloatware += @(
                    '*HPSupportAssistant*',
                    '*HP.MyHP*',
                    '*HPWolfSecurity*',
                    '*HPConnectionOptimizer*',
                    '*HPPrivacySettings*'
                )
                Write-Log -Nachricht "OEM-Bloatware: HP-spezifische Apps werden entfernt" -Ebene 'Info'
            }
            'Dell' {
                $oemBloatware += @(
                    '*DellSupportAssist*',
                    '*DellUpdate*',
                    '*DellCommandUpdate*',
                    '*DellEdgeManagement*'
                )
                Write-Log -Nachricht "OEM-Bloatware: Dell-spezifische Apps werden entfernt" -Ebene 'Info'
            }
            'Lenovo' {
                $oemBloatware += @(
                    '*LenovoVantage*',
                    '*LenovoSmartCommunication*',
                    '*LenovoWelcome*',
                    '*E046963F.LenovoCompanion*'
                )
                Write-Log -Nachricht "OEM-Bloatware: Lenovo-spezifische Apps werden entfernt" -Ebene 'Info'
            }
        }
    }

    $alleBloatware = $bloatwareListe + $oemBloatware

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] Folgende Apps wuerden entfernt werden (sofern installiert):" -Ebene 'Info'
        foreach ($app in $alleBloatware) {
            Write-Log -Nachricht "  - $app" -Ebene 'Info'
        }
        return
    }

    $entfernt = 0
    $nichtVorhanden = 0
    $fehler = 0

    foreach ($appPattern in $alleBloatware) {
        # Pruefen ob Pattern in Schutzliste passt
        $geschuetzt = $false
        foreach ($schutz in $schutzListe) {
            if ($appPattern -like $schutz) {
                $geschuetzt = $true
                break
            }
        }
        if ($geschuetzt) {
            Write-Log -Nachricht "Geschuetzt, wird nicht entfernt: $appPattern" -Ebene 'Warn'
            continue
        }

        try {
            Show-Fortschritt -Aktivitaet "Bloatware entfernen" -Status "Prüfe: $appPattern" -Id 3

            # Installierte AppX-Pakete (aktueller Benutzer)
            $pakete = Get-AppxPackage -Name $appPattern -ErrorAction SilentlyContinue
            foreach ($paket in @($pakete)) {
                if ($null -ne $paket) {
                    Remove-AppxPackage -Package $paket.PackageFullName -ErrorAction SilentlyContinue
                    Write-Log -Nachricht "Entfernt (AppX): $($paket.Name)" -Ebene 'Success'
                    $entfernt++
                }
            }

            # Bereitgestellte Pakete (alle Benutzer / neue Installationen)
            $bereitgestellt = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like $appPattern }
            foreach ($bp in @($bereitgestellt)) {
                if ($null -ne $bp) {
                    Remove-AppxProvisionedPackage -Online -PackageName $bp.PackageName -ErrorAction SilentlyContinue
                    Write-Log -Nachricht "Entfernt (Provisioned): $($bp.DisplayName)" -Ebene 'Success'
                }
            }

            if (-not $pakete -and -not $bereitgestellt) { $nichtVorhanden++ }
        }
        catch {
            Write-Log -Nachricht "Fehler beim Entfernen von $appPattern : $($_.Exception.Message)" -Ebene 'Warn'
            $fehler++
        }
    }

    Show-Fortschritt -Aktivitaet "Bloatware entfernen" -Status "Abgeschlossen" -Abschliessen -Id 3
    Write-Log -Nachricht "Bloatware: $entfernt entfernt, $nichtVorhanden nicht vorhanden, $fehler Fehler" -Ebene 'Success'
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 4: Bereinigung
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Bereinigung {
    Show-SchrittHeader -Titel "Datentraeger-Bereinigung" -Nummer 4

    if (-not (Confirm-SchrittAusfuehren -Frage "Temporaere Dateien, Disk-Cleanup und DISM-Bereinigung ausfuehren?")) {
        Write-Log -Nachricht "Schritt 4 (Bereinigung) uebersprungen." -Ebene 'Info'
        return
    }

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] Bereinigung wuerde ausgefuehrt werden." -Ebene 'Info'
        return
    }

    # --- Temp-Ordner bereinigen ---
    $tempPfade = @(
        $env:TEMP,
        $env:TMP,
        'C:\Windows\Temp',
        'C:\Windows\Prefetch'
    )

    $geloescht = 0
    foreach ($pfad in $tempPfade) {
        if (Test-Path $pfad) {
            try {
                $dateien = Get-ChildItem -Path $pfad -Recurse -Force -ErrorAction SilentlyContinue
                foreach ($d in $dateien) {
                    try {
                        Remove-Item -Path $d.FullName -Force -Recurse -ErrorAction SilentlyContinue
                        $geloescht++
                    } catch {}
                }
                Write-Log -Nachricht "Temp bereinigt: $pfad" -Ebene 'Info'
            }
            catch {
                Write-Log -Nachricht "Temp-Bereinigung teilweise fehlgeschlagen: $pfad" -Ebene 'Warn'
            }
        }
    }
    Write-Log -Nachricht "Temp-Dateien entfernt: ~$geloescht Elemente" -Ebene 'Success'

    # --- Windows Disk Cleanup (automatisch) ---
    try {
        Write-Log -Nachricht "Starte Windows Disk Cleanup (sageset 64)..." -Ebene 'Info'

        # Alle Cleanup-Kategorien aktivieren
        $regPfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
        $kategorien = Get-ChildItem -Path $regPfad -ErrorAction SilentlyContinue
        foreach ($kategorie in $kategorien) {
            Set-ItemProperty -Path $kategorie.PSPath -Name 'StateFlags0064' -Value 2 -Type DWord -ErrorAction SilentlyContinue
        }

        # cleanmgr starten
        $proc = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:64' -Wait -PassThru -ErrorAction Stop
        Write-Log -Nachricht "Disk Cleanup abgeschlossen (ExitCode: $($proc.ExitCode))" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "Disk Cleanup fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Warn'
    }

    # --- DISM Component Store bereinigen ---
    try {
        Write-Log -Nachricht "DISM: Component Store bereinigen (kann mehrere Minuten dauern)..." -Ebene 'Info'
        Show-Fortschritt -Aktivitaet "DISM" -Status "Analyse des Component Store..." -Id 4

        $dismLog = Join-Path $ToolkitRoot "logs\dism_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
        $ausgabe = & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
        $ausgabe | Out-File -FilePath $dismLog -Encoding UTF8

        if ($LASTEXITCODE -eq 0) {
            Write-Log -Nachricht "DISM Component Store erfolgreich bereinigt" -Ebene 'Success'
        }
        else {
            Write-Log -Nachricht "DISM beendet mit Code $LASTEXITCODE (Detail: $dismLog)" -Ebene 'Warn'
        }
        Show-Fortschritt -Aktivitaet "DISM" -Status "Abgeschlossen" -Abschliessen -Id 4
    }
    catch {
        Write-Log -Nachricht "DISM-Bereinigung fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
    }

    # --- TRIM fuer alle SSDs ausfuehren ---
    if ($hw -and $hw.IsSSD) {
        try {
            Write-Log -Nachricht "TRIM fuer SSD(s) ausfuehren..." -Ebene 'Info'
            $laufwerke = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
            foreach ($lw in $laufwerke) {
                $result = Optimize-Volume -DriveLetter $lw.DriveLetter -ReTrim -ErrorAction SilentlyContinue
                Write-Log -Nachricht "TRIM ausgefuehrt: Laufwerk $($lw.DriveLetter):\" -Ebene 'Success'
            }
        }
        catch {
            Write-Log -Nachricht "TRIM fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Warn'
        }
    }
    else {
        # HDD Defragmentierung
        try {
            Write-Log -Nachricht "Defragmentierung fuer HDD anstossen..." -Ebene 'Info'
            $laufwerke = Get-Volume -ErrorAction Stop | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }
            foreach ($lw in $laufwerke) {
                Optimize-Volume -DriveLetter $lw.DriveLetter -Defrag -ErrorAction SilentlyContinue
                Write-Log -Nachricht "Defragmentierung: Laufwerk $($lw.DriveLetter):\" -Ebene 'Info'
            }
        }
        catch {
            Write-Log -Nachricht "Defragmentierung fehlgeschlagen" -Ebene 'Warn'
        }
    }

    # --- Papierkorb leeren ---
    try {
        $shell = New-Object -ComObject Shell.Application
        $papierkorb = $shell.Namespace(0xA)
        $papierkorb.Items() | ForEach-Object { $_.InvokeVerb('delete') }
        Write-Log -Nachricht "Papierkorb geleert" -Ebene 'Success'
    }
    catch {
        # Alternativ: Clear-RecycleBin (PS 5+)
        try {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-Log -Nachricht "Papierkorb geleert (Clear-RecycleBin)" -Ebene 'Success'
        }
        catch {
            Write-Log -Nachricht "Papierkorb konnte nicht geleert werden" -Ebene 'Warn'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 5: Energieplan
# ─────────────────────────────────────────────────────────────────────────────
function Set-Energieplan {
    Show-SchrittHeader -Titel "Energieplan optimieren" -Nummer 5

    if (-not (Confirm-SchrittAusfuehren -Frage "Energieplan optimieren (Hohe Leistung / Ausgewogen)?")) {
        Write-Log -Nachricht "Schritt 5 (Energieplan) uebersprungen." -Ebene 'Info'
        return
    }

    if ($NurBericht) {
        $aktuellerPlan = & powercfg.exe /GETACTIVESCHEME 2>&1
        Write-Log -Nachricht "[BERICHT] Aktueller Energieplan: $aktuellerPlan" -Ebene 'Info'
        return
    }

    try {
        $hatAkku = if ($hw) { $hw.HasBattery } else { $false }

        if (-not $hatAkku) {
            # Desktop/Workstation: Maximale Leistung

            # "Ultimative Leistung" aktivieren (falls nicht vorhanden)
            $ultimativGUID = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
            $vorhandene = & powercfg.exe /LIST 2>&1
            if ($vorhandene -notmatch $ultimativGUID) {
                Write-Log -Nachricht "Aktiviere 'Ultimative Leistung' Energieplan..." -Ebene 'Info'
                & powercfg.exe /DUPLICATESCHEME $ultimativGUID 2>&1 | Out-Null
            }

            # Ultimative Leistung aktivieren
            $result = & powercfg.exe /SETACTIVE $ultimativGUID 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Nachricht "Energieplan: Ultimative Leistung aktiviert" -Ebene 'Success'
            }
            else {
                # Fallback: Hohe Leistung
                $hoheLeistungGUID = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
                & powercfg.exe /SETACTIVE $hoheLeistungGUID 2>&1 | Out-Null
                Write-Log -Nachricht "Energieplan: Hohe Leistung aktiviert (Fallback)" -Ebene 'Success'
            }

            # Ruhezustand deaktivieren (Desktop)
            & powercfg.exe /HIBERNATE OFF 2>&1 | Out-Null
            Write-Log -Nachricht "Ruhezustand deaktiviert (Desktop)" -Ebene 'Success'

            # Monitor-Ausschalten: nach 30 Min (AC)
            & powercfg.exe /CHANGE monitor-timeout-ac 30 2>&1 | Out-Null
            # Kein automatisches Standby
            & powercfg.exe /CHANGE standby-timeout-ac 0 2>&1 | Out-Null
            Write-Log -Nachricht "Monitor-Timeout: 30 Min, Standby: Deaktiviert" -Ebene 'Info'
        }
        else {
            # Laptop: Ausgewogener Plan
            $ausgewogenGUID = '381b4222-f694-41f0-9685-ff5bb260df2e'
            & powercfg.exe /SETACTIVE $ausgewogenGUID 2>&1 | Out-Null
            Write-Log -Nachricht "Energieplan: Ausgewogen (Laptop-Modus)" -Ebene 'Success'

            # Ruhezustand aktiviert lassen fuer Laptops
            & powercfg.exe /HIBERNATE ON 2>&1 | Out-Null
            Write-Log -Nachricht "Ruhezustand: Aktiv (Laptop)" -Ebene 'Info'

            # Reasonable Timeouts fuer Akku
            & powercfg.exe /CHANGE monitor-timeout-dc 5  2>&1 | Out-Null
            & powercfg.exe /CHANGE standby-timeout-dc 15 2>&1 | Out-Null
            & powercfg.exe /CHANGE monitor-timeout-ac 15 2>&1 | Out-Null
            & powercfg.exe /CHANGE standby-timeout-ac 30 2>&1 | Out-Null
        }

        # Fast Startup deaktivieren (verhindert echtes Herunterfahren)
        $regPfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
        Backup-Registry -RegistryPfad $regPfad -Beschreibung 'Energieplan_SessionManager'
        Set-ItemProperty -Path $regPfad -Name 'HiberbootEnabled' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log -Nachricht "Fast Startup deaktiviert" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "Fehler beim Energieplan: $($_.Exception.Message)" -Ebene 'Error'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 6: Telemetrie / Werbung / Datenschutz
# ─────────────────────────────────────────────────────────────────────────────
function Set-Datenschutz {
    Show-SchrittHeader -Titel "Telemetrie & Datenschutz" -Nummer 6

    if (-not (Confirm-SchrittAusfuehren -Frage "Telemetrie, Werbung und Datenschutz-Einstellungen optimieren?")) {
        Write-Log -Nachricht "Schritt 6 (Datenschutz) uebersprungen." -Ebene 'Info'
        return
    }

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] Telemetrie/Datenschutz-Einstellungen wuerden optimiert." -Ebene 'Info'
        return
    }

    # Registry-Backup vor Aenderungen
    Backup-Registry -RegistryPfad 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' -Beschreibung 'Telemetrie_Policies'
    Backup-Registry -RegistryPfad 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' -Beschreibung 'Datenschutz_User'

    $regAenderungen = @(
        # Telemetrie auf Minimum (0=Sicherheit, 1=Basis - Home benoetigt min. 1)
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'MaxTelemetryAllowed'; Wert = 0; Typ = 'DWord' },
        # Werbungs-ID deaktivieren
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Name = 'DisabledByGroupPolicy'; Wert = 1; Typ = 'DWord' },
        # Cortana deaktivieren
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'AllowCortana'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Name = 'DisableWebSearch'; Wert = 1; Typ = 'DWord' },
        # Suche (Web-Ergebnisse in Startmenue)
        @{ Pfad = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Wert = 1; Typ = 'DWord' },
        # Diagnosedaten
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'DoNotShowFeedbackNotifications'; Wert = 1; Typ = 'DWord' },
        # Windows Error Reporting deaktivieren
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'; Name = 'Disabled'; Wert = 1; Typ = 'DWord' },
        # Activity History
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'EnableActivityFeed'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Name = 'PublishUserActivities'; Wert = 0; Typ = 'DWord' },
        # Zugriff auf Kamera/Mikrofon (Policy)
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; Name = 'LetAppsAccessLocation'; Wert = 2; Typ = 'DWord' },
        # Sprachübermittlung
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; Name = 'HasAccepted'; Wert = 0; Typ = 'DWord' },
        # Handwriting Telemetrie
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Wert = 1; Typ = 'DWord' },
        @{ Pfad = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Wert = 1; Typ = 'DWord' },
        # Werbung im Startmenue
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SystemPaneSuggestionsEnabled'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338388Enabled'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-338389Enabled'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353694Enabled'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SubscribedContent-353696Enabled'; Wert = 0; Typ = 'DWord' },
        # Tipps & Vorschlaege
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SoftLandingEnabled'; Wert = 0; Typ = 'DWord' },
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'RotatingLockScreenEnabled'; Wert = 0; Typ = 'DWord' },
        # OneDrive AutoStart (nicht deinstallieren, nur AutoStart entfernen)
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Name = 'OneDrive'; Wert = ([byte[]](0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)); Typ = 'Binary' }
    )

    $gesetzt = 0
    foreach ($aenderung in $regAenderungen) {
        try {
            if (-not (Test-Path $aenderung.Pfad)) {
                New-Item -Path $aenderung.Pfad -Force | Out-Null
            }
            Set-ItemProperty -Path $aenderung.Pfad -Name $aenderung.Name -Value $aenderung.Wert -Type $aenderung.Typ -Force -ErrorAction Stop
            $gesetzt++
        }
        catch {
            Write-Log -Nachricht "Registry konnte nicht gesetzt werden: $($aenderung.Pfad)\$($aenderung.Name) - $($_.Exception.Message)" -Ebene 'Warn'
        }
    }

    Write-Log -Nachricht "Datenschutz: $gesetzt Registry-Eintraege gesetzt" -Ebene 'Success'

    # Diagnosedienst auf Basis setzen (erfordert HKLM)
    try {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack' `
            -Name 'Start' -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log -Nachricht "DiagTrack-Dienst deaktiviert" -Ebene 'Success'
    }
    catch {}
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 7: Visuelle Effekte optimieren
# ─────────────────────────────────────────────────────────────────────────────
function Set-VisuelleEffekte {
    Show-SchrittHeader -Titel "Visuelle Effekte optimieren" -Nummer 7

    if (-not (Confirm-SchrittAusfuehren -Frage "Visuelle Effekte fuer bessere Performance optimieren?")) {
        Write-Log -Nachricht "Schritt 7 (Visuelle Effekte) uebersprungen." -Ebene 'Info'
        return
    }

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] Visuelle Effekte wuerden optimiert." -Ebene 'Info'
        return
    }

    try {
        # Performance-Einstellungen (UserPreferencesMask)
        $regPfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        Backup-Registry -RegistryPfad 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Beschreibung 'VisualEffects'

        if (-not (Test-Path $regPfad)) {
            New-Item -Path $regPfad -Force | Out-Null
        }
        # 0 = Optimale Leistung, 1 = Optimales Aussehen, 2 = Benutzerdefiniert, 3 = Windows entscheidet
        Set-ItemProperty -Path $regPfad -Name 'VisualFXSetting' -Value 2 -Type DWord -Force

        $sysPfad = 'HKCU:\Control Panel\Desktop'
        $winMetPfad = 'HKCU:\SOFTWARE\Microsoft\Windows\DWM'

        # Nur behalten: Bildlauf-Leisten, Schriften glaetten, Miniaturansichten
        $effekte = @{
            # Desktop
            'HKCU:\Control Panel\Desktop'                                           = @{
                'UserPreferencesMask' = ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00))
                'FontSmoothing'       = '2'
                'FontSmoothingType'   = 2
            }
            # Taskleiste Animationen aus
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'     = @{
                'TaskbarAnimations'     = 0
                'ListviewAlphaSelect'   = 0
                'ListviewShadow'        = 0
                'TaskbarMn'             = 0
            }
            # Fenster-Animationen aus
            'HKCU:\Control Panel\Desktop\WindowMetrics'                             = @{
                'MinAnimate' = '0'
            }
        }

        foreach ($pfad in $effekte.Keys) {
            if (-not (Test-Path $pfad)) {
                New-Item -Path $pfad -Force | Out-Null
            }
            foreach ($name in $effekte[$pfad].Keys) {
                $wert = $effekte[$pfad][$name]
                $typ  = if ($wert -is [byte[]]) { 'Binary' }
                        elseif ($wert -is [int]) { 'DWord'  }
                        else                     { 'String' }
                Set-ItemProperty -Path $pfad -Name $name -Value $wert -Type $typ -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Log -Nachricht "Visuelle Effekte: Fuer Performance optimiert" -Ebene 'Success'

        # Transparenz ausschalten (kostet GPU)
        Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
            -Name 'EnableTransparency' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log -Nachricht "Transparenz-Effekte deaktiviert" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "Fehler bei visuellen Effekten: $($_.Exception.Message)" -Ebene 'Error'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 8: Netzwerk-Optimierungen
# ─────────────────────────────────────────────────────────────────────────────
function Set-NetzwerkOptimierungen {
    Show-SchrittHeader -Titel "Netzwerk-Optimierungen" -Nummer 8

    if (-not (Confirm-SchrittAusfuehren -Frage "Netzwerk-Einstellungen fuer beste Performance optimieren?")) {
        Write-Log -Nachricht "Schritt 8 (Netzwerk) uebersprungen." -Ebene 'Info'
        return
    }

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] Netzwerk-Optimierungen wuerden angewendet." -Ebene 'Info'
        return
    }

    try {
        Backup-Registry -RegistryPfad 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Beschreibung 'Netzwerk_TCPIP'

        # TCP/IP Optimierungen
        $tcpParamPfad = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
        $tcpEinstellungen = @{
            'TcpAckFrequency'           = 1      # Schnelleres ACK
            'TCPNoDelay'                = 1      # Nagle-Algorithmus deaktivieren
            'TcpDelAckTicks'            = 0      # Kein ACK-Delay
            'DefaultTTL'                = 64
        }

        foreach ($name in $tcpEinstellungen.Keys) {
            Set-ItemProperty -Path $tcpParamPfad -Name $name `
                -Value $tcpEinstellungen[$name] -Type DWord -Force -ErrorAction SilentlyContinue
        }
        Write-Log -Nachricht "TCP/IP-Parameter optimiert" -Ebene 'Success'

        # Netzwerk-Adapter optimieren (Energiesparen deaktivieren)
        $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Up' }
        foreach ($adp in @($adapter)) {
            try {
                # Energieverwaltung: Adapter nicht ausschalten
                $adpConfig = $adp | Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue
                if ($adpConfig) {
                    $adpConfig.AllowComputerToTurnOffDevice = 'Disabled'
                    $adpConfig | Set-NetAdapterPowerManagement -ErrorAction SilentlyContinue
                }

                # Interrupt Moderation (fuer niedrige Latenz) anpassen
                Set-NetAdapterAdvancedProperty -Name $adp.Name `
                    -DisplayName 'Interrupt Moderation' -DisplayValue 'Disabled' `
                    -ErrorAction SilentlyContinue

                Write-Log -Nachricht "Adapter optimiert: $($adp.Name)" -Ebene 'Info'
            }
            catch {}
        }

        # Windows Auto-Tuning
        & netsh.exe int tcp set global autotuninglevel=normal 2>&1 | Out-Null
        & netsh.exe int tcp set global chimney=disabled 2>&1 | Out-Null
        & netsh.exe int tcp set global rss=enabled 2>&1 | Out-Null

        Write-Log -Nachricht "TCP Auto-Tuning: Normal, RSS: Aktiviert" -Ebene 'Success'

        # Netzwerk-Entdeckung (wenn nicht benoetigt)
        $regNetzwerk = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator'
        if (-not (Test-Path $regNetzwerk)) { New-Item -Path $regNetzwerk -Force | Out-Null }
        Set-ItemProperty -Path $regNetzwerk -Name 'NoActiveProbe' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        Write-Log -Nachricht "Netzwerk-Optimierungen angewendet" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "Fehler bei Netzwerk-Optimierungen: $($_.Exception.Message)" -Ebene 'Error'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 9: GPU-spezifische Optimierungen
# ─────────────────────────────────────────────────────────────────────────────
function Set-GPUOptimierungen {
    Show-SchrittHeader -Titel "GPU-Optimierungen" -Nummer 9

    $gpuVendor = if ($hw) { $hw.GPU_Vendor } else { 'Intel' }

    if (-not (Confirm-SchrittAusfuehren -Frage "GPU-Optimierungen anwenden ($gpuVendor erkannt)?")) {
        Write-Log -Nachricht "Schritt 9 (GPU) uebersprungen." -Ebene 'Info'
        return
    }

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] GPU-Optimierungen fuer $gpuVendor wuerden angewendet." -Ebene 'Info'
        return
    }

    # Hardware-beschleunigte GPU-Planung (HAGS) aktivieren fuer alle Hersteller
    try {
        Backup-Registry -RegistryPfad 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Beschreibung 'GPU_GraphicsDrivers'
        $graphPfad = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        Set-ItemProperty -Path $graphPfad -Name 'HwSchMode' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log -Nachricht "Hardware-GPU-Planung (HAGS): Aktiviert" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "HAGS konnte nicht aktiviert werden" -Ebene 'Warn'
    }

    switch ($gpuVendor) {
        'AMD' {
            Write-Log -Nachricht "AMD GPU erkannt: Radeon-spezifische Optimierungen..." -Ebene 'Info'
            try {
                Backup-Registry -RegistryPfad 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -Beschreibung 'AMD_GPU_Treiber'

                # AMD-Treiber-Registry optimieren
                $amdTreiberPfade = Get-ChildItem `
                    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' `
                    -ErrorAction SilentlyContinue |
                    Where-Object {
                        (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DriverDesc -match 'AMD|Radeon|ATI'
                    }

                foreach ($treiber in @($amdTreiberPfade)) {
                    if ($null -eq $treiber) { continue }
                    try {
                        # Tessellation auf AMD-Standard (verhindert Engpass)
                        Set-ItemProperty -Path $treiber.PSPath -Name 'KMD_EnableSWTesselation' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        # Anti-Aliasing: Anwendung entscheidet
                        Set-ItemProperty -Path $treiber.PSPath -Name 'DAL_DisableCCC' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                        # TDR (Timeout Detection Recovery) Timeout erhoehen
                        Set-ItemProperty -Path $treiber.PSPath -Name 'TdrDelay' -Value 60 -Type DWord -Force -ErrorAction SilentlyContinue
                        Write-Log -Nachricht "AMD-Treiber optimiert: $($treiber.PSChildName)" -Ebene 'Success'
                    }
                    catch {}
                }

                # Hardware Accelerated GPU Scheduling fuer AMD
                Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
                    -Name 'HwSchMode' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

                Write-Log -Nachricht "AMD GPU: Optimierungen angewendet" -Ebene 'Success'
            }
            catch {
                Write-Log -Nachricht "AMD-Optimierungen teilweise fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Warn'
            }
        }

        'NVIDIA' {
            Write-Log -Nachricht "NVIDIA GPU erkannt: NVIDIA-spezifische Optimierungen..." -Ebene 'Info'
            try {
                Backup-Registry -RegistryPfad 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -Beschreibung 'NVIDIA_GPU_Treiber'

                $nvidiaPfade = Get-ChildItem `
                    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' `
                    -ErrorAction SilentlyContinue |
                    Where-Object {
                        (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DriverDesc -match 'NVIDIA|GeForce|Quadro'
                    }

                foreach ($treiber in @($nvidiaPfade)) {
                    if ($null -eq $treiber) { continue }
                    try {
                        # Low Latency Modus aktivieren
                        Set-ItemProperty -Path $treiber.PSPath -Name 'PerfLevelSrc' -Value 0x2222 -Type DWord -Force -ErrorAction SilentlyContinue
                        # Power Management: Maximale Leistung
                        Set-ItemProperty -Path $treiber.PSPath -Name 'PowerMizerEnable' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $treiber.PSPath -Name 'PowerMizerLevel' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $treiber.PSPath -Name 'PowerMizerLevelAC' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                        Write-Log -Nachricht "NVIDIA-Treiber optimiert: $($treiber.PSChildName)" -Ebene 'Success'
                    }
                    catch {}
                }

                # NVIDIA Telemetrie deaktivieren
                $nvSvc = @('NvTelemetryContainer', 'NvNetworkService')
                foreach ($svc in $nvSvc) {
                    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
                    if ($s) {
                        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                        Write-Log -Nachricht "NVIDIA-Dienst deaktiviert: $svc" -Ebene 'Info'
                    }
                }

                Write-Log -Nachricht "NVIDIA GPU: Optimierungen angewendet" -Ebene 'Success'
            }
            catch {
                Write-Log -Nachricht "NVIDIA-Optimierungen teilweise fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Warn'
            }
        }

        'Intel' {
            Write-Log -Nachricht "Intel GPU/iGPU erkannt: Intel-spezifische Optimierungen..." -Ebene 'Info'
            try {
                # Intel Power-Management optimieren
                $intelPfade = Get-ChildItem `
                    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' `
                    -ErrorAction SilentlyContinue |
                    Where-Object {
                        (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DriverDesc -match 'Intel'
                    }

                foreach ($treiber in @($intelPfade)) {
                    if ($null -eq $treiber) { continue }
                    # Gaming-Modus
                    Set-ItemProperty -Path $treiber.PSPath -Name 'KMD_EnableComputePreemption' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                }

                Write-Log -Nachricht "Intel GPU: Optimierungen angewendet" -Ebene 'Success'
            }
            catch {
                Write-Log -Nachricht "Intel-Optimierungen fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Warn'
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 10: Autostart-Bereinigung (interaktiv)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-AutostartBereinigung {
    Show-SchrittHeader -Titel "Autostart-Bereinigung" -Nummer 10

    if ($NurBericht) {
        Write-Log -Nachricht "[BERICHT] Autostart-Eintraege werden nur aufgelistet." -Ebene 'Info'
    }
    elseif (-not (Confirm-SchrittAusfuehren -Frage "Autostart-Programme interaktiv bereinigen?")) {
        Write-Log -Nachricht "Schritt 10 (Autostart) uebersprungen." -Ebene 'Info'
        return
    }

    # Autostart-Eintraege sammeln
    $autostartEintraege = @()

    # Registry-Quellen
    $regQuellen = @(
        @{ Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Bereich = 'HKLM (Alle)' },
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Bereich = 'HKCU (User)' },
        @{ Pfad = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Bereich = 'HKLM RunOnce' },
        @{ Pfad = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Bereich = 'HKCU RunOnce' }
    )

    foreach ($quelle in $regQuellen) {
        try {
            if (Test-Path $quelle.Pfad) {
                $eintraege = Get-ItemProperty -Path $quelle.Pfad -ErrorAction SilentlyContinue
                if ($eintraege) {
                    $eintraege.PSObject.Properties |
                        Where-Object { $_.Name -notmatch '^PS' } |
                        ForEach-Object {
                            $autostartEintraege += [PSCustomObject]@{
                                Index    = $autostartEintraege.Count + 1
                                Name     = $_.Name
                                Befehl   = $_.Value
                                Bereich  = $quelle.Bereich
                                RegPfad  = $quelle.Pfad
                                Quelle   = 'Registry'
                            }
                        }
                }
            }
        }
        catch {}
    }

    # Startmenue-Ordner
    $startupOrdner = @(
        [System.Environment]::GetFolderPath('CommonStartup'),
        [System.Environment]::GetFolderPath('Startup')
    )
    foreach ($ordner in $startupOrdner) {
        if (Test-Path $ordner) {
            Get-ChildItem -Path $ordner -Filter '*.lnk' -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $autostartEintraege += [PSCustomObject]@{
                        Index   = $autostartEintraege.Count + 1
                        Name    = $_.BaseName
                        Befehl  = $_.FullName
                        Bereich = $ordner
                        RegPfad = $ordner
                        Quelle  = 'Startmenue'
                    }
                }
        }
    }

    if ($autostartEintraege.Count -eq 0) {
        Write-Log -Nachricht "Keine Autostart-Eintraege gefunden." -Ebene 'Info'
        return
    }

    # Anzeige der Eintraege
    Write-Host ""
    Write-Host "  Gefundene Autostart-Eintraege:" -ForegroundColor White
    Write-Host ""
    Write-Host ("  {0,-5} {1,-35} {2,-20} {3}" -f "Nr.", "Name", "Bereich", "Befehl (gekuerzt)") -ForegroundColor Cyan
    Write-Trennlinie -Zeichen '-' -Breite 110
    foreach ($e in $autostartEintraege) {
        $befehlGekuerzt = if ($e.Befehl.Length -gt 50) { $e.Befehl.Substring(0, 50) + '...' } else { $e.Befehl }
        Write-Host ("  {0,-5} {1,-35} {2,-20} {3}" -f $e.Index, $e.Name, $e.Bereich, $befehlGekuerzt)
    }
    Write-Host ""

    if ($NurBericht -or $AllesOhneAbfrage) {
        Write-Log -Nachricht "$($autostartEintraege.Count) Autostart-Eintraege gefunden." -Ebene 'Info'
        return
    }

    # Interaktive Auswahl
    Write-Host "  Welche Nummern sollen deaktiviert werden?" -ForegroundColor Yellow
    Write-Host "  (Komma-getrennt, z.B.: 2,4,7 | ENTER = keine Aenderung)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Eingabe: " -ForegroundColor Yellow -NoNewline

    try {
        $eingabe = Read-Host
    }
    catch {
        Write-Log -Nachricht "Keine interaktive Eingabe moeglich." -Ebene 'Warn'
        return
    }

    if ([string]::IsNullOrWhiteSpace($eingabe)) {
        Write-Log -Nachricht "Keine Autostart-Eintraege geaendert." -Ebene 'Info'
        return
    }

    # Ausgewaehlte Nummern parsen
    $ausgewaehlteNummern = $eingabe.Split(',') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ } |
        Where-Object { $_ -ge 1 -and $_ -le $autostartEintraege.Count }

    foreach ($nr in $ausgewaehlteNummern) {
        $eintrag = $autostartEintraege | Where-Object { $_.Index -eq $nr }
        if (-not $eintrag) { continue }

        try {
            if ($eintrag.Quelle -eq 'Registry') {
                # Registry-Eintrag entfernen (Backup zuerst)
                Backup-Registry -RegistryPfad $eintrag.RegPfad -Beschreibung "Autostart_$($eintrag.Name)"
                Remove-ItemProperty -Path $eintrag.RegPfad -Name $eintrag.Name -ErrorAction Stop
                Write-Log -Nachricht "Autostart deaktiviert: $($eintrag.Name) ($($eintrag.Bereich))" -Ebene 'Success'
            }
            elseif ($eintrag.Quelle -eq 'Startmenue') {
                # Verknuepfung deaktivieren (umbenennen mit .disabled)
                Rename-Item -Path $eintrag.Befehl -NewName "$($eintrag.Name).lnk.disabled" -Force -ErrorAction Stop
                Write-Log -Nachricht "Autostart-Verknuepfung deaktiviert: $($eintrag.Name)" -Ebene 'Success'
            }
        }
        catch {
            Write-Log -Nachricht "Konnte Autostart nicht deaktivieren: $($eintrag.Name) - $($_.Exception.Message)" -Ebene 'Error'
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ABSCHLUSSBERICHT HTML
# ─────────────────────────────────────────────────────────────────────────────
function New-WartungsBericht {
    $datumString = Get-Date -Format 'yyyy-MM-dd_HH-mm'
    $berichtPfad = Join-Path $ToolkitRoot "reports\maintenance-${datumString}.html"

    try {
        if (-not (Test-Path (Split-Path $berichtPfad))) {
            New-Item -ItemType Directory -Path (Split-Path $berichtPfad) -Force | Out-Null
        }

        $hwInfo = if ($hw) {
            "<tr><td>OEM</td><td>$($hw.OEM)</td></tr>
             <tr><td>Modell</td><td>$($hw.Model)</td></tr>
             <tr><td>CPU</td><td>$($hw.CPU)</td></tr>
             <tr><td>GPU</td><td>$($hw.GPU_Model) ($($hw.GPU_Vendor))</td></tr>
             <tr><td>RAM</td><td>$($hw.RAM_GB) GB</td></tr>
             <tr><td>SSD</td><td>$(if ($hw.IsSSD) { 'Ja' } else { 'Nein' })</td></tr>"
        }
        else { "<tr><td colspan='2'>Hardware-Profil nicht verfuegbar</td></tr>" }

        $logEintraege = if ($Script:LogPfad -and (Test-Path $Script:LogPfad)) {
            (Get-Content $Script:LogPfad -Encoding UTF8 -ErrorAction SilentlyContinue) -join "<br>"
        }
        else { "Kein Log vorhanden." }

        $html = @"
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wartungsbericht - $(Get-Date -Format 'dd.MM.yyyy HH:mm')</title>
    <style>
        body { font-family: Segoe UI, sans-serif; background: #1a1a2e; color: #e0e0e0; margin: 0; padding: 20px; }
        h1   { color: #00d4ff; border-bottom: 2px solid #00d4ff; padding-bottom: 10px; }
        h2   { color: #7fdbff; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th    { background: #16213e; color: #00d4ff; padding: 10px; text-align: left; }
        td    { padding: 8px 10px; border-bottom: 1px solid #2a2a4a; }
        tr:hover { background: #16213e; }
        .ok   { color: #4caf50; }
        .warn { color: #ff9800; }
        .err  { color: #f44336; }
        .log  { background: #0d0d1a; padding: 15px; border-radius: 5px; font-family: Consolas, monospace;
                font-size: 12px; line-height: 1.6; overflow-x: auto; max-height: 400px; overflow-y: auto; }
        .badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 11px; }
        .badge-ok { background: #1b5e20; color: #a5d6a7; }
        .badge-warn { background: #e65100; color: #ffe0b2; }
    </style>
</head>
<body>
    <h1>🛠 Windows 11 Optimierungs-Toolkit - Wartungsbericht</h1>
    <p><strong>Datum:</strong> $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss') &nbsp;
       <strong>Rechner:</strong> $env:COMPUTERNAME &nbsp;
       <strong>Benutzer:</strong> $env:USERNAME</p>

    <h2>Hardware-Profil</h2>
    <table>
        <tr><th>Eigenschaft</th><th>Wert</th></tr>
        $hwInfo
    </table>

    <h2>Ausgefuehrte Schritte</h2>
    <table>
        <tr><th>Schritt</th><th>Beschreibung</th><th>Status</th></tr>
        <tr><td>01</td><td>Region / Zeitzone / NTP</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>02</td><td>Dienste deaktivieren</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>03</td><td>Bloatware entfernen</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>04</td><td>Datentraeger-Bereinigung</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>05</td><td>Energieplan</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>06</td><td>Telemetrie &amp; Datenschutz</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>07</td><td>Visuelle Effekte</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>08</td><td>Netzwerk-Optimierungen</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>09</td><td>GPU-Optimierungen ($($hw.GPU_Vendor))</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
        <tr><td>10</td><td>Autostart-Bereinigung</td><td><span class='badge badge-ok'>Ausgefuehrt</span></td></tr>
    </table>

    <h2>Protokoll</h2>
    <div class="log">$logEintraege</div>
</body>
</html>
"@

        $html | Out-File -FilePath $berichtPfad -Encoding UTF8 -Force
        Write-Log -Nachricht "Wartungsbericht erstellt: $berichtPfad" -Ebene 'Success'
        return $berichtPfad
    }
    catch {
        Write-Log -Nachricht "Bericht konnte nicht erstellt werden: $($_.Exception.Message)" -Ebene 'Error'
        return $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HAUPTPROGRAMM
# ─────────────────────────────────────────────────────────────────────────────

if ($NurBericht) {
    Write-Log -Nachricht "Modus: NUR-BERICHT (keine Aenderungen)" -Ebene 'Warn'
}

# Wiederherstellungspunkt vor Aenderungen
if (-not $NurBericht) {
    $wp = New-Wiederherstellungspunkt -Beschreibung "Win11-Toolkit Maintenance $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
}

# Alle Schritte ausfuehren
Set-RegionUndZeit
Disable-UnnoetigeDienste
Remove-Bloatware
Invoke-Bereinigung
Set-Energieplan
Set-Datenschutz
Set-VisuelleEffekte
Set-NetzwerkOptimierungen
Set-GPUOptimierungen
Invoke-AutostartBereinigung

# Abschlussbericht erstellen
$berichtPfad = New-WartungsBericht

# state\maintenance-done.json schreiben
$statePfad = Join-Path $ToolkitRoot 'state'
$maintenanceDone = Join-Path $statePfad 'maintenance-done.json'
try {
    [PSCustomObject]@{
        Timestamp    = (Get-Date -Format 'o')
        Berichtspfad = $berichtPfad
        Rechner      = $env:COMPUTERNAME
        Benutzer     = $env:USERNAME
        NurBericht   = $NurBericht.IsPresent
    } | ConvertTo-Json | Out-File -FilePath $maintenanceDone -Encoding UTF8 -Force
}
catch {}

# Abschluss
Write-Host ""
Write-Trennlinie -Titel (Get-LStr 'maint_done_title')
Write-Host ""
Write-Log -Nachricht (Get-LStr 'maint_done_msg') -Ebene 'Success'

if ($berichtPfad -and (Test-Path $berichtPfad)) {
    Write-Host "$(Get-LStr 'maint_report') $berichtPfad" -ForegroundColor Cyan
    Write-Host (Get-LStr 'maint_report_hint') -ForegroundColor Gray
}

Write-Host ""
Write-Host (Get-LStr 'maint_reboot_warn') -ForegroundColor Yellow
Write-Host ""

if (-not $AllesOhneAbfrage) {
    $neustart = Confirm-Schritt -Frage (Get-LStr 'maint_reboot_q')
    if ($neustart) {
        Write-Log -Nachricht "Neustart wird ausgefuehrt..." -Ebene 'Info'
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }
}
