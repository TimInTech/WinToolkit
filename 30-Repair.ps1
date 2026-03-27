#Requires -Version 5.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Reparatur- und Diagnose-Menue fuer Windows 11.
.DESCRIPTION
    Interaktives Text-Menue fuer Systemdiagnose, haeufige Reparaturen,
    Backup-Erstellung, Wiederherstellungspunkte und Werksreset.
.NOTES
    Datei   : 30-Repair.ps1
    Version : 1.0.0
    Benoetigt Administrator-Rechte.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# Initialisierung
# ─────────────────────────────────────────────────────────────────────────────
$ToolkitRoot = $PSScriptRoot
. "$ToolkitRoot\lib\Common.ps1"
Set-ToolkitRoot -Pfad $ToolkitRoot

Initialize-Log -Praefix 'Repair'
$hw = Get-HardwareProfile -Stumm

# ─────────────────────────────────────────────────────────────────────────────
# Haupt-Menue anzeigen
# ─────────────────────────────────────────────────────────────────────────────
function Show-HauptMenue {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║    🔧 Windows 11 - Reparatur & Diagnose             ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║                                                      ║" -ForegroundColor Cyan
    Write-Host "  ║  [1]  Systemzustand prüfen (Diagnose)               ║" -ForegroundColor White
    Write-Host "  ║  [2]  Häufige Fehler beheben                        ║" -ForegroundColor White
    Write-Host "  ║  [3]  Backup erstellen                              ║" -ForegroundColor White
    Write-Host "  ║  [4]  Wiederherstellungspunkt laden                 ║" -ForegroundColor White
    Write-Host "  ║  [5]  Neustart & Werksreset                         ║" -ForegroundColor White
    Write-Host "  ║                                                      ║" -ForegroundColor Cyan
    Write-Host "  ║  [Q]  Beenden                                        ║" -ForegroundColor Gray
    Write-Host "  ║                                                      ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    if ($hw) {
        Write-Host "  PC: $($hw.OEM) $($hw.Model) | RAM: $($hw.RAM_GB) GB | GPU: $($hw.GPU_Vendor)" -ForegroundColor DarkGray
    }
    Write-Host "  Log: $Script:LogPfad" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Auswahl: " -ForegroundColor Yellow -NoNewline
}

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 1: Systemzustand pruefen (Diagnose mit Ampel-System)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Diagnose {
    Clear-Host
    Write-Host ""
    Write-Trennlinie -Titel ' Systemdiagnose '
    Write-Host ""
    Write-Log -Nachricht "Starte Systemdiagnose..." -Ebene 'Info'

    $ergebnisse = [ordered]@{}

    # --- SFC /scannow ---
    Write-Host "  [1/6] Systemdatei-Pruefung (sfc /scannow)..." -ForegroundColor Cyan
    Write-Host "        (Kann 5-15 Minuten dauern)" -ForegroundColor Gray
    try {
        $sfcLog = Join-Path $ToolkitRoot "logs\sfc_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
        $sfcAusgabe = & sfc.exe /scannow 2>&1 | ForEach-Object { $_ }
        $sfcAusgabe | Out-File -FilePath $sfcLog -Encoding UTF8

        $sfcOK = ($sfcAusgabe | Where-Object { $_ -match 'keine Integritaetsverletzung|no integrity violations|erfolgreich repariert' })
        $sfcFehler = ($sfcAusgabe | Where-Object { $_ -match 'Fehler|error|corrupted|konnte nicht reparieren' })

        if ($sfcFehler) {
            $ergebnisse['SFC'] = @{ Status = 'Rot'; Text = "Fehler gefunden (siehe $sfcLog)" }
            Write-Host "  [ROT]  SFC: Fehler gefunden" -ForegroundColor Red
        }
        elseif ($sfcOK) {
            $ergebnisse['SFC'] = @{ Status = 'Gruen'; Text = "Keine Fehler" }
            Write-Host "  [OK]   SFC: Systemdateien intakt" -ForegroundColor Green
        }
        else {
            $ergebnisse['SFC'] = @{ Status = 'Gelb'; Text = "Ergebnis unklar (Log pruefen)" }
            Write-Host "  [WARN] SFC: Ergebnis unklar (Log: $sfcLog)" -ForegroundColor Yellow
        }
    }
    catch {
        $ergebnisse['SFC'] = @{ Status = 'Gelb'; Text = "SFC konnte nicht ausgefuehrt werden" }
        Write-Host "  [WARN] SFC fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # --- DISM /CheckHealth ---
    Write-Host "  [2/6] DISM Gesundheitscheck..." -ForegroundColor Cyan
    try {
        $dismAusgabe = & dism.exe /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
        if ($dismAusgabe -match 'RestoreHealth|repariert|repairable|corrupted') {
            $ergebnisse['DISM'] = @{ Status = 'Rot'; Text = "Component Store beschaedigt" }
            Write-Host "  [ROT]  DISM: Component Store beschaedigt" -ForegroundColor Red
        }
        elseif ($dismAusgabe -match 'no component store corruption|keine Beschaedigung') {
            $ergebnisse['DISM'] = @{ Status = 'Gruen'; Text = "Keine Beschaedigung" }
            Write-Host "  [OK]   DISM: Component Store OK" -ForegroundColor Green
        }
        else {
            $ergebnisse['DISM'] = @{ Status = 'Gelb'; Text = "Status unklar" }
            Write-Host "  [WARN] DISM: Status unklar" -ForegroundColor Yellow
        }
    }
    catch {
        $ergebnisse['DISM'] = @{ Status = 'Gelb'; Text = "DISM nicht verfuegbar" }
        Write-Host "  [WARN] DISM fehlgeschlagen" -ForegroundColor Yellow
    }

    # --- Event Log: Letzte 24h Critical + Error ---
    Write-Host "  [3/6] Event-Log Analyse (letzte 24 Stunden)..." -ForegroundColor Cyan
    try {
        $seit24h = (Get-Date).AddHours(-24)
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'System', 'Application'
            Level     = 1, 2   # Critical=1, Error=2
            StartTime = $seit24h
        } -ErrorAction SilentlyContinue

        $anzahlEvents = @($events).Count
        $haeufigeQuellen = if ($anzahlEvents -gt 0) {
            $events | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5
        } else { @() }

        if ($anzahlEvents -gt 50) {
            $ergebnisse['EventLog'] = @{ Status = 'Rot'; Text = "$anzahlEvents kritische Fehler" }
            Write-Host "  [ROT]  Event-Log: $anzahlEvents kritische/Fehler-Ereignisse" -ForegroundColor Red
        }
        elseif ($anzahlEvents -gt 10) {
            $ergebnisse['EventLog'] = @{ Status = 'Gelb'; Text = "$anzahlEvents Fehler-Ereignisse" }
            Write-Host "  [WARN] Event-Log: $anzahlEvents Fehler-Ereignisse" -ForegroundColor Yellow
        }
        else {
            $ergebnisse['EventLog'] = @{ Status = 'Gruen'; Text = "$anzahlEvents Fehler (normal)" }
            Write-Host "  [OK]   Event-Log: $anzahlEvents Fehler-Ereignisse (letzte 24h)" -ForegroundColor Green
        }

        if ($haeufigeQuellen.Count -gt 0) {
            Write-Host "         Haeufigste Quellen:" -ForegroundColor Gray
            foreach ($q in $haeufigeQuellen) {
                Write-Host "         - $($q.Name): $($q.Count)x" -ForegroundColor Gray
            }
        }
    }
    catch {
        $ergebnisse['EventLog'] = @{ Status = 'Gelb'; Text = "Event-Log konnte nicht gelesen werden" }
        Write-Host "  [WARN] Event-Log-Analyse fehlgeschlagen" -ForegroundColor Yellow
    }

    # --- Datentraeger-Gesundheit ---
    Write-Host "  [4/6] Datentraeger-Gesundheit..." -ForegroundColor Cyan
    try {
        $datentraeger = Get-PhysicalDisk -ErrorAction Stop
        $fehlerhaft = @($datentraeger | Where-Object { $_.HealthStatus -notin @('Healthy', 'Gesund') })

        if ($fehlerhaft.Count -gt 0) {
            $ergebnisse['Datentraeger'] = @{ Status = 'Rot'; Text = "$($fehlerhaft.Count) Laufwerk(e) fehlerhaft" }
            Write-Host "  [ROT]  Datentraeger: $($fehlerhaft.Count) Laufwerk(e) haben Probleme" -ForegroundColor Red
            foreach ($d in $fehlerhaft) {
                Write-Host "         - $($d.FriendlyName): $($d.HealthStatus)" -ForegroundColor Red
            }
        }
        else {
            $ergebnisse['Datentraeger'] = @{ Status = 'Gruen'; Text = "Alle Laufwerke OK" }
            Write-Host "  [OK]   Datentraeger: Alle $(@($datentraeger).Count) Laufwerk(e) gesund" -ForegroundColor Green
            foreach ($d in $datentraeger) {
                Write-Host "         - $($d.FriendlyName): $($d.HealthStatus) ($($d.MediaType))" -ForegroundColor Gray
            }
        }
    }
    catch {
        $ergebnisse['Datentraeger'] = @{ Status = 'Gelb'; Text = "Status nicht ermittelbar" }
        Write-Host "  [WARN] Datentraeger-Status konnte nicht ermittelt werden" -ForegroundColor Yellow
    }

    # --- Windows-Aktivierung ---
    Write-Host "  [5/6] Windows-Aktivierungsstatus..." -ForegroundColor Cyan
    try {
        $aktivierung = & slmgr.vbs /xpr 2>&1
        $aktivierungText = $aktivierung | Out-String

        if ($aktivierungText -match 'permanent|dauerhaft aktiviert|Licensed') {
            $ergebnisse['Aktivierung'] = @{ Status = 'Gruen'; Text = "Windows dauerhaft aktiviert" }
            Write-Host "  [OK]   Windows: Dauerhaft aktiviert" -ForegroundColor Green
        }
        elseif ($aktivierungText -match 'laeuft ab|expires|Testversion') {
            $ergebnisse['Aktivierung'] = @{ Status = 'Gelb'; Text = "Aktivierung laeuft ab" }
            Write-Host "  [WARN] Windows: Aktivierung laeuft ab" -ForegroundColor Yellow
        }
        else {
            $ergebnisse['Aktivierung'] = @{ Status = 'Rot'; Text = "Nicht aktiviert" }
            Write-Host "  [ROT]  Windows: Moeglicherweise nicht aktiviert" -ForegroundColor Red
        }
    }
    catch {
        # Alternativer Check
        try {
            $slStatus = (Get-CimInstance -ClassName SoftwareLicensingProduct |
                Where-Object { $_.PartialProductKey } |
                Select-Object -First 1).LicenseStatus
            if ($slStatus -eq 1) {
                $ergebnisse['Aktivierung'] = @{ Status = 'Gruen'; Text = "Aktiviert (LicenseStatus=1)" }
                Write-Host "  [OK]   Windows: Aktiviert" -ForegroundColor Green
            }
            else {
                $ergebnisse['Aktivierung'] = @{ Status = 'Gelb'; Text = "Status: $slStatus" }
                Write-Host "  [WARN] Windows: LicenseStatus=$slStatus" -ForegroundColor Yellow
            }
        }
        catch {}
    }

    # --- Pending Reboot ---
    Write-Host "  [6/6] Neustart-Status..." -ForegroundColor Cyan
    $reboot = Test-PendingReboot
    if ($reboot.NeuStartNoetig) {
        $ergebnisse['Neustart'] = @{ Status = 'Gelb'; Text = "Neustart steht aus: $($reboot.Gruende -join ', ')" }
        Write-Host "  [WARN] Neustart steht aus: $($reboot.Gruende -join ', ')" -ForegroundColor Yellow
    }
    else {
        $ergebnisse['Neustart'] = @{ Status = 'Gruen'; Text = "Kein Neustart erforderlich" }
        Write-Host "  [OK]   Kein ausstehender Neustart" -ForegroundColor Green
    }

    # --- Ampel-Zusammenfassung ---
    Write-Host ""
    Write-Trennlinie -Titel ' Zusammenfassung '
    Write-Host ""

    $rotAnzahl  = ($ergebnisse.Values | Where-Object { $_.Status -eq 'Rot'  }).Count
    $gelbAnzahl = ($ergebnisse.Values | Where-Object { $_.Status -eq 'Gelb' }).Count
    $gruenAnzahl = ($ergebnisse.Values | Where-Object { $_.Status -eq 'Gruen' }).Count

    foreach ($kategorie in $ergebnisse.Keys) {
        $e    = $ergebnisse[$kategorie]
        $icon = switch ($e.Status) {
            'Gruen' { '🟢' }
            'Gelb'  { '🟡' }
            'Rot'   { '🔴' }
            default { '⚪' }
        }
        $farbe = switch ($e.Status) {
            'Gruen' { 'Green'  }
            'Gelb'  { 'Yellow' }
            'Rot'   { 'Red'    }
            default { 'Gray'   }
        }
        Write-Host "  $icon  $kategorie : $($e.Text)" -ForegroundColor $farbe
    }

    Write-Host ""
    $gesamtStatus = if ($rotAnzahl -gt 0) { "ROT ($rotAnzahl kritisch)" }
                    elseif ($gelbAnzahl -gt 0) { "GELB ($gelbAnzahl Warnungen)" }
                    else { "GRUEN (alles OK)" }
    Write-Host "  Gesamtstatus: $gesamtStatus" -ForegroundColor $(if ($rotAnzahl -gt 0) { 'Red' } elseif ($gelbAnzahl -gt 0) { 'Yellow' } else { 'Green' })

    Write-Log -Nachricht "Diagnose abgeschlossen: $gesamtStatus (OK:$gruenAnzahl, Warn:$gelbAnzahl, Fehler:$rotAnzahl)" -Ebene 'Info'
    Write-Host ""

    if ($rotAnzahl -gt 0) {
        Write-Host "  Empfehlung: Option [2] - Haeufige Fehler beheben" -ForegroundColor Yellow
    }

    Write-Host "  Druecke eine Taste um zurueck zum Menue zu kehren..." -ForegroundColor Gray
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { Start-Sleep -Seconds 3 }
}

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 2: Haeufige Fehler beheben (Untermenü)
# ─────────────────────────────────────────────────────────────────────────────
function Show-ReparaturMenue {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "  ╔═════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "  ║  🔧 Haeufige Fehler beheben                    ║" -ForegroundColor Yellow
        Write-Host "  ╠═════════════════════════════════════════════════╣" -ForegroundColor Yellow
        Write-Host "  ║  [1] DNS-Cache leeren + Winsock reset          ║" -ForegroundColor White
        Write-Host "  ║  [2] Windows Update zuruecksetzen              ║" -ForegroundColor White
        Write-Host "  ║  [3] DISM /RestoreHealth                       ║" -ForegroundColor White
        Write-Host "  ║  [4] Netzwerk komplett zuruecksetzen           ║" -ForegroundColor White
        Write-Host "  ║  [5] Microsoft Store zuruecksetzen (wsreset)   ║" -ForegroundColor White
        Write-Host "  ║  [6] Temporaere Dateien bereinigen             ║" -ForegroundColor White
        Write-Host "  ║  [7] Drucker-Spooler reparieren                ║" -ForegroundColor White
        Write-Host "  ║  [A] ALLE Reparaturen ausfuehren               ║" -ForegroundColor Cyan
        Write-Host "  ║  [Z] Zurueck                                   ║" -ForegroundColor Gray
        Write-Host "  ╚═════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Auswahl: " -ForegroundColor Yellow -NoNewline

        $wahl = try { (Read-Host).Trim().ToUpper() } catch { 'Z' }

        switch ($wahl) {
            '1' { Repair-DNS;           Wait-Taste }
            '2' { Repair-WindowsUpdate; Wait-Taste }
            '3' { Repair-DISM;          Wait-Taste }
            '4' { Repair-Netzwerk;      Wait-Taste }
            '5' { Repair-Store;         Wait-Taste }
            '6' { Repair-Temp;          Wait-Taste }
            '7' { Repair-Spooler;       Wait-Taste }
            'A' {
                Repair-DNS
                Repair-Temp
                Repair-Store
                Repair-Netzwerk
                Repair-WindowsUpdate
                Repair-Spooler
                Repair-DISM
                Write-Host ""
                Write-Log -Nachricht "Alle Reparaturen abgeschlossen." -Ebene 'Success'
                Wait-Taste
            }
            'Z' { return }
        }
    } while ($true)
}

