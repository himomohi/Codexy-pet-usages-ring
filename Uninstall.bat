@echo off
setlocal
set "ROOT=%~dp0"
cd /d "%TEMP%"
call "%ROOT%bin\cmd\uninstall.cmd" -RemoveFiles %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Uninstall failed with exit code %EXITCODE%.
  pause
) else (
  echo Uninstall completed. The source folder was kept.
  ping 127.0.0.1 -n 4 >nul
)
exit /b %EXITCODE%
