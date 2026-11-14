@echo off
rem Single line on purpose: "dex uninstall" deletes this file while it runs.
rem !errorlevel! (delayed expansion) is read after PowerShell exits, so the exit code is kept.
setlocal EnableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dex.ps1" %* & exit /b !errorlevel!
