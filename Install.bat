@echo off
setlocal
cd /d "%~dp0"
call "%~dp0bin\cmd\install.cmd" -Startup %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Install failed with exit code %EXITCODE%.
  pause
) else (
  echo Install completed and the usage rings are running.
  echo Windows auto-start was enabled for reboot-safe pet detection.
  ping 127.0.0.1 -n 4 >nul
)
exit /b %EXITCODE%
