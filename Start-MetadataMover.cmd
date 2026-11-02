@echo off
title Metadata Mover
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" %*
pause
