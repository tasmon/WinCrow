@echo off
setlocal EnableExtensions
title WinCrow Installer
color 0C

rem ------------------------------------------------------------------
rem  WinCrow Installer
rem  Installs WinCrow to "C:\Program Files\WinCrow" and adds a Start menu
rem  shortcut. Keep this file in the same folder as WinCrow.ps1.
rem  Developer: Tasmon Islam <tasmon@outlook.com>
rem ------------------------------------------------------------------

set "SCRIPT=%~dp0WinCrow.ps1"

rem ---- ask for administrator rights if we do not have them
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%SCRIPT%" (
    echo.
    echo   WinCrow.ps1 was not found next to this installer.
    echo   Extract the whole download first, then run this file again.
    echo.
    pause
    exit /b 1
)

:menu
cls
echo.
echo   ==============================================
echo     W I N C R O W   -   Installer
echo     Scavenge the bloat. Leave only bones.
echo   ==============================================
echo.
echo   [1]  Install or update WinCrow
echo   [2]  Uninstall WinCrow
echo   [3]  Exit
echo.
choice /c 123 /n /m "  Choose 1, 2 or 3: "
if errorlevel 3 exit /b 0
if errorlevel 2 goto uninstall
if errorlevel 1 goto install
goto menu

:install
echo.
echo   Installing WinCrow...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%SCRIPT%' -ErrorAction SilentlyContinue"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
if %errorlevel% neq 0 (
    echo.
    echo   Something went wrong. Error code %errorlevel%.
    pause
    goto menu
)
echo.
echo   Done. WinCrow is starting and was added to your Start menu.
echo   Next time, just open "WinCrow" from Start.
echo.
timeout /t 4 >nul
exit /b 0

:uninstall
echo.
echo   Removing WinCrow...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Uninstall
echo.
echo   WinCrow was removed. Your Windows settings were not changed.
echo.
pause
exit /b 0
