@echo off
setlocal
set "ROOT=%~dp0"
cd /d "%TEMP%"
call "%ROOT%bin\cmd\uninstall.cmd" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Uninstall failed with exit code %EXITCODE%.
  pause
) else (
  echo Uninstall completed. You can close this window.
  timeout /t 5 >nul
)
exit /b %EXITCODE%
