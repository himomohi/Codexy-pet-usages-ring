@echo off
setlocal
cd /d "%~dp0"
call "%~dp0bin\cmd\stop.cmd" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Stop failed with exit code %EXITCODE%.
  pause
) else (
  echo Stopped. You can close this window.
  timeout /t 3 >nul
)
exit /b %EXITCODE%