function Wait-Taste {
    Write-Host ""
    Write-Host "  Druecke eine Taste um fortzufahren..." -ForegroundColor Gray
    try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { Start-Sleep -Seconds 2 }
}

function Repair-DNS {
    Write-Log -Nachricht "DNS-Cache leeren + Winsock reset..." -Ebene 'Info'
    try {
        & ipconfig.exe /flushdns 2>&1 | Out-Null
        Write-Log -Nachricht "DNS-Cache geleert" -Ebene 'Success'
        Write-Host "  [OK] DNS-Cache geleert" -ForegroundColor Green

        & netsh.exe winsock reset 2>&1 | Out-Null
        Write-Log -Nachricht "Winsock zurueckgesetzt (Neustart erforderlich)" -Ebene 'Success'
        Write-Host "  [OK] Winsock zurueckgesetzt (Neustart erforderlich)" -ForegroundColor Green

        & netsh.exe int ip reset 2>&1 | Out-Null
        Write-Log -Nachricht "IP-Stack zurueckgesetzt" -Ebene 'Success'
        Write-Host "  [OK] IP-Stack zurueckgesetzt" -ForegroundColor Green
    }
    catch {
        Write-Log -Nachricht "DNS/Winsock-Reset teilweise fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
    }
}

function Repair-WindowsUpdate {
    Write-Log -Nachricht "Windows Update zuruecksetzen..." -Ebene 'Info'
    Write-Host "  Windows Update-Dienste stoppen..." -ForegroundColor Cyan

    $dienste = @('wuauserv', 'cryptSvc', 'bits', 'msiserver')
    try {
        foreach ($d in $dienste) {
            Stop-Service -Name $d -Force -ErrorAction SilentlyContinue
        }

        # SoftwareDistribution und catroot2 umbenennen
        $backupSuffix = "_backup_$(Get-Date -Format 'yyyyMMdd_HHmm')"

        $pfade = @(
            'C:\Windows\SoftwareDistribution',
            'C:\Windows\System32\catroot2'
        )
        foreach ($pfad in $pfade) {
            if (Test-Path $pfad) {
                $neuerName = $pfad + $backupSuffix
                try {
                    Rename-Item -Path $pfad -NewName $neuerName -Force -ErrorAction Stop
                    Write-Host "  [OK] Umbenannt: $pfad" -ForegroundColor Green
                    Write-Log -Nachricht "Umbenannt: $pfad -> $neuerName" -Ebene 'Success'
                }
                catch {
                    Write-Host "  [WARN] Konnte nicht umbenennen: $pfad" -ForegroundColor Yellow
                }
            }
        }

        # BITS und WU-Dienste neu registrieren
        & regsvr32.exe /s atl.dll 2>&1 | Out-Null
        & regsvr32.exe /s urlmon.dll 2>&1 | Out-Null
        & regsvr32.exe /s mshtml.dll 2>&1 | Out-Null
        & regsvr32.exe /s shdocvw.dll 2>&1 | Out-Null
        & regsvr32.exe /s wuapi.dll 2>&1 | Out-Null
        & regsvr32.exe /s wuaueng.dll 2>&1 | Out-Null
        & regsvr32.exe /s wucltux.dll 2>&1 | Out-Null
        & regsvr32.exe /s wups.dll 2>&1 | Out-Null
        & regsvr32.exe /s wups2.dll 2>&1 | Out-Null

        foreach ($d in $dienste) {
            Start-Service -Name $d -ErrorAction SilentlyContinue
        }

        Write-Host "  [OK] Windows Update erfolgreich zurueckgesetzt" -ForegroundColor Green
        Write-Log -Nachricht "Windows Update zurueckgesetzt" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "Windows Update Reset fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
        # Dienste trotzdem neu starten
        foreach ($d in $dienste) {
            Start-Service -Name $d -ErrorAction SilentlyContinue
        }
    }
}

