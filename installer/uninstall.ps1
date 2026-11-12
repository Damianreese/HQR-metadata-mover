<#
  HQR Metadata Mover uninstaller - House of Quintanilla-Reese LLC - MIT License
  Runs from a temporary copy so it can remove the install folder it came from.
#>
param([Parameter(Mandatory)][string]$InstallDir)
$ErrorActionPreference = 'SilentlyContinue'
$AppName = 'HQR Metadata Mover'
$InstallDir = (Resolve-Path $InstallDir).Path.TrimEnd('\')
Add-Type -AssemblyName PresentationFramework

$answer = [System.Windows.MessageBox]::Show(
    "Remove HQR Metadata Mover from this PC?`n`nThis stops it and removes the app and its shortcuts. Your packages, backups and templates in Documents\HQR Metadata Mover are kept, and so are your Salesforce CLI org logins.",
    "Uninstall $AppName", 'YesNo', 'Question')
if ($answer -ne 'Yes') { return }

# Stop the local server if it's running.
$pattern = [regex]::Escape($InstallDir) + '\\server\.ps1'
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -match $pattern } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
# ...and its app window, which uses a browser profile inside the install folder.
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$InstallDir\browser-profile*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 1

# Remove shortcuts that point into this install.
$ws = New-Object -ComObject WScript.Shell
foreach ($folder in 'Desktop', 'Programs') {
    $lnk = Join-Path ([Environment]::GetFolderPath($folder)) "$AppName.lnk"
    if ((Test-Path $lnk) -and ($ws.CreateShortcut($lnk).TargetPath -like "$InstallDir\*")) { Remove-Item $lnk -Force }
}

Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HQRMetadataMover' -Recurse -Force

# Remove the program folder (retry briefly in case something is still letting go of files).
for ($i = 0; $i -lt 5 -and (Test-Path $InstallDir); $i++) {
    Remove-Item $InstallDir -Recurse -Force
    if (Test-Path $InstallDir) { Start-Sleep -Seconds 1 }
}

if (Test-Path $InstallDir) {
    [void][System.Windows.MessageBox]::Show("HQR Metadata Mover was removed, but some files are still in use.`nYou can delete this folder after restarting:`n`n$InstallDir", "Uninstall $AppName")
} else {
    [void][System.Windows.MessageBox]::Show('HQR Metadata Mover has been removed. Thanks for trying it!', "Uninstall $AppName")
}
