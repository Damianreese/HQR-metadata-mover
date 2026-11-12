@echo off
rem Copy the uninstaller out of the install folder first, so it can delete that folder.
copy /y "%~dp0uninstall.ps1" "%TEMP%\hqr-metadatamover-uninstall.ps1" >nul
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%TEMP%\hqr-metadatamover-uninstall.ps1" -InstallDir "%~dp0."
