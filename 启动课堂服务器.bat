@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Atomic Physics Games - Classroom Server
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
echo.
echo Server stopped. Press any key to close.
pause >nul
