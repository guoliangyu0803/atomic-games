@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Atomic Physics Games - Public Tunnel
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tunnel.ps1"
echo.
echo Tunnel stopped. Press any key to close.
pause >nul
