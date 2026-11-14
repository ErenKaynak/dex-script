@echo off
rem Single line on purpose: "dex uninstall" deletes this file while it runs.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dex.ps1" %* & exit /b
