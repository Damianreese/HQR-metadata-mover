<#
  Builds the download: dist\HQR-MetadataMover-<version>.zip, laid out like the other HQR apps:
    Install HQR Metadata Mover.cmd, README.md, LICENSE.txt, app\..., setup\install.ps1
  The version comes from $Version in server.ps1. Prints the zip's SHA-256 for the download page.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
if ((Get-Content (Join-Path $here 'server.ps1') -Raw) -notmatch "\`$Version = '([\d.]+)'") { throw 'No $Version in server.ps1' }
$ver = $Matches[1]
$name = "HQR-MetadataMover-$ver"
$dist = Join-Path $here 'dist'
$stage = Join-Path $dist $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
$null = New-Item -ItemType Directory -Force (Join-Path $stage 'app'), (Join-Path $stage 'setup')

$inst = Join-Path $here 'installer'
Copy-Item (Join-Path $here 'server.ps1'), (Join-Path $here 'index.html') (Join-Path $stage 'app')
Copy-Item (Join-Path $inst 'Launch-MetadataMover.cmd'), (Join-Path $inst 'Uninstall HQR Metadata Mover.cmd'), (Join-Path $inst 'uninstall.ps1'), (Join-Path $inst 'app.ico') (Join-Path $stage 'app')
Copy-Item (Join-Path $inst 'install.ps1') (Join-Path $stage 'setup')
Copy-Item (Join-Path $inst 'Install HQR Metadata Mover.cmd'), (Join-Path $here 'README.md'), (Join-Path $here 'LICENSE.txt') $stage

$zip = Join-Path $dist "$name.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path $stage -DestinationPath $zip
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
Write-Host "Built $zip ($([math]::Round((Get-Item $zip).Length / 1KB)) KB)" -ForegroundColor Green
Write-Host "SHA-256: $hash"
