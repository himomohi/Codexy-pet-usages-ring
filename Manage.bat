@echo off
chcp 949 >nul
setlocal
title Codex Pet 사용량 링 관리
cd /d "%~dp0"

:menu
cls
echo.
echo  =============================================
echo       Codex Pet 5시간 / 주간 사용량 링
echo  =============================================
echo.
echo   1. 설치하고 지금 실행 (자동 시작 안 함 - 권장)
echo   2. 설치하고 지금 실행 + Windows 자동 시작
echo   3. 현재 상태 확인
echo   4. 링 설정 열기
echo   5. 링 일시 중지
echo   6. 진단 실행
echo   7. 설치본 완전 제거 (이 소스 폴더는 유지)
echo   8. 종료
echo.
set /p "CHOICE=번호를 선택하세요: "

if "%CHOICE%"=="1" goto install
if "%CHOICE%"=="2" goto autostart
if "%CHOICE%"=="3" goto status
if "%CHOICE%"=="4" goto settings
if "%CHOICE%"=="5" goto stop
if "%CHOICE%"=="6" goto diagnose
if "%CHOICE%"=="7" goto uninstall
if "%CHOICE%"=="8" goto end

echo.
echo 잘못된 선택입니다.
pause
goto menu

:install
call "%~dp0Install.bat"
goto menu

:autostart
call "%~dp0Install-AutoStart.bat"
goto menu

:status
call "%~dp0Status.bat"
goto menu

:settings
call "%~dp0Settings.bat"
goto menu

:stop
call "%~dp0Stop.bat"
goto menu

:diagnose
call "%~dp0Diagnose.bat"
goto menu

:uninstall
echo.
choice /C YN /N /M "설치본과 설정을 완전히 제거할까요? [Y/N]: "
if errorlevel 2 goto menu
call "%~dp0Uninstall.bat"
goto menu

:end
exit /b 0
