@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ===============================================================
echo   Docker Bridge Watcher - DeepSeek Harness Installer
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

echo [1/3] Deploying docker_switch into:
echo       !TARGET_DIR!\docker_switch
xcopy /E /I /Y "%~dp0docker_switch" "!TARGET_DIR!\docker_switch" >nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to copy docker_switch.
    pause
    exit /b 1
)

echo [2/3] Enabling MCP configuration (.mcp.json)...
call "!TARGET_DIR!\docker_switch\watcher\mcp_configs\enable_mcp.bat" deepseek "!TARGET_DIR!"

echo [3/3] Updating project instructions in AGENTS.md...
set "AGENTS_MD=!TARGET_DIR!\AGENTS.md"
findstr /i "Docker Bridge Integration" "!AGENTS_MD!" >nul 2>&1
if %ERRORLEVEL% neq 0 (
(
echo.
echo ## Docker Bridge Integration
echo - Do NOT execute `docker` or `docker compose` directly in container sandboxes.
echo - Use `docker-bridge` MCP tools: `docker_compose_execute`, `docker_compose_ps`, etc.
echo - If MCP is unavailable, write commands to `docker_switch/commands/execute.txt`.
echo - Monitor continuous logs in `docker_switch/logs/continuous.log`.
) >> "!AGENTS_MD!"
    echo [OK] Added Docker Bridge instructions to !AGENTS_MD!
) else (
    echo [INFO] Instructions already exist in !AGENTS_MD!
)

echo.
echo ===============================================================
echo   [SUCCESS] DeepSeek Harness configured successfully!
echo ===============================================================
echo   Next steps:
echo   1. Start the watcher on the host:
echo      !TARGET_DIR!\docker_switch\start-watcher.bat
echo   2. Run DeepSeek Harness in your project.
echo ===============================================================
echo.
if "%~1"=="" pause
exit /b 0
