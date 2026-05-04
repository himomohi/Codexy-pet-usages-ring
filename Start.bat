@echo off
setlocal
cd /d "%~dp0"
call "%~dp0bin\cmd\start.cmd" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Start failed with exit code %EXITCODE%.
  pause
) else (
  echo Started. You can close this window.
  timeout /t 3 >nul
)
exit /b %EXITCODE%
