@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: 1. Read config.ini from docker_switch root
set "CONFIG_FILE=%~dp0..\config.ini"
set "CFG_PROJECT_DIR=auto"
set "CFG_SAFE_MODE=true"

if exist "%CONFIG_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
        set "KEY=%%A"
        set "VAL=%%B"
        for /f "tokens=* delims= " %%K in ("!KEY!") do set "KEY=%%K"
        for /f "tokens=* delims= " %%V in ("!VAL!") do set "VAL=%%V"
        if /i "!KEY!"=="PROJECT_DIR" set "CFG_PROJECT_DIR=!VAL!"
        if /i "!KEY!"=="SAFE_MODE" set "CFG_SAFE_MODE=!VAL!"
    )
)

:: 2. Determine target project directory
if /i "!CFG_PROJECT_DIR!"=="auto" (
    for %%I in ("%~dp0..\..") do set "PROJECT_DIR=%%~fI"
) else (
    if exist "!CFG_PROJECT_DIR!" (
        for %%I in ("!CFG_PROJECT_DIR!") do set "PROJECT_DIR=%%~fI"
    ) else (
        for %%I in ("%~dp0..\!CFG_PROJECT_DIR!") do set "PROJECT_DIR=%%~fI"
    )
)

for %%I in ("%PROJECT_DIR%") do set "PROJECT_NAME=%%~nxI"

set "WIN_TITLE=[ %PROJECT_NAME% ] - Docker Bridge Watcher"
title %WIN_TITLE%

reg add "HKCU\Console\%WIN_TITLE%" /v FaceName /t REG_SZ /d Consolas /f >nul 2>&1
reg add "HKCU\Console\%WIN_TITLE%" /v FontSize /t REG_DWORD /d 0x00100000 /f >nul 2>&1
reg add "HKCU\Console\%WIN_TITLE%" /v FontFamily /t REG_DWORD /d 54 /f >nul 2>&1

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0watcher.ps1"

echo.
echo Watcher process terminated.
pause
