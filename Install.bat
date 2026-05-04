@echo off
setlocal
cd /d "%~dp0"
call "%~dp0bin\cmd\install.cmd" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Install failed with exit code %EXITCODE%.
  pause
) else (
  echo Install completed. You can close this window.
  timeout /t 5 >nul
)
exit /b %EXITCODE%
