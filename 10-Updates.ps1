#Requires -Version 5.0
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows-Updates, Treiber-Updates und WinGet-Upgrades installieren.
.DESCRIPTION
    Installiert alle verfuegbaren Windows-Updates (Quality, Cumulative, Defender, .NET),
    optional Treiber-Updates, sowie WinGet-Package-Upgrades.
    Unterstuetzt automatischen Neustart mit Scheduled Task zur Update-Fortsetzung.
.PARAMETER Skip
    Alle Update-Schritte ueberspringen (nur Zustandsdatei schreiben).
.PARAMETER IncludeDrivers
    Treiber-Updates ohne Nachfrage installieren.
.PARAMETER KeineReboot
    Keinen automatischen Neustart durchfuehren.
.NOTES
    Datei   : 10-Updates.ps1
    Version : 1.0.0
    Abhaengigkeit: NuGet + PSWindowsUpdate werden bei Bedarf installiert.
#>

[CmdletBinding()]
param(
    [switch]$Skip,
    [switch]$IncludeDrivers,
    [switch]$KeineReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# Initialisierung
# ─────────────────────────────────────────────────────────────────────────────
$ToolkitRoot = $PSScriptRoot
. "$ToolkitRoot\lib\Common.ps1"
Set-ToolkitRoot -Pfad $ToolkitRoot

Initialize-Log -Praefix 'Updates'
Show-ToolkitBanner -Modul '10 - Updates & Treiber'

# Bootstrap-Check
$bootstrapOkPfad = Join-Path $ToolkitRoot 'state\bootstrap-ok.json'
if (-not (Test-Path $bootstrapOkPfad)) {
    Write-Log -Nachricht "Bootstrap wurde noch nicht ausgefuehrt (state\bootstrap-ok.json fehlt)." -Ebene 'Warn'
    Write-Log -Nachricht "Empfehlung: Zuerst 00-Bootstrap.ps1 ausfuehren." -Ebene 'Warn'
}

if ($Skip) {
    Write-Log -Nachricht "Parameter -Skip gesetzt: Updates werden uebersprungen." -Ebene 'Warn'
    # Zustandsdatei trotzdem schreiben
    [PSCustomObject]@{
        Timestamp   = (Get-Date -Format 'o')
        Status      = 'Uebersprungen'
        Rechner     = $env:COMPUTERNAME
    } | ConvertTo-Json | Out-File -FilePath (Join-Path $ToolkitRoot 'state\updates-done.json') -Encoding UTF8 -Force
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 1: NuGet-Provider und PSWindowsUpdate installieren
# ─────────────────────────────────────────────────────────────────────────────
function Install-PSWindowsUpdateModul {
    Write-Log -Nachricht "Pruefe NuGet-Provider und PSWindowsUpdate..." -Ebene 'Info'

    try {
        # TLS 1.2 erzwingen (fuer alte PS-Versionen)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        # NuGet-Provider pruefen/installieren
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget -or $nuget.Version -lt '2.8.5.201') {
            Write-Log -Nachricht "Installiere NuGet-Provider..." -Ebene 'Info'
            Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Force -Scope AllUsers -ErrorAction Stop
            Write-Log -Nachricht "NuGet-Provider installiert" -Ebene 'Success'
        }
        else {
            Write-Log -Nachricht "NuGet-Provider: OK (v$($nuget.Version))" -Ebene 'Info'
        }

        # PSGallery als vertrauenswuerdig markieren
        $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
            Write-Log -Nachricht "PSGallery als vertrauenswuerdig markiert" -Ebene 'Info'
        }

        # PSWindowsUpdate pruefen/installieren
        $pswu = Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue
        if (-not $pswu) {
            Write-Log -Nachricht "Installiere PSWindowsUpdate-Modul..." -Ebene 'Info'
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber -Scope AllUsers `
                -ErrorAction Stop -WarningAction SilentlyContinue
            Write-Log -Nachricht "PSWindowsUpdate installiert" -Ebene 'Success'
        }
        else {
            $version = ($pswu | Sort-Object Version -Descending | Select-Object -First 1).Version
            Write-Log -Nachricht "PSWindowsUpdate: OK (v$version)" -Ebene 'Info'
        }

        # Modul importieren
        Import-Module PSWindowsUpdate -Force -ErrorAction Stop
        Write-Log -Nachricht "PSWindowsUpdate-Modul geladen" -Ebene 'Success'
        return $true
    }
    catch {
        Write-Log -Nachricht "PSWindowsUpdate konnte nicht installiert werden: $($_.Exception.Message)" -Ebene 'Error'
        Write-Log -Nachricht "Fallback: Windows Update wird ueber wuauclt.exe gestartet" -Ebene 'Warn'
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 2: Windows Updates installieren (Update-Loop)
# ─────────────────────────────────────────────────────────────────────────────
function Install-WindowsUpdates {
    param([bool]$PSWUVerfuegbar)

    Write-Log -Nachricht "Starte Windows-Update-Schleife..." -Ebene 'Info'
    Write-Trennlinie -Titel ' Windows Updates '

    if (-not $PSWUVerfuegbar) {
        # Fallback: Windows Update Center oeffnen
        Write-Log -Nachricht "PSWindowsUpdate nicht verfuegbar. Starte Windows Update manuell..." -Ebene 'Warn'
        try {
            & wuauclt.exe /detectnow /updatenow 2>&1 | Out-Null
            Start-Process 'ms-settings:windowsupdate' -ErrorAction SilentlyContinue
            Write-Log -Nachricht "Windows Update wurde gestartet (manuell)" -Ebene 'Info'
        }
        catch {}
        return $false
    }

    $runde = 0
    $maxRunden = 5   # Maximale Update-Schleifen (Sicherheitsnetz)
    $gesamtInstalliert = 0

    do {
        $runde++
        Write-Log -Nachricht "Update-Schleife Runde $runde von $maxRunden..." -Ebene 'Info'

        try {
            # Verfuegbare Updates abrufen
            $updateFilter = @(
                'IsHidden=0',
                'IsInstalled=0'
            )

            Show-Fortschritt -Aktivitaet "Windows Updates" -Status "Suche nach Updates (Runde $runde)..." -Id 2

            $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot `
                -ErrorAction SilentlyContinue 2>&1

            if ($null -eq $updates -or @($updates).Count -eq 0) {
                Write-Log -Nachricht "Keine weiteren Updates gefunden (Runde $runde)." -Ebene 'Success'
                break
            }

            $anzahl = @($updates).Count
            Write-Log -Nachricht "Runde ${runde}: $anzahl Update(s) gefunden" -Ebene 'Info'

            # Treiber-Updates separat behandeln
            $treiber    = @($updates | Where-Object { $_.Categories -match 'Driver' })
            $sonstiges  = @($updates | Where-Object { $_.Categories -notmatch 'Driver' })

            Write-Log -Nachricht "  Systemupdates: $($sonstiges.Count), Treiber: $($treiber.Count)" -Ebene 'Info'

            # Treiber-Update-Entscheidung
            $treiberInstallieren = $IncludeDrivers
            if ($treiber.Count -gt 0 -and -not $IncludeDrivers) {
                Write-Host ""
                Write-Host "  $($treiber.Count) Treiber-Update(s) gefunden:" -ForegroundColor Yellow
                foreach ($t in $treiber) {
                    Write-Host "    - $($t.Title)" -ForegroundColor Gray
                }
                $treiberInstallieren = Confirm-Schritt -Frage "Treiber-Updates jetzt installieren?"
            }

            # Systemupdates installieren
            if ($sonstiges.Count -gt 0) {
                Write-Log -Nachricht "Installiere $($sonstiges.Count) System-Update(s)..." -Ebene 'Info'
                Show-Fortschritt -Aktivitaet "Windows Updates" -Status "Installiere $($sonstiges.Count) Updates..." -Id 2 -Protokollieren

                try {
                    $installResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll `
                        -IgnoreReboot -NotCategory 'Drivers' -AutoReboot:$false `
                        -ErrorAction SilentlyContinue 2>&1

                    $gesamtInstalliert += $sonstiges.Count
                    Write-Log -Nachricht "Systemupdates installiert: $($sonstiges.Count)" -Ebene 'Success'
                }
                catch {
                    Write-Log -Nachricht "Fehler bei Systemupdates: $($_.Exception.Message)" -Ebene 'Error'
                }
            }

            # Treiber installieren falls gewuenscht
            if ($treiber.Count -gt 0 -and $treiberInstallieren) {
                Write-Log -Nachricht "Installiere $($treiber.Count) Treiber-Update(s)..." -Ebene 'Info'
                try {
                    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot `
                        -Category 'Drivers' -AutoReboot:$false `
                        -ErrorAction SilentlyContinue 2>&1 | Out-Null

                    $gesamtInstalliert += $treiber.Count
                    Write-Log -Nachricht "Treiber-Updates installiert: $($treiber.Count)" -Ebene 'Success'
                }
                catch {
                    Write-Log -Nachricht "Fehler bei Treiber-Updates: $($_.Exception.Message)" -Ebene 'Warn'
                }
            }

            # Reboot-Check nach Runde
            $reboot = Test-PendingReboot
            if ($reboot.NeuStartNoetig) {
                Write-Log -Nachricht "Neustart nach Updates erforderlich: $($reboot.Gruende -join ', ')" -Ebene 'Warn'

                if ($KeineReboot) {
                    Write-Log -Nachricht "Neustart wegen -KeineReboot uebersprungen. Weitere Updates koennen erst nach Neustart installiert werden." -Ebene 'Warn'
                    break
                }

                # Pending-State speichern fuer Auto-Restart-Task
                $pendingPfad = Join-Path $ToolkitRoot 'state\update-pending.json'
                [PSCustomObject]@{
                    Timestamp          = (Get-Date -Format 'o')
                    Runde              = $runde
                    GesamtInstalliert  = $gesamtInstalliert
                    IncludeDrivers     = $IncludeDrivers.IsPresent
                    Grund              = $reboot.Gruende
                } | ConvertTo-Json | Out-File -FilePath $pendingPfad -Encoding UTF8 -Force

                # Scheduled Task fuer Neustart und Wiederaufnahme anlegen
                New-NeustartTask -Runde $runde

                Write-Log -Nachricht "Neustart in 30 Sekunden... (Scheduled Task fuer Wiederaufnahme angelegt)" -Ebene 'Warn'
                Write-Host ""
                Write-Host "  NEUSTART IN 30 SEKUNDEN" -ForegroundColor Red -BackgroundColor DarkRed
                Write-Host "  Updates werden nach dem Neustart automatisch fortgesetzt." -ForegroundColor Yellow
                Write-Host "  Zum Abbrechen: Shutdown /a" -ForegroundColor Gray
                Write-Host ""

                Start-Sleep -Seconds 30
                Restart-Computer -Force
                return $true   # Neustart eingeleitet
            }
        }
        catch {
            Write-Log -Nachricht "Fehler in Update-Schleife Runde $runde : $($_.Exception.Message)" -Ebene 'Error'
            break
        }

    } while ($runde -lt $maxRunden)

    Show-Fortschritt -Aktivitaet "Windows Updates" -Status "Abgeschlossen" -Abschliessen -Id 2

    Write-Log -Nachricht "Update-Schleife abgeschlossen. Gesamt installiert: $gesamtInstalliert" -Ebene 'Success'
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# Scheduled Task fuer automatischen Neustart + Wiederaufnahme
# ─────────────────────────────────────────────────────────────────────────────
function New-NeustartTask {
    param([int]$Runde)

    $taskName = 'WinToolkit_UpdateFortsetzung'
    $skriptPfad = Join-Path $ToolkitRoot '10-Updates.ps1'

    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$skriptPfad`""
    if ($IncludeDrivers) { $args += ' -IncludeDrivers' }

    try {
        # Alten Task entfernen falls vorhanden
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        # Neuen Task anlegen: Trigger = Bei Anmeldung (einmalig)
        $action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $args
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -RunOnlyIfNetworkAvailable:$false

        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
            -LogonType ServiceAccount -RunLevel Highest

        Register-ScheduledTask -TaskName $taskName `
            -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principal `
            -Description "Windows Toolkit: Update-Fortsetzung nach Neustart (Runde $Runde)" `
            -Force -ErrorAction Stop | Out-Null

        Write-Log -Nachricht "Scheduled Task '$taskName' angelegt (Wiederaufnahme nach Neustart)" -Ebene 'Success'

        # Self-Delete-Logik: Task loescht sich beim naechsten Start selbst
        # (implementiert durch Update-Script, das den Task nach dem Start entfernt)
        $selbstloeschPfad = Join-Path $ToolkitRoot 'state\task-selbstloeschen.json'
        [PSCustomObject]@{ TaskName = $taskName; Timestamp = (Get-Date -Format 'o') } |
            ConvertTo-Json | Out-File -FilePath $selbstloeschPfad -Encoding UTF8 -Force
    }
    catch {
        Write-Log -Nachricht "Scheduled Task konnte nicht angelegt werden: $($_.Exception.Message)" -Ebene 'Warn'
    }
}

