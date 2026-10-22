@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ===============================================================
echo   Docker Bridge Watcher - Universal MCP Installer (.mcp.json)
echo   (Cursor / Windsurf / VS Code / Roo Code)
echo ===============================================================
echo.

set "TARGET_DIR=%~1"
if "!TARGET_DIR!"=="" (
    set /p "TARGET_DIR=Enter path to your project directory: "
)

if "!TARGET_DIR!"=="" (
    echo [ERROR] No project directory specified.
    pause
    exit /b 1
)

for %%I in ("!TARGET_DIR!") do set "TARGET_DIR=%%~fI"

if not exist "!TARGET_DIR!" (
    echo [ERROR] Project directory does not exist: !TARGET_DIR!
    pause
    exit /b 1
)

echo [1/2] Deploying docker_switch into:
echo       !TARGET_DIR!\docker_switch
xcopy /E /I /Y "%~dp0docker_switch" "!TARGET_DIR!\docker_switch" >nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to copy docker_switch.
    pause
    exit /b 1
)

echo [2/2] Enabling universal .mcp.json...
call "!TARGET_DIR!\docker_switch\watcher\mcp_configs\enable_mcp.bat" universal "!TARGET_DIR!"

echo.
echo ===============================================================
echo   [SUCCESS] Universal MCP configured in !TARGET_DIR!\.mcp.json
echo ===============================================================
echo   Next steps:
echo   1. Start the watcher on the host:
echo      !TARGET_DIR!\docker_switch\start-watcher.bat
echo   2. Open the project in Cursor / Windsurf / VS Code.
echo ===============================================================
echo.
if "%~1"=="" pause
exit /b 0