function Repair-DISM {
    Write-Log -Nachricht "DISM /RestoreHealth starten..." -Ebene 'Info'
    Write-Host "  DISM RestoreHealth (kann 10-30 Minuten dauern)..." -ForegroundColor Cyan

    try {
        $dismLog = Join-Path $ToolkitRoot "logs\dism_repair_$(Get-Date -Format 'yyyyMMdd_HHmm').log"
        $ausgabe = & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1
        $ausgabe | Out-File -FilePath $dismLog -Encoding UTF8

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] DISM RestoreHealth erfolgreich" -ForegroundColor Green
            Write-Log -Nachricht "DISM RestoreHealth: Erfolgreich" -Ebene 'Success'
        }
        else {
            Write-Host "  [WARN] DISM beendet mit Code $LASTEXITCODE (Log: $dismLog)" -ForegroundColor Yellow
            Write-Log -Nachricht "DISM beendet mit Code $LASTEXITCODE" -Ebene 'Warn'
        }
    }
    catch {
        Write-Host "  [FEHLER] DISM fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log -Nachricht "DISM RestoreHealth fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
    }
}

function Repair-Netzwerk {
    Write-Log -Nachricht "Netzwerk komplett zuruecksetzen..." -Ebene 'Info'
    Write-Host "  Netzwerk-Reset..." -ForegroundColor Cyan

    try {
        & netsh.exe int ip reset resetlog.txt 2>&1 | Out-Null
        & netsh.exe int ipv6 reset 2>&1 | Out-Null
        & netsh.exe winsock reset catalog 2>&1 | Out-Null
        & ipconfig.exe /release 2>&1 | Out-Null
        & ipconfig.exe /flushdns 2>&1 | Out-Null
        & ipconfig.exe /renew 2>&1 | Out-Null
        & netsh.exe advfirewall reset 2>&1 | Out-Null

        Write-Host "  [OK] Netzwerk zurueckgesetzt (Neustart empfohlen)" -ForegroundColor Green
        Write-Log -Nachricht "Netzwerk-Reset abgeschlossen" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "Netzwerk-Reset fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
    }
}

