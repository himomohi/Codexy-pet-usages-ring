@echo off
rem Expects ROOT and SCRIPT_NAME. Set CODEX_PET_USE_REPO=1 to force repo scripts.
if defined CODEX_PET_USE_REPO exit /b 0
if not defined SCRIPT_NAME exit /b 0
if not defined LOCALAPPDATA exit /b 0

set "INSTALLED_ROOT=%LOCALAPPDATA%\CodexPetLimitRingsWin"
if exist "%INSTALLED_ROOT%\bin\powershell\%SCRIPT_NAME%" set "ROOT=%INSTALLED_ROOT%"
exit /b 0
