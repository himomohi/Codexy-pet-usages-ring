@echo off
setlocal
set "ROOT=%~dp0..\.."
set "SCRIPT=%ROOT%\bin\powershell\Uninstall.ps1"
call "%~dp0run-powershell.cmd" %*
exit /b %ERRORLEVEL%
