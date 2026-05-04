@echo off
setlocal
cd /d "%~dp0"
call "%~dp0bin\cmd\settings.cmd" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Settings failed with exit code %EXITCODE%.
  pause
)
exit /b %EXITCODE%
