#Requires -Version 5.0
<#
.SYNOPSIS
    WPF-GUI-Launcher fuer das Windows 11 Optimierungs-Toolkit.
.DESCRIPTION
    Grafische Oberflaeche (WPF/XAML) fuer das Toolkit.
    Zeigt Hardware-Info, Status der einzelnen Module und ermoeglicht
    das Starten der Skripte mit einem Klick.
    Keine externen Abhaengigkeiten.
.NOTES
    Datei   : Start-Launcher.ps1
    Version : 1.0.0
    Autor   : TimInTech (https://github.com/TimInTech)
    Benoetigte Assemblies: PresentationFramework, PresentationCore, WindowsBase
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ─────────────────────────────────────────────────────────────────────────────
# Self-Elevation
# ─────────────────────────────────────────────────────────────────────────────
$identitaet = [Security.Principal.WindowsIdentity]::GetCurrent()
$prinzipal  = [Security.Principal.WindowsPrincipal]$identitaet
$istAdmin   = $prinzipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $istAdmin) {
    try {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" `
            -Verb RunAs
        exit 0
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Starte dieses Skript bitte als Administrator (Rechtsklick -> Als Administrator ausfuehren).",
            "Administrator-Rechte benoetigt",
            'OK', 'Error') | Out-Null
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# WPF-Assemblies laden
# ─────────────────────────────────────────────────────────────────────────────
try {
    Add-Type -AssemblyName PresentationFramework  -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore       -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase            -ErrorAction Stop
    Add-Type -AssemblyName System.Windows.Forms   -ErrorAction Stop
}
catch {
    Write-Host "FEHLER: WPF-Assemblies konnten nicht geladen werden: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Windows Presentation Foundation wird fuer den GUI-Launcher benoetigt." -ForegroundColor Yellow
    pause
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Pfade und Hilfsfunktionen
# ─────────────────────────────────────────────────────────────────────────────
$ToolkitRoot = $PSScriptRoot

function Get-StatusInfo {
    $statePfad = Join-Path $ToolkitRoot 'state'

    return [PSCustomObject]@{
        BootstrapOK   = Test-Path (Join-Path $statePfad 'bootstrap-ok.json')
        UpdatesDone   = Test-Path (Join-Path $statePfad 'updates-done.json')
        MaintenanceDone = Test-Path (Join-Path $statePfad 'maintenance-done.json')
        HardwarePfad  = Join-Path $statePfad 'hardware.json'
    }
}

function Get-HardwareInfo {
    $hardwarePfad = Join-Path $ToolkitRoot 'state\hardware.json'
    if (Test-Path $hardwarePfad) {
        try {
            return (Get-Content $hardwarePfad -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        catch {}
    }
    return $null
}

function Get-LogZeilen {
    param([int]$Anzahl = 20)
    $logOrdner = Join-Path $ToolkitRoot 'logs'
    if (-not (Test-Path $logOrdner)) { return @("(Noch kein Log vorhanden)") }

    $letzteLog = Get-ChildItem -Path $logOrdner -Filter '*.log' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $letzteLog) { return @("(Kein Log gefunden)") }

    try {
        $zeilen = Get-Content -Path $letzteLog.FullName -Encoding UTF8 -ErrorAction Stop
        if ($zeilen.Count -le $Anzahl) { return $zeilen }
        return $zeilen[-$Anzahl..-1]
    }
    catch {
        return @("(Log konnte nicht gelesen werden)")
    }
}

function Start-SkriptAlsAdmin {
    param(
        [string]$Skript,
        [string]$ZusatzArgs = ''
    )
    try {
        $skriptPfad = Join-Path $ToolkitRoot $Skript
        $argListe   = "-NoProfile -ExecutionPolicy Bypass -File `"$skriptPfad`" $ZusatzArgs"

        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList $argListe `
            -Verb RunAs `
            -ErrorAction Stop
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Fehler beim Starten von $Skript`:`n$($_.Exception.Message)",
            "Fehler", 'OK', 'Error') | Out-Null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# XAML-Definition des Hauptfensters
# ─────────────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Windows 11 Optimierungs-Toolkit"
    Width="680" Height="700"
    MinWidth="580" MinHeight="580"
    WindowStartupLocation="CenterScreen"
    Background="#0d1117"
    FontFamily="Segoe UI"
    FontSize="13"
    ResizeMode="CanResizeWithGrip">

    <Window.Resources>
        <!-- Basis-Button-Stil -->
        <Style x:Key="BasisButtonStil" TargetType="Button">
            <Setter Property="Background"   Value="#1f6feb"/>
            <Setter Property="Foreground"   Value="White"/>
            <Setter Property="BorderBrush"  Value="#388bfd"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding"      Value="10,5"/>
            <Setter Property="Cursor"       Value="Hand"/>
            <Setter Property="FontSize"     Value="12"/>
            <Setter Property="FontWeight"   Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Rand"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Rand" Property="Background" Value="#388bfd"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Rand" Property="Background" Value="#0d419d"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Rand" Property="Background" Value="#21262d"/>
                                <Setter Property="Foreground" Value="#8b949e"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="GruenerButton" BasedOn="{StaticResource BasisButtonStil}" TargetType="Button">
            <Setter Property="Background" Value="#196c2e"/>
            <Setter Property="BorderBrush" Value="#2ea043"/>
        </Style>

        <Style x:Key="RoterButton" BasedOn="{StaticResource BasisButtonStil}" TargetType="Button">
            <Setter Property="Background" Value="#6e2020"/>
            <Setter Property="BorderBrush" Value="#f85149"/>
        </Style>

        <!-- Karten-Stil -->
        <Style x:Key="KarteStil" TargetType="Border">
            <Setter Property="Background"     Value="#161b22"/>
            <Setter Property="BorderBrush"    Value="#30363d"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius"   Value="8"/>
            <Setter Property="Padding"        Value="12"/>
            <Setter Property="Margin"         Value="0,4"/>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>   <!-- Header -->
            <RowDefinition Height="Auto"/>   <!-- Hardware-Info -->
            <RowDefinition Height="*"/>      <!-- Module -->
            <RowDefinition Height="Auto"/>   <!-- Alle starten -->
            <RowDefinition Height="Auto"/>   <!-- Log-Header -->
            <RowDefinition Height="150"/>    <!-- Log-Viewer -->
        </Grid.RowDefinitions>

        <!-- ═══ HEADER ═══ -->
        <Border Grid.Row="0" Style="{StaticResource KarteStil}" Margin="0,0,0,8">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel>
                    <TextBlock Text="🛠  Windows 11 Optimierungs-Toolkit"
                               FontSize="18" FontWeight="Bold"
                               Foreground="#58a6ff"/>
                    <TextBlock Name="txtVersion" Text="Version 1.0.0  |  Toolkit-Pfad wird geladen..."
                               Foreground="#8b949e" FontSize="11" Margin="0,2,0,0"/>
                </StackPanel>

                <Border Grid.Column="1" Background="#196c2e" CornerRadius="12"
                        Padding="8,4" VerticalAlignment="Center">
                    <TextBlock Name="txtAdminStatus" Text="Admin ✓"
                               Foreground="#3fb950" FontWeight="Bold" FontSize="12"/>
                </Border>
            </Grid>
        </Border>

        <!-- ═══ HARDWARE-INFO ═══ -->
        <Border Grid.Row="1" Style="{StaticResource KarteStil}" Margin="0,0,0,8">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Name="txtPC"  Text="PC:  Lade Hardware-Informationen..."
                               Foreground="#c9d1d9" FontSize="12"/>
                    <TextBlock Name="txtRAM" Text="RAM: —"
                               Foreground="#c9d1d9" FontSize="12" Margin="0,3,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1">
                    <TextBlock Name="txtGPU" Text="GPU: —"
                               Foreground="#c9d1d9" FontSize="12"/>
                    <TextBlock Name="txtOS"  Text="OS:  —"
                               Foreground="#c9d1d9" FontSize="12" Margin="0,3,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- ═══ MODULE ═══ -->
        <StackPanel Grid.Row="2">

            <!-- 00 Bootstrap -->
            <Border Style="{StaticResource KarteStil}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="30"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Name="ico00" Text="○" FontSize="18"
                               Foreground="#8b949e" VerticalAlignment="Center"/>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="8,0">
                        <TextBlock Text="00  Bootstrap &amp; Systemcheck"
                                   Foreground="#c9d1d9" FontWeight="SemiBold"/>
                        <TextBlock Name="status00" Text="Noch nicht ausgefuehrt"
                                   Foreground="#8b949e" FontSize="11"/>
                    </StackPanel>
                    <Button Grid.Column="2" Name="btn00" Content="▶  Starten"
                            Style="{StaticResource BasisButtonStil}"
                            Width="100" Height="30"/>
                </Grid>
            </Border>

            <!-- 10 Updates -->
            <Border Style="{StaticResource KarteStil}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="30"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Name="ico10" Text="○" FontSize="18"
                               Foreground="#8b949e" VerticalAlignment="Center"/>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="8,0">
                        <TextBlock Text="10  Updates &amp; Treiber"
                                   Foreground="#c9d1d9" FontWeight="SemiBold"/>
                        <TextBlock Name="status10" Text="Noch nicht ausgefuehrt"
                                   Foreground="#8b949e" FontSize="11"/>
                    </StackPanel>
                    <StackPanel Grid.Column="2" Orientation="Horizontal">
                        <Button Name="btn10Treiber" Content="+ Treiber"
                                Style="{StaticResource BasisButtonStil}"
                                Width="80" Height="30" Margin="0,0,6,0"
                                Background="#21262d" BorderBrush="#30363d"/>
                        <Button Name="btn10" Content="▶  Starten"
                                Style="{StaticResource BasisButtonStil}"
                                Width="100" Height="30"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- 20 Maintenance -->
            <Border Style="{StaticResource KarteStil}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="30"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Name="ico20" Text="○" FontSize="18"
                               Foreground="#8b949e" VerticalAlignment="Center"/>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="8,0">
                        <TextBlock Text="20  Bereinigung &amp; Datenschutz"
                                   Foreground="#c9d1d9" FontWeight="SemiBold"/>
                        <TextBlock Name="status20" Text="Noch nicht ausgefuehrt"
                                   Foreground="#8b949e" FontSize="11"/>
                    </StackPanel>
                    <StackPanel Grid.Column="2" Orientation="Horizontal">
                        <Button Name="btn20Bericht" Content="Nur Bericht"
                                Style="{StaticResource BasisButtonStil}"
                                Width="90" Height="30" Margin="0,0,6,0"
                                Background="#21262d" BorderBrush="#30363d"/>
                        <Button Name="btn20" Content="▶  Starten"
                                Style="{StaticResource BasisButtonStil}"
                                Width="100" Height="30"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- 30 Repair -->
            <Border Style="{StaticResource KarteStil}">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="30"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Name="ico30" Text="○" FontSize="18"
                               Foreground="#8b949e" VerticalAlignment="Center"/>
                    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="8,0">
                        <TextBlock Text="30  Reparatur &amp; Diagnose"
                                   Foreground="#c9d1d9" FontWeight="SemiBold"/>
                        <TextBlock Name="status30" Text="Interaktives Menue"
                                   Foreground="#8b949e" FontSize="11"/>
                    </StackPanel>
                    <Button Grid.Column="2" Name="btn30" Content="▶  Starten"
                            Style="{StaticResource BasisButtonStil}"
                            Width="100" Height="30"/>
                </Grid>
            </Border>

        </StackPanel>

        <!-- ═══ ALLE STARTEN / AKTUALISIEREN ═══ -->
        <Grid Grid.Row="3" Margin="0,8,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Button Name="btnAlleStarten" Grid.Column="0"
                    Content="⚡  Alle Module ausfuehren (00 → 10 → 20)"
                    Style="{StaticResource GruenerButton}"
                    Height="36" Margin="0,0,8,0"/>

            <Button Name="btnAktualisieren" Grid.Column="1"
                    Content="↻  Status"
                    Style="{StaticResource BasisButtonStil}"
                    Width="80" Height="36" Margin="0,0,8,0"
                    Background="#21262d" BorderBrush="#388bfd"/>

            <Button Name="btnOrdnerOeffnen" Grid.Column="2"
                    Content="📁  Ordner"
                    Style="{StaticResource BasisButtonStil}"
                    Width="80" Height="36"
                    Background="#21262d" BorderBrush="#30363d"/>
        </Grid>

        <!-- ═══ LOG-HEADER ═══ -->
        <Grid Grid.Row="4" Margin="0,10,0,4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock Text="──  Log (letzte 20 Eintraege)  " Foreground="#8b949e" FontSize="12"
                       VerticalAlignment="Center"/>
            <Button Name="btnLogLeeren" Grid.Column="1"
                    Content="Leeren" Foreground="#8b949e"
                    Background="Transparent" BorderBrush="Transparent"
                    FontSize="11" Cursor="Hand" Padding="4,0"/>
        </Grid>

        <!-- ═══ LOG-VIEWER ═══ -->
        <Border Grid.Row="5"
                Background="#0d1117"
                BorderBrush="#30363d"
                BorderThickness="1"
                CornerRadius="6">
            <ScrollViewer Name="logScrollViewer"
                          VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Auto">
                <TextBlock Name="txtLog"
                           FontFamily="Consolas, Courier New"
                           FontSize="11"
                           Foreground="#7ee787"
                           Background="Transparent"
                           Padding="8"
                           TextWrapping="NoWrap"/>
            </ScrollViewer>
        </Border>

    </Grid>
</Window>
'@

# ─────────────────────────────────────────────────────────────────────────────
# Fenster erstellen und Elemente binden
# ─────────────────────────────────────────────────────────────────────────────
try {
    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $fenster = [Windows.Markup.XamlReader]::Load($reader)
}
catch {
    [System.Windows.MessageBox]::Show(
        "XAML konnte nicht geladen werden:`n$($_.Exception.Message)",
        "XAML-Fehler", 'OK', 'Error') | Out-Null
    exit 1
}

# UI-Elemente referenzieren
$txtVersion       = $fenster.FindName('txtVersion')
$txtAdminStatus   = $fenster.FindName('txtAdminStatus')
$txtPC            = $fenster.FindName('txtPC')
$txtRAM           = $fenster.FindName('txtRAM')
$txtGPU           = $fenster.FindName('txtGPU')
$txtOS            = $fenster.FindName('txtOS')

# Status-Icons und Texte
$ico00   = $fenster.FindName('ico00')
$ico10   = $fenster.FindName('ico10')
$ico20   = $fenster.FindName('ico20')
$ico30   = $fenster.FindName('ico30')

$status00 = $fenster.FindName('status00')
$status10 = $fenster.FindName('status10')
$status20 = $fenster.FindName('status20')
$status30 = $fenster.FindName('status30')

# Buttons
$btn00         = $fenster.FindName('btn00')
$btn10         = $fenster.FindName('btn10')
$btn10Treiber  = $fenster.FindName('btn10Treiber')
$btn20         = $fenster.FindName('btn20')
$btn20Bericht  = $fenster.FindName('btn20Bericht')
$btn30         = $fenster.FindName('btn30')
$btnAlleStarten    = $fenster.FindName('btnAlleStarten')
$btnAktualisieren  = $fenster.FindName('btnAktualisieren')
$btnOrdnerOeffnen  = $fenster.FindName('btnOrdnerOeffnen')
$btnLogLeeren      = $fenster.FindName('btnLogLeeren')

$txtLog           = $fenster.FindName('txtLog')
$logScrollViewer  = $fenster.FindName('logScrollViewer')

# ─────────────────────────────────────────────────────────────────────────────
# UI-Aktualisierungsfunktionen
# ─────────────────────────────────────────────────────────────────────────────
function Update-UI {
    # Version / Pfad
    $txtVersion.Text = "v1.0.0  |  $ToolkitRoot"

    # Admin-Status
    if ($istAdmin) {
        $txtAdminStatus.Text = "Admin ✓"
        $txtAdminStatus.Foreground = '#3fb950'
    }
    else {
        $txtAdminStatus.Text = "Kein Admin ✗"
        $txtAdminStatus.Foreground = '#f85149'
    }

    # Hardware-Info
    $hw = Get-HardwareInfo
    if ($hw) {
        $txtPC.Text  = "PC:  $($hw.OEM) $($hw.Model)"
        $txtRAM.Text = "RAM: $($hw.RAM_GB) GB"
        $txtGPU.Text = "GPU: $($hw.GPU_Model) ($($hw.GPU_Vendor))"
        $txtOS.Text  = "OS:  Windows 11 Build $($hw.OS_Build) ($($hw.OS_Edition))"
    }
    else {
        $txtPC.Text  = "PC:  (Bootstrap noch nicht ausgefuehrt)"
        $txtRAM.Text = "RAM: —"
        $txtGPU.Text = "GPU: —"
        $txtOS.Text  = "OS:  —"
    }

    # Modul-Status
    $statusInfo = Get-StatusInfo

    if ($statusInfo.BootstrapOK) {
        $ico00.Text = "●"
        $ico00.Foreground = '#3fb950'
        try {
            $bs = Get-Content (Join-Path $ToolkitRoot 'state\bootstrap-ok.json') -Raw | ConvertFrom-Json
            $status00.Text = "✓ Abgeschlossen am $($bs.TimestampAnzeige)"
        }
        catch { $status00.Text = "✓ Abgeschlossen" }
    }
    else {
        $ico00.Text = "○"
        $ico00.Foreground = '#8b949e'
        $status00.Text = "Noch nicht ausgefuehrt"
    }

    if ($statusInfo.UpdatesDone) {
        $ico10.Text = "●"
        $ico10.Foreground = '#3fb950'
        try {
            $upd = Get-Content (Join-Path $ToolkitRoot 'state\updates-done.json') -Raw | ConvertFrom-Json
            $status10.Text = "✓ Abgeschlossen am $($upd.TimestampAnzeige)"
        }
        catch { $status10.Text = "✓ Abgeschlossen" }
    }
    else {
        $ico10.Text = "○"
        $ico10.Foreground = '#8b949e'
        $status10.Text = "Noch nicht ausgefuehrt"
    }

    if ($statusInfo.MaintenanceDone) {
        $ico20.Text = "●"
        $ico20.Foreground = '#3fb950'
        try {
            $mnt = Get-Content (Join-Path $ToolkitRoot 'state\maintenance-done.json') -Raw | ConvertFrom-Json
            $timestamp = if ($mnt.Timestamp) { ([datetime]$mnt.Timestamp).ToString('dd.MM.yyyy HH:mm') } else { '—' }
            $status20.Text = "✓ Abgeschlossen am $timestamp"
        }
        catch { $status20.Text = "✓ Abgeschlossen" }
    }
    else {
        $ico20.Text = "○"
        $ico20.Foreground = '#8b949e'
        $status20.Text = "Noch nicht ausgefuehrt"
    }

    # 30-Repair hat keinen Status (immer verfuegbar)
    $ico30.Text = "◎"
    $ico30.Foreground = '#79c0ff'
    $status30.Text = "Interaktives Menue (immer verfuegbar)"

    # Log aktualisieren
    Update-Log
}

function Update-Log {
    try {
        $zeilen = Get-LogZeilen -Anzahl 20
        $txtLog.Text = $zeilen -join "`n"

        # Automatisch ans Ende scrollen
        $fenster.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [System.Action]{ $logScrollViewer.ScrollToEnd() }
        ) | Out-Null
    }
    catch {}
}

# ─────────────────────────────────────────────────────────────────────────────
# Event-Handler
# ─────────────────────────────────────────────────────────────────────────────

# 00 Bootstrap
$btn00.Add_Click({
    Start-SkriptAlsAdmin -Skript '00-Bootstrap.ps1'
    Start-Sleep -Seconds 1
    Update-UI
})

# 10 Updates
$btn10.Add_Click({
    Start-SkriptAlsAdmin -Skript '10-Updates.ps1'
    Start-Sleep -Seconds 1
    Update-UI
})

$btn10Treiber.Add_Click({
    Start-SkriptAlsAdmin -Skript '10-Updates.ps1' -ZusatzArgs '-IncludeDrivers'
    Start-Sleep -Seconds 1
    Update-UI
})

# 20 Maintenance
$btn20.Add_Click({
    Start-SkriptAlsAdmin -Skript '20-Maintenance.ps1'
    Start-Sleep -Seconds 1
    Update-UI
})

$btn20Bericht.Add_Click({
    Start-SkriptAlsAdmin -Skript '20-Maintenance.ps1' -ZusatzArgs '-NurBericht'
    Start-Sleep -Seconds 1
    Update-UI
})

# 30 Repair
$btn30.Add_Click({
    Start-SkriptAlsAdmin -Skript '30-Repair.ps1'
})

# Alle Starten (00 -> 10 -> 20 sequenziell)
$btnAlleStarten.Add_Click({
    $antwort = [System.Windows.MessageBox]::Show(
        "Alle Module werden nacheinander ausgefuehrt:`n`n" +
        "  00 - Bootstrap & Systemcheck`n" +
        "  10 - Updates & Treiber`n" +
        "  20 - Bereinigung & Datenschutz`n`n" +
        "Hinweis: Jedes Modul oeffnet ein eigenes PowerShell-Fenster.`n" +
        "Warten Sie bis jedes Modul abgeschlossen ist, bevor das naechste startet.`n`n" +
        "Jetzt starten?",
        "Alle Module starten",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )

    if ($antwort -eq 'Yes') {
        # PowerShell-Skript das alle Module sequenziell startet
        $sequenzSkript = @"
# Alle Toolkit-Module sequenziell ausfuehren
Set-ExecutionPolicy Bypass -Scope Process -Force
`$root = '$ToolkitRoot'

Write-Host "=== 00-Bootstrap ===" -ForegroundColor Cyan
& "`$root\00-Bootstrap.ps1" -Stumm
Write-Host "=== Bootstrap abgeschlossen. Naechstes Modul in 3 Sek... ===" -ForegroundColor Green
Start-Sleep 3

Write-Host "=== 10-Updates ===" -ForegroundColor Cyan
& "`$root\10-Updates.ps1" -KeineReboot
Write-Host "=== Updates abgeschlossen. Naechstes Modul in 3 Sek... ===" -ForegroundColor Green
Start-Sleep 3

Write-Host "=== 20-Maintenance ===" -ForegroundColor Cyan
& "`$root\20-Maintenance.ps1" -AllesOhneAbfrage
Write-Host "=== Maintenance abgeschlossen ===" -ForegroundColor Green

Write-Host ""
Write-Host "ALLE MODULE ABGESCHLOSSEN. Neustart empfohlen." -ForegroundColor Yellow
pause
"@
        $tmpSkript = [System.IO.Path]::GetTempFileName() + '.ps1'
        $sequenzSkript | Out-File -FilePath $tmpSkript -Encoding UTF8 -Force

        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmpSkript`"" `
            -Verb RunAs
    }
})

# Status aktualisieren
$btnAktualisieren.Add_Click({
    Update-UI
})

# Ordner oeffnen
$btnOrdnerOeffnen.Add_Click({
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$ToolkitRoot`""
    }
    catch {}
})

# Log leeren (nur Anzeige)
$btnLogLeeren.Add_Click({
    $txtLog.Text = "(Log geleert - Datei bleibt erhalten)"
})

# Tastenkuerzel
$fenster.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'F5') { Update-UI }
})

# ─────────────────────────────────────────────────────────────────────────────
# Fenster anzeigen
# ─────────────────────────────────────────────────────────────────────────────

# Initial-Aktualisierung nach dem Laden
$fenster.Add_Loaded({
    Update-UI

    # Warnhinweis wenn Bootstrap noch nicht ausgefuehrt
    $statusInfo = Get-StatusInfo
    if (-not $statusInfo.BootstrapOK) {
        $txtLog.Text = "[$(Get-Date -Format 'HH:mm:ss')] Willkommen! Bitte zuerst '00-Bootstrap.ps1' ausfuehren,`n" +
                       "um das System vorzubereiten und Hardware zu erkennen.`n" +
                       "Klicken Sie dazu auf den [Starten]-Button bei Modul 00."
    }
})

# Fenster anzeigen (blockierend)
try {
    $app = [System.Windows.Application]::new()
    $app.Run($fenster) | Out-Null
}
catch {
    # Fallback: ShowDialog
    try {
        $fenster.ShowDialog() | Out-Null
    }
    catch {
        Write-Host "GUI konnte nicht angezeigt werden: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Bitte Skripte direkt ausfuehren:" -ForegroundColor Yellow
        Write-Host "  .\00-Bootstrap.ps1" -ForegroundColor Cyan
        Write-Host "  .\10-Updates.ps1" -ForegroundColor Cyan
        Write-Host "  .\20-Maintenance.ps1" -ForegroundColor Cyan
        pause
    }
}