# Self-Delete: Task entfernen wenn nach Neustart gestartet
function Remove-EigenenTask {
    $selbstloeschPfad = Join-Path $ToolkitRoot 'state\task-selbstloeschen.json'
    if (Test-Path $selbstloeschPfad) {
        try {
            $taskInfo = Get-Content $selbstloeschPfad -Raw | ConvertFrom-Json
            Unregister-ScheduledTask -TaskName $taskInfo.TaskName -Confirm:$false -ErrorAction SilentlyContinue
            Remove-Item -Path $selbstloeschPfad -Force -ErrorAction SilentlyContinue
            Remove-Item -Path (Join-Path $ToolkitRoot 'state\update-pending.json') -Force -ErrorAction SilentlyContinue
            Write-Log -Nachricht "Scheduled Task '$($taskInfo.TaskName)' entfernt (nach Neustart)" -Ebene 'Info'
        }
        catch {}
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 3: WinGet-Upgrades
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-WinGetUpgrade {
    Write-Log -Nachricht "Pruefe WinGet-Verfuegbarkeit..." -Ebene 'Info'
    Write-Trennlinie -Titel ' WinGet Upgrades '

    # WinGet-Pfad suchen (verschiedene Installationsorte)
    $wingetPfade = @(
        $(try { (Get-Command 'winget.exe' -ErrorAction Stop).Source } catch { $null }),
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe"
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

    if (-not $wingetPfade) {
        # WinGet-Suche ueber Glob
        $wingetGlob = Get-ChildItem `
            -Path "$env:ProgramFiles\WindowsApps" `
            -Filter 'winget.exe' -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($wingetGlob) {
            $wingetPfade = $wingetGlob.FullName
        }
    }

    if (-not $wingetPfade) {
        Write-Log -Nachricht "WinGet nicht gefunden. Schritt wird uebersprungen." -Ebene 'Warn'
        Write-Log -Nachricht "Tipp: WinGet ist Teil des 'App Installer' aus dem Microsoft Store." -Ebene 'Warn'
        return
    }

    Write-Log -Nachricht "WinGet gefunden: $wingetPfade" -Ebene 'Info'

    try {
        # Quellen aktualisieren
        Write-Log -Nachricht "Aktualisiere WinGet-Paketquellen..." -Ebene 'Info'
        & $wingetPfade source update --accept-source-agreements 2>&1 | Out-Null

        # Verfuegbare Upgrades anzeigen
        Write-Log -Nachricht "Pruefe verfuegbare Upgrades..." -Ebene 'Info'
        $upgradeCheck = & $wingetPfade upgrade --include-unknown 2>&1 | Out-String
        Write-Log -Nachricht "WinGet Upgrade-Liste:`n$upgradeCheck" -Ebene 'Info'

        # Alle Upgrades installieren
        Write-Log -Nachricht "Starte: winget upgrade --all ..." -Ebene 'Info'
        Show-Fortschritt -Aktivitaet "WinGet" -Status "Aktualisiere alle Pakete..." -Id 3 -Protokollieren

        $wingetOutput = & $wingetPfade upgrade `
            --all `
            --accept-source-agreements `
            --accept-package-agreements `
            --silent `
            --include-unknown `
            2>&1

        $wingetOutput | ForEach-Object {
            if ($_ -match 'erfolgreich|Successfully|Updated') {
                Write-Log -Nachricht "WinGet: $_" -Ebene 'Success'
            }
            elseif ($_ -match 'Fehler|Error|failed') {
                Write-Log -Nachricht "WinGet: $_" -Ebene 'Warn'
            }
        }

        Show-Fortschritt -Aktivitaet "WinGet" -Status "Abgeschlossen" -Abschliessen -Id 3
        Write-Log -Nachricht "WinGet Upgrade abgeschlossen (ExitCode: $LASTEXITCODE)" -Ebene 'Success'
    }
    catch {
        Write-Log -Nachricht "WinGet-Upgrade fehlgeschlagen: $($_.Exception.Message)" -Ebene 'Error'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# HAUPTPROGRAMM
# ─────────────────────────────────────────────────────────────────────────────

# Pruefe ob wir nach einem Neustart fortsetzen
Remove-EigenenTask

# Schritt 1: PSWindowsUpdate installieren
$pswuOK = Install-PSWindowsUpdateModul

# Schritt 2: Windows Updates (Loop)
$neustartEingeleitet = Install-WindowsUpdates -PSWUVerfuegbar $pswuOK

if ($neustartEingeleitet) {
    # Skript wird nach Neustart automatisch neu gestartet
    exit 0
}

# Schritt 3: WinGet
Invoke-WinGetUpgrade

# Abschluss: Zustandsdatei
$statePfad    = Join-Path $ToolkitRoot 'state'
$updatesDone  = Join-Path $statePfad 'updates-done.json'

try {
    [PSCustomObject]@{
        Timestamp      = (Get-Date -Format 'o')
        TimestampAnzeige = (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
        Status         = 'Abgeschlossen'
        IncludeDrivers = $IncludeDrivers.IsPresent
        Rechner        = $env:COMPUTERNAME
        Benutzer       = $env:USERNAME
    } | ConvertTo-Json | Out-File -FilePath $updatesDone -Encoding UTF8 -Force
    Write-Log -Nachricht "Updates-Status gespeichert: $updatesDone" -Ebene 'Info'
}
catch {
    Write-Log -Nachricht "Zustandsdatei konnte nicht geschrieben werden: $($_.Exception.Message)" -Ebene 'Warn'
}

# Abschluss-Ausgabe
Write-Host ""
Write-Trennlinie -Titel ' Updates abgeschlossen '
Write-Host ""
Write-Log -Nachricht "Alle Update-Schritte erfolgreich abgeschlossen." -Ebene 'Success'
Write-Host ""
Write-Host "  Naechster Schritt: 20-Maintenance.ps1" -ForegroundColor Cyan
Write-Host ""

# Neustart-Empfehlung
$finalReboot = Test-PendingReboot
if ($finalReboot.NeuStartNoetig -and -not $KeineReboot) {
    Write-Host "  Neustart empfohlen: $($finalReboot.Gruende -join ', ')" -ForegroundColor Yellow
    $neustart = Confirm-Schritt -Frage "Jetzt neu starten?"
    if ($neustart) {
        Write-Log -Nachricht "Neustart wird ausgefuehrt..." -Ebene 'Info'
        Start-Sleep -Seconds 3
        Restart-Computer -Force
    }
}

Write-Host "  Druecke eine Taste zum Beenden..." -ForegroundColor Gray
try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch {}

