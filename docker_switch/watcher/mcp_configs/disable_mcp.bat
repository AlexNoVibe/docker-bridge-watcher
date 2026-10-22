@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "CUSTOM_PROJ=%~1"

:: 1. Read config.ini from bridge root
set "CONFIG_FILE=%~dp0..\..\config.ini"
set "CFG_PROJECT_DIR=auto"

if exist "%CONFIG_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG_FILE%") do (
        set "KEY=%%A"
        set "VAL=%%B"
        for /f "tokens=* delims= " %%K in ("!KEY!") do set "KEY=%%K"
        for /f "tokens=* delims= " %%V in ("!VAL!") do set "VAL=%%V"
        if /i "!KEY!"=="PROJECT_DIR" set "CFG_PROJECT_DIR=!VAL!"
    )
)

:: 2. Determine target project directory
if not "%CUSTOM_PROJ%"=="" (
    set "PROJECT_ROOT=%CUSTOM_PROJ%"
) else if /i "!CFG_PROJECT_DIR!"=="auto" (
    for %%I in ("%~dp0..\..\..") do set "PROJECT_ROOT=%%~fI"
) else (
    if exist "!CFG_PROJECT_DIR!" (
        for %%I in ("!CFG_PROJECT_DIR!") do set "PROJECT_ROOT=%%~fI"
    ) else (
        for %%I in ("%~dp0..\..\!CFG_PROJECT_DIR!") do set "PROJECT_ROOT=%%~fI"
    )
)

for %%I in ("%PROJECT_ROOT%") do set "PROJECT_ROOT=%%~fI"

echo [INFO] Disabling and removing MCP configurations from: %PROJECT_ROOT%

if exist "%PROJECT_ROOT%\.zcode.json" (
    del /f /q "%PROJECT_ROOT%\.zcode.json"
    echo [OK] Removed: .zcode.json
)

if exist "%PROJECT_ROOT%\.claude.json" (
    del /f /q "%PROJECT_ROOT%\.claude.json"
    echo [OK] Removed: .claude.json
)

if exist "%PROJECT_ROOT%\opencode.json" (
    del /f /q "%PROJECT_ROOT%\opencode.json"
    echo [OK] Removed: opencode.json
)

if exist "%PROJECT_ROOT%\.mcp.json" (
    del /f /q "%PROJECT_ROOT%\.mcp.json"
    echo [OK] Removed: .mcp.json
)

echo [SUCCESS] All MCP configs disabled in %PROJECT_ROOT%.
if "%~1"=="" pause
exit /b 0
