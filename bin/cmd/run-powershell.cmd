@echo off
setlocal

if not defined SCRIPT (
  echo Missing SCRIPT environment variable. Use a wrapper in bin\cmd.
  exit /b 64
)

if not exist "%SCRIPT%" (
  echo Missing PowerShell script: "%SCRIPT%"
  exit /b 2
)

set "PS_EXE="
where powershell.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 set "PS_EXE=powershell.exe"

if not defined PS_EXE (
  where pwsh.exe >nul 2>nul
  if %ERRORLEVEL% EQU 0 set "PS_EXE=pwsh.exe"
)

if not defined PS_EXE (
  echo PowerShell was not found. Install PowerShell or run this on Windows 10/11.
  exit /b 127
)

"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%SCRIPT%" %*
exit /b %ERRORLEVEL%
