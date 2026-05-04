@echo off
setlocal
cd /d "%~dp0"
call "%~dp0bin\cmd\status.cmd" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" (
  echo Status failed with exit code %EXITCODE%.
)
pause
exit /b %EXITCODE%
