<#
  HQR Metadata Mover installer - House of Quintanilla-Reese LLC - MIT License
  Installs for the current Windows user only (no admin rights needed):
    - program files  -> %LOCALAPPDATA%\Programs\HQR Metadata Mover
    - your packages  -> Documents\HQR Metadata Mover (created on first run, never touched by setup)
    - shortcuts      -> Desktop and Start menu
    - Apps entry     -> Settings > Apps > Installed apps (for uninstalling)
  Running it again upgrades in place.
#>
$ErrorActionPreference = 'Stop'
$AppName = 'HQR Metadata Mover'
$src     = Join-Path (Split-Path $PSScriptRoot -Parent) 'app'
$dest    = Join-Path $env:LOCALAPPDATA "Programs\$AppName"

function Say([string]$msg, [string]$color = 'Gray') { Write-Host "  $msg" -ForegroundColor $color }

$files = 'server.ps1', 'index.html', 'Launch-MetadataMover.cmd', 'Uninstall HQR Metadata Mover.cmd', 'uninstall.ps1', 'app.ico'
foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $src $f))) {
        throw "Can't find '$f'. Please extract (unzip) the whole download first, then run the installer from the extracted folder."
    }
}
$Version = '0.0.0'
if ((Get-Content (Join-Path $src 'server.ps1') -Raw) -match "\`$Version = '([\d.]+)'") { $Version = $Matches[1] }

Write-Host ''
Write-Host "  $AppName $Version setup" -ForegroundColor Cyan
Write-Host '  ------------------------------------' -ForegroundColor DarkGray

# --- Requirement: the Salesforce CLI (setup continues without it; the app explains how to get it) ---
$sf = Get-Command sf.cmd -ErrorAction SilentlyContinue
if (-not $sf) { $sf = @("$env:ProgramFiles\sf\bin\sf.cmd", "$env:LOCALAPPDATA\sf\bin\sf.cmd", "$env:APPDATA\npm\sf.cmd") | Where-Object { Test-Path $_ } | Select-Object -First 1 }
if ($sf) { Say 'Found the Salesforce CLI.' 'Green' }
else { Say 'The Salesforce CLI is not installed yet. Get it from developer.salesforce.com/tools/salesforcecli' 'Yellow' }

# --- Stop an installed copy that's running, so its files can be replaced ---
$pattern = [regex]::Escape($dest) + '\\server\.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match $pattern } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$dest\browser-profile*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 800

# --- Copy program files ---
New-Item -ItemType Directory -Force $dest | Out-Null
foreach ($f in $files + 'README.md', 'LICENSE.txt') {
    $from = if (Test-Path (Join-Path $src $f)) { Join-Path $src $f } else { Join-Path (Split-Path $src -Parent) $f }
    if (Test-Path $from) { Copy-Item $from $dest -Force }
}
# Files from a download are marked as "from the internet"; clear that on our own copies.
Get-ChildItem $dest -File | Unblock-File -ErrorAction SilentlyContinue
Say "Installed to $dest" 'Green'

# --- Shortcuts ---
$ws = New-Object -ComObject WScript.Shell
$icon = Join-Path $dest 'app.ico'
$launcher = Join-Path $dest 'Launch-MetadataMover.cmd'
function New-Shortcut([string]$path) {
    $l = $ws.CreateShortcut($path)
    $l.TargetPath = $launcher; $l.WorkingDirectory = $dest
    $l.WindowStyle = 7; $l.IconLocation = "$icon,0"; $l.Description = 'HQR Metadata Mover - Salesforce metadata deployments'
    $l.Save()
}
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk")
New-Shortcut (Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk")
Say 'Added shortcuts to your Desktop and Start menu.' 'Green'

# --- Apps & features entry (per-user, so uninstall is where people expect it) ---
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HQRMetadataMover'
New-Item -Path $key -Force | Out-Null
$props = @{
    DisplayName = $AppName; DisplayVersion = $Version; Publisher = 'House of Quintanilla-Reese LLC'
    DisplayIcon = $icon; InstallLocation = $dest; URLInfoAbout = 'https://quintanillareese.com'
    UninstallString = "`"$env:SystemRoot\System32\cmd.exe`" /c `"`"$dest\Uninstall HQR Metadata Mover.cmd`"`""
    NoModify = 1; NoRepair = 1
}
foreach ($k in $props.Keys) {
    $type = if ($props[$k] -is [int]) { 'DWord' } else { 'String' }
    New-ItemProperty -Path $key -Name $k -Value $props[$k] -PropertyType $type -Force | Out-Null
}
Say 'Added to Settings > Apps so it can be uninstalled like any other app.' 'Green'

# --- Start it ---
Write-Host ''
Say "Starting $AppName... it opens in its own window." 'Cyan'
Start-Process $launcher -WorkingDirectory $dest -WindowStyle Minimized
Start-Sleep -Seconds 2
Write-Host ''
Say 'All done. You can close this window.' 'Cyan'
Write-Host ''
