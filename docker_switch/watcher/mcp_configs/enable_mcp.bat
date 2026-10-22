@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

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

:: 2. Check CLI arguments
if "%~1"=="" goto :show_menu

set "TARGET=%~1"
set "CUSTOM_PROJ=%~2"
goto :resolve_paths

:show_menu
set "CUSTOM_PROJ="
echo ===============================================================
echo   Docker Bridge - MCP Configurator
echo ===============================================================
echo Select agent configuration to enable:
echo.
echo   [1] ZCode / Claude Code    (.zcode.json, .claude.json)
echo   [2] OpenCode               (opencode.json, .mcp.json)
echo   [3] DeepSeek Harness       (.mcp.json)
echo   [4] Universal              (.mcp.json for Cursor / Windsurf / VS Code)
echo   [5] Enable for ALL agents
echo   [6] Disable / Clean all MCP configs
echo   [0] Exit
echo ===============================================================
set /p "CHOICE=Enter choice [1-6, 0]: "

if "!CHOICE!"=="1" set "TARGET=zcode"& goto :resolve_paths
if "!CHOICE!"=="2" set "TARGET=opencode"& goto :resolve_paths
if "!CHOICE!"=="3" set "TARGET=deepseek"& goto :resolve_paths
if "!CHOICE!"=="4" set "TARGET=universal"& goto :resolve_paths
if "!CHOICE!"=="5" set "TARGET=all"& goto :resolve_paths
if "!CHOICE!"=="6" goto :do_disable
if "!CHOICE!"=="0" exit /b 0

echo [ERROR] Invalid selection.
pause
exit /b 1

:do_disable
call "%~dp0disable_mcp.bat"
pause
exit /b 0

:resolve_paths
:: 3. Determine target project directory
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
for %%I in ("%PROJECT_ROOT%") do set "PROJECT_NAME=%%~nxI"

:: 4. Determine MCP python script path (relative if in-tree, absolute if external)
set "SCRIPT_ABS=%~dp0docker_bridge_mcp.py"
for %%I in ("%SCRIPT_ABS%") do set "SCRIPT_ABS=%%~fI"
set "SCRIPT_JSON_PATH=%SCRIPT_ABS:\=/%"

if exist "%PROJECT_ROOT%\docker_switch\watcher\docker_bridge_mcp.py" (
    set "SCRIPT_JSON_PATH=docker_switch/watcher/docker_bridge_mcp.py"
)

echo [INFO] Target Project: %PROJECT_ROOT%
echo [INFO] Bridge Script : %SCRIPT_JSON_PATH%
echo [INFO] Enabling MCP for: %TARGET%

if /i "%TARGET%"=="zcode" goto :apply_zcode
if /i "%TARGET%"=="opencode" goto :apply_opencode
if /i "%TARGET%"=="deepseek" goto :apply_deepseek
if /i "%TARGET%"=="universal" goto :apply_universal
if /i "%TARGET%"=="all" goto :apply_all

echo [ERROR] Unknown target: %TARGET%. Use: zcode, opencode, deepseek, universal, or all.
if "%~1"=="" pause
exit /b 1

:write_standard_mcp
set "OUT_FILE=%~1"
(
echo {
echo   "mcpServers": {
echo     "docker-bridge": {
echo       "command": "uv",
echo       "args": [
echo         "run",
echo         "--python",
echo         "3.12",
echo         "%SCRIPT_JSON_PATH%"
echo       ]
echo     }
echo   }
echo }
) > "%OUT_FILE%"
exit /b 0

:write_opencode_json
set "OUT_FILE=%~1"
(
echo {
echo   "$schema": "https://opencode.ai/config.json",
echo   "mcp": {
echo     "docker-bridge": {
echo       "type": "local",
echo       "command": [
echo         "uv",
echo         "run",
echo         "--python",
echo         "3.12",
echo         "%SCRIPT_JSON_PATH%"
echo       ]
echo     }
echo   },
echo   "mcpServers": {
echo     "docker-bridge": {
echo       "command": "uv",
echo       "args": [
echo         "run",
echo         "--python",
echo         "3.12",
echo         "%SCRIPT_JSON_PATH%"
echo       ]
echo     }
echo   }
echo }
) > "%OUT_FILE%"
exit /b 0

:apply_zcode
call :write_standard_mcp "%PROJECT_ROOT%\.zcode.json"
call :write_standard_mcp "%PROJECT_ROOT%\.claude.json"
echo [OK] Created: %PROJECT_ROOT%\.zcode.json
echo [OK] Created: %PROJECT_ROOT%\.claude.json
goto :finish

:apply_opencode
call :write_opencode_json "%PROJECT_ROOT%\opencode.json"
call :write_standard_mcp "%PROJECT_ROOT%\.mcp.json"
echo [OK] Created: %PROJECT_ROOT%\opencode.json
echo [OK] Created: %PROJECT_ROOT%\.mcp.json
goto :finish

:apply_deepseek
call :write_standard_mcp "%PROJECT_ROOT%\.mcp.json"
echo [OK] Created: %PROJECT_ROOT%\.mcp.json
goto :finish

:apply_universal
call :write_standard_mcp "%PROJECT_ROOT%\.mcp.json"
echo [OK] Created: %PROJECT_ROOT%\.mcp.json
goto :finish

:apply_all
call :write_standard_mcp "%PROJECT_ROOT%\.zcode.json"
call :write_standard_mcp "%PROJECT_ROOT%\.claude.json"
call :write_opencode_json "%PROJECT_ROOT%\opencode.json"
call :write_standard_mcp "%PROJECT_ROOT%\.mcp.json"
echo [OK] Created .zcode.json, .claude.json, opencode.json, .mcp.json in %PROJECT_ROOT%
goto :finish

:finish
echo.
echo [SUCCESS] MCP configuration active for %TARGET%.
if "%~1"=="" pause
exit /b 0
