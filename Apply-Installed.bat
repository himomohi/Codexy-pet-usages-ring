@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Sync-Installed.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Installed-copy update failed with exit code %EXITCODE%.
) else (
  echo The current installed copy now matches this source folder.
)
pause
exit /b %EXITCODE%
