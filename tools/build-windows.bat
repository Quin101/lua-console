@echo off
rem Double-click to rebuild QrawllerTerminal.exe after you add commands or widgets.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1"
pause
