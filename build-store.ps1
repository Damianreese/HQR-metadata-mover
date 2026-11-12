<#
  Builds the Microsoft Store package (MSIX) for HQR Metadata Mover.
    .\build-store.ps1              -> dist\store\HQR-MetadataMover-<version>.msix, ready to upload in Partner Center
    .\build-store.ps1 -Register    -> installs the unpacked package on this PC to try it (needs Developer Mode)
  The Store signs the package itself, so nothing here needs a certificate.
  Making the .msix needs makeappx.exe: from the Windows SDK, or unpacked from the free
  Microsoft.Windows.SDK.BuildTools NuGet package into tools\ (this script looks in both).
#>
param([switch]$Register)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$store = Join-Path $here 'store'

$ver = '0.0.0'
if ((Get-Content (Join-Path $here 'server.ps1') -Raw) -match "\`$Version = '([\d.]+)'") { $ver = $Matches[1] }
$pkgVer = "$ver.0"   # Store versions have four parts; the last must be 0.

$out = Join-Path $here 'dist\store'
$layout = Join-Path $out 'layout'
if ($Register) { Get-AppxPackage 'HouseofQuintanilla-ReeseL.HQRMetadataMover' | Remove-AppxPackage }
if (Test-Path $layout) { Remove-Item $layout -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $layout 'Assets') | Out-Null

foreach ($f in 'server.ps1', 'index.html', 'README.md', 'LICENSE.txt') { Copy-Item (Join-Path $here $f) $layout }
Copy-Item (Join-Path $store 'Assets\*.png') (Join-Path $layout 'Assets')
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $layout 'AppxManifest.xml'),
  [IO.File]::ReadAllText((Join-Path $store 'AppxManifest.xml')).Replace('{{VERSION}}', $pkgVer), $utf8)

# The launcher .exe, compiled with the C# compiler that ships with Windows.
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$cs = Join-Path $out 'Launcher.cs'
[IO.File]::WriteAllText($cs, [IO.File]::ReadAllText((Join-Path $store 'Launcher.cs')).Replace('{{VERSION}}', $pkgVer), $utf8)
& $csc /nologo /target:winexe /platform:anycpu /optimize "/win32icon:$(Join-Path $here 'installer\app.ico')" `
  /reference:System.Windows.Forms.dll "/out:$(Join-Path $layout 'HQRMetadataMover.exe')" $cs
if ($LASTEXITCODE) { throw 'Compiling the launcher failed.' }
Remove-Item $cs

if ($Register) {
  Add-AppxPackage -Register (Join-Path $layout 'AppxManifest.xml')
  "Installed HQR Metadata Mover $pkgVer from $layout. Find it in the Start menu."
  return
}

$makeappx = @(
  Get-ChildItem (Join-Path $here 'tools') -Recurse -Filter makeappx.exe -ErrorAction SilentlyContinue | Where-Object FullName -match '\\x64\\'
  Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter makeappx.exe -ErrorAction SilentlyContinue | Where-Object FullName -match '\\x64\\'
) | Select-Object -First 1
if (-not $makeappx) { throw "Can't find makeappx.exe. Put the Microsoft.Windows.SDK.BuildTools NuGet package in tools\ or install the Windows SDK." }

$msix = Join-Path $out "HQR-MetadataMover-$pkgVer.msix"
& $makeappx.FullName pack /d $layout /p $msix /o
if ($LASTEXITCODE) { throw 'makeappx failed.' }
"Built $msix ($([math]::Round((Get-Item $msix).Length / 1KB)) KB). Upload it in Partner Center > Packages."
