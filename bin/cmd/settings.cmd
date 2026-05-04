@echo off
setlocal
set "ROOT=%~dp0..\.."
set "SCRIPT=%ROOT%\bin\powershell\Settings.ps1"
call "%~dp0run-powershell.cmd" %*
exit /b %ERRORLEVEL%