function Repair-Store {
    Write-Log -Nachricht "Microsoft Store zuruecksetzen (wsreset.exe)..." -Ebene 'Info'
    Write-Host "  Store-Reset..." -ForegroundColor Cyan

    try {
        # Store-Cache loeschen
        $storeCachePfad = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\Cache"
        if (Test-Path $storeCachePfad) {
            Remove-Item -Path $storeCachePfad -Recurse -Force -ErrorAction SilentlyContinue
        }

        # WSReset ausfuehren
        Start-Process -FilePath 'wsreset.exe' -Wait -ErrorAction Stop
        Write-Host "  [OK] Microsoft Store zurueckgesetzt" -ForegroundColor Green
        Write-Log -Nachricht "Microsoft Store Reset erfolgreich" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "Store-Reset fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Warn'

        # Alternativer Reset via PowerShell
        try {
            Get-AppxPackage -Name 'Microsoft.WindowsStore' |
                ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue }
            Write-Host "  [OK] Store-Registrierung erneuert" -ForegroundColor Green
        }
        catch {}
    }
}

function Repair-Temp {
    Write-Log -Nachricht "Temporaere Dateien bereinigen..." -Ebene 'Info'
    Write-Host "  Bereinige Temp-Ordner..." -ForegroundColor Cyan

    $tempPfade = @($env:TEMP, $env:TMP, 'C:\Windows\Temp')
    $geloescht = 0

    foreach ($pfad in $tempPfade) {
        if (Test-Path $pfad) {
            $dateien = Get-ChildItem -Path $pfad -Recurse -Force -ErrorAction SilentlyContinue
            foreach ($d in $dateien) {
                try {
                    Remove-Item -Path $d.FullName -Force -Recurse -ErrorAction SilentlyContinue
                    $geloescht++
                } catch {}
            }
        }
    }

    Write-Host "  [OK] $geloescht Temp-Elemente entfernt" -ForegroundColor Green
    Write-Log -Nachricht "Temp bereinigt: $geloescht Elemente" -Ebene 'Success'
}

