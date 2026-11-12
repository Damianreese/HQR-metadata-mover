@echo off
title HQR Metadata Mover setup
if not exist "%~dp0setup\install.ps1" (
  echo.
  echo   Please extract ^(unzip^) the whole download first,
  echo   then double-click "Install HQR Metadata Mover" in the extracted folder.
  echo.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\install.ps1"
if errorlevel 1 (
  echo.
  echo   Setup did not finish. The message above explains why.
  echo.
  pause
  exit /b 1
)
timeout /t 6 >nul
