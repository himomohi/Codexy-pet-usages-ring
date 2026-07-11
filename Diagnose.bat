@echo off
setlocal
cd /d "%~dp0"
call "%~dp0bin\cmd\diagnose.cmd" -TestLiveUsage %*
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" echo Diagnose failed with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