function Repair-Spooler {
    Write-Log -Nachricht "Drucker-Spooler reparieren..." -Ebene 'Info'
    Write-Host "  Repariere Drucker-Spooler..." -ForegroundColor Cyan

    try {
        # Spooler stoppen
        Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Druckerjobs loeschen
        $spoolPfad = 'C:\Windows\System32\spool\PRINTERS'
        if (Test-Path $spoolPfad) {
            Get-ChildItem -Path $spoolPfad -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Druckerwarteschlange geleert" -ForegroundColor Green
        }

        # Drucker-DLLs neu registrieren
        & regsvr32.exe /s printui.dll 2>&1 | Out-Null
        & regsvr32.exe /s winspool.drv 2>&1 | Out-Null

        # Spooler neu starten
        Set-Service -Name Spooler -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name Spooler -ErrorAction Stop

        Write-Host "  [OK] Drucker-Spooler neugestartet" -ForegroundColor Green
        Write-Log -Nachricht "Drucker-Spooler repariert und neugestartet" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "Spooler-Reparatur fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
        Write-Host "  [FEHLER] Spooler: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 3: Backup erstellen
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Backup {
    Clear-Host
    Write-Host ""
    Write-Trennlinie -Titel ' Backup erstellen '
    Write-Host ""

    # Vorhandene Wiederherstellungspunkte anzeigen
    Write-Host "  Vorhandene Systemwiederherstellungspunkte:" -ForegroundColor Cyan
    try {
        $punkte = Get-ComputerRestorePoint -ErrorAction Stop
        if (@($punkte).Count -gt 0) {
            $punkte | Select-Object SequenceNumber, Description, CreationTime |
                ForEach-Object {
                    $zeit = [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime)
                    Write-Host ("  [{0:D3}] {1} - {2}" -f $_.SequenceNumber,
                        $zeit.ToString('dd.MM.yyyy HH:mm'),
                        $_.Description) -ForegroundColor Gray
                }
        }
        else {
            Write-Host "  (Keine Wiederherstellungspunkte vorhanden)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  (Wiederherstellungspunkte konnten nicht geladen werden)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Backup-Optionen:" -ForegroundColor White
    Write-Host "  [1] Wiederherstellungspunkt erstellen" -ForegroundColor White
    Write-Host "  [2] Systemabbild erstellen (wbAdmin)" -ForegroundColor White
    Write-Host "  [Z] Zurueck" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Auswahl: " -ForegroundColor Yellow -NoNewline

    $wahl = try { (Read-Host).Trim() } catch { 'Z' }

    switch ($wahl) {
        '1' {
            Write-Host ""
            Write-Host "  Beschreibung (ENTER fuer Standard): " -ForegroundColor Yellow -NoNewline
            $beschreibung = try { Read-Host } catch { "" }
            if ([string]::IsNullOrWhiteSpace($beschreibung)) {
                $beschreibung = "Manueller Wiederherstellungspunkt $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
            }
            New-Wiederherstellungspunkt -Beschreibung $beschreibung
        }
        '2' {
            Write-Host ""
            Write-Host "  Ziellaufwerk fuer Systemabbild (z.B. D:): " -ForegroundColor Yellow -NoNewline
            $ziel = try { Read-Host } catch { "" }

            if ([string]::IsNullOrWhiteSpace($ziel)) {
                Write-Host "  Kein Laufwerk angegeben. Abgebrochen." -ForegroundColor Yellow
            }
            else {
                Write-Log -Nachricht "Erstelle Systemabbild auf $ziel..." -Ebene 'Info'
                Write-Host "  Starte wbAdmin (kann sehr lange dauern)..." -ForegroundColor Cyan
                try {
                    $wbadminOutput = & wbAdmin.exe start backup `
                        -backupTarget:"$ziel" `
                        -include:"C:" `
                        -allCritical `
                        -quiet `
                        2>&1

                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  [OK] Systemabbild erstellt auf $ziel" -ForegroundColor Green
                        Write-Log -Nachricht "Systemabbild erstellt auf $ziel" -Ebene 'Success'
                    }
                    else {
                        Write-Host "  [WARN] wbAdmin beendet mit Code $LASTEXITCODE" -ForegroundColor Yellow
                        Write-Log -Nachricht "wbAdmin ExitCode: $LASTEXITCODE" -Ebene 'Warn'
                    }
                }
                catch {
                    Write-Host "  [FEHLER] wbAdmin fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Log -Nachricht "wbAdmin fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
                }
            }
        }
        'Z' { return }
    }

    Wait-Taste
}

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 4: Wiederherstellungspunkt laden
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Wiederherstellung {
    Clear-Host
    Write-Host ""
    Write-Trennlinie -Titel ' Wiederherstellungspunkt laden '
    Write-Host ""
    Write-Host "  HINWEIS: Die Systemwiederherstellung wird im laufenden System" -ForegroundColor Yellow
    Write-Host "           ausgefuehrt. Das System wird automatisch neu gestartet." -ForegroundColor Yellow
    Write-Host ""

    try {
        $punkte = Get-ComputerRestorePoint -ErrorAction Stop
        if (-not $punkte -or @($punkte).Count -eq 0) {
            Write-Host "  Keine Wiederherstellungspunkte vorhanden." -ForegroundColor Red
            Wait-Taste
            return
        }

        Write-Host "  Verfuegbare Wiederherstellungspunkte:" -ForegroundColor Cyan
        Write-Host ""
        $i = 0
        $punktListe = @()
        foreach ($p in ($punkte | Sort-Object SequenceNumber -Descending)) {
            $i++
            $zeit = [Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime)
            Write-Host ("  [{0}] {1} - {2}" -f $i, $zeit.ToString('dd.MM.yyyy HH:mm'), $p.Description) -ForegroundColor White
            $punktListe += $p
        }

        Write-Host ""
        Write-Host "  Nummer waehlen (ENTER = Abbrechen): " -ForegroundColor Yellow -NoNewline
        $eingabe = try { Read-Host } catch { "" }

        if ([string]::IsNullOrWhiteSpace($eingabe)) { return }

        $nr = 0
        if ([int]::TryParse($eingabe, [ref]$nr) -and $nr -ge 1 -and $nr -le $punktListe.Count) {
            $gewaehlterPunkt = $punktListe[$nr - 1]
            $zeit = [Management.ManagementDateTimeConverter]::ToDateTime($gewaehlterPunkt.CreationTime)

            Write-Host ""
            Write-Host "  Gewaehlt: $($gewaehlterPunkt.Description) ($($zeit.ToString('dd.MM.yyyy HH:mm')))" -ForegroundColor Yellow
            Write-Host ""

            $bestaetigt = Confirm-Schritt -Frage "Systemwiederherstellung JETZT starten? (System wird neugestartet!)"
            if ($bestaetigt) {
                Write-Log -Nachricht "Systemwiederherstellung wird gestartet: $($gewaehlterPunkt.Description)" -Ebene 'Warn'
                try {
                    Restore-Computer -RestorePoint $gewaehlterPunkt.SequenceNumber -ErrorAction Stop
                    Write-Host "  [OK] Systemwiederherstellung eingeleitet. Neustart erfolgt..." -ForegroundColor Green
                }
                catch {
                    # Fallback: rstrui.exe starten
                    Write-Host "  Starte Systemwiederherstellungs-Assistent..." -ForegroundColor Cyan
                    Start-Process -FilePath 'rstrui.exe' -ArgumentList "/restorepoint:$($gewaehlterPunkt.SequenceNumber)"
                }
            }
        }
        else {
            Write-Host "  Ungueltige Auswahl." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  Systemwiederherstellung nicht verfuegbar: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Oeffne Systemsteuerung > Wiederherstellung manuell." -ForegroundColor Yellow
        Write-Log -Nachricht "Systemwiederherstellung fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
    }

    Wait-Taste
}

# ─────────────────────────────────────────────────────────────────────────────
# OPTION 5: Neustart & Werksreset
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-WerksReset {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "  ║  ⚠️  ACHTUNG: WERKSRESET / WINDOWS ZURUECKSETZEN        ║" -ForegroundColor Red
    Write-Host "  ╚══════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Diese Aktion setzt Windows auf den Werkszustand zurueck." -ForegroundColor Yellow
    Write-Host "  ALLE installierten Programme werden GELOESCHT." -ForegroundColor Yellow
    Write-Host ""

    # 3-fache Bestaetigung
    Write-Host "  SCHRITT 1/3: Wirklich fortfahren?" -ForegroundColor Red
    $b1 = Confirm-Schritt -Frage "Ich verstehe, dass alle Programme geloescht werden"
    if (-not $b1) {
        Write-Host "  Abgebrochen." -ForegroundColor Green
        Wait-Taste
        return
    }

    Write-Host ""
    Write-Host "  SCHRITT 2/3: Haben Sie alle wichtigen Daten gesichert?" -ForegroundColor Red
    $b2 = Confirm-Schritt -Frage "Ich habe alle Daten gesichert"
    if (-not $b2) {
        Write-Host "  Abgebrochen. Bitte zuerst Daten sichern." -ForegroundColor Yellow
        Wait-Taste
        return
    }

    Write-Host ""
    Write-Host "  SCHRITT 3/3: LETZTE WARNUNG - Wirklich fortfahren?" -ForegroundColor Red
    $b3 = Confirm-Schritt -Frage "JA - Windows jetzt zuruecksetzen"
    if (-not $b3) {
        Write-Host "  Abgebrochen." -ForegroundColor Green
        Wait-Taste
        return
    }

    # Art des Resets waehlen
    Write-Host ""
    Write-Host "  Reset-Optionen:" -ForegroundColor Cyan
    Write-Host "  [1] Eigene Dateien behalten (nur Programme entfernen)" -ForegroundColor White
    Write-Host "  [2] Alles loeschen (Saubere Installation)" -ForegroundColor White
    Write-Host "  [Z] Abbrechen" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Auswahl: " -ForegroundColor Yellow -NoNewline
    $resetWahl = try { (Read-Host).Trim() } catch { 'Z' }

    switch ($resetWahl) {
        '1' {
            Write-Log -Nachricht "Werksreset gestartet: Dateien behalten" -Ebene 'Warn'
            try {
                # systemreset.exe - ohne Parameter = interaktiv, /cleanpc = alles
                Start-Process -FilePath 'systemreset.exe' -ArgumentList '-factoryreset'
                Write-Host "  [OK] Werksreset eingeleitet (Dateien behalten)." -ForegroundColor Green
            }
            catch {
                # Fallback: Reset-Computer
                try {
                    Reset-Computer -ResetType KeepUserData -WhatIf:$false -Force -ErrorAction Stop
                }
                catch {
                    Write-Host "  Starte Einstellungen > Wiederherstellung manuell..." -ForegroundColor Yellow
                    Start-Process 'ms-settings:recovery'
                }
            }
        }
        '2' {
            Write-Log -Nachricht "Werksreset gestartet: ALLES LOESCHEN" -Ebene 'Warn'
            try {
                Start-Process -FilePath 'systemreset.exe'
                Write-Host "  [OK] Werksreset eingeleitet." -ForegroundColor Green
            }
            catch {
                Write-Host "  Starte Einstellungen > Wiederherstellung manuell..." -ForegroundColor Yellow
                Start-Process 'ms-settings:recovery'
            }
        }
        'Z' {
            Write-Host "  Abgebrochen." -ForegroundColor Green
        }
    }

    Wait-Taste
}

# ─────────────────────────────────────────────────────────────────────────────
# HAUPTSCHLEIFE
# ─────────────────────────────────────────────────────────────────────────────
Show-ToolkitBanner -Modul '30 - Reparatur & Diagnose'

do {
    Show-HauptMenue

    $wahl = try { (Read-Host).Trim().ToUpper() } catch { 'Q' }

    switch ($wahl) {
        '1' { Invoke-Diagnose }
        '2' { Show-ReparaturMenue }
        '3' { Invoke-Backup }
        '4' { Invoke-Wiederherstellung }
        '5' { Invoke-WerksReset }
        'Q' {
            Write-Host ""
            Write-Log -Nachricht "30-Repair.ps1 beendet." -Ebene 'Info'
            Write-Host "  Auf Wiedersehen!" -ForegroundColor Cyan
            Write-Host ""
            exit 0
        }
        default {
            Write-Host "  Ungueltige Eingabe: '$wahl'" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }

} while ($true)
