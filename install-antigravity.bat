@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

echo ===============================================================
echo   Docker Bridge Watcher - Google Antigravity (AGY) Installer
echo ===============================================================
echo.

set "AGY_CONFIG=%USERPROFILE%\.gemini\config"
set "TEMPLATE_DIR=%AGY_CONFIG%\skills\docker-bridge\template\docker_switch"
set "TOOLS_DIR=%AGY_CONFIG%\tools"
set "SKILL_FILE=%AGY_CONFIG%\skills\docker-bridge\SKILL.md"

echo [1/3] Installing global template into:
echo       %TEMPLATE_DIR%
mkdir "%TEMPLATE_DIR%" 2>nul
xcopy /E /I /Y "%~dp0docker_switch" "%TEMPLATE_DIR%" >nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Failed to copy master template to Antigravity directory.
    pause
    exit /b 1
)

echo [2/3] Installing global MCP server into:
echo       %TOOLS_DIR%\docker_bridge_mcp.py
mkdir "%TOOLS_DIR%" 2>nul
copy /y "%~dp0docker_switch\watcher\docker_bridge_mcp.py" "%TOOLS_DIR%\docker_bridge_mcp.py" >nul

echo [3/3] Registering global skill and MCP server...
if not exist "%AGY_CONFIG%\skills\docker-bridge" mkdir "%AGY_CONFIG%\skills\docker-bridge" 2>nul

:: Register in mcp_config.json if not present
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$cfgPath = Join-Path $env:USERPROFILE '.gemini\config\mcp_config.json';" ^
    "$mcpScript = (Join-Path $env:USERPROFILE '.gemini\config\tools\docker_bridge_mcp.py').Replace('\','/');" ^
    "$cfg = @{ mcpServers = @{} };" ^
    "if (Test-Path $cfgPath) { try { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch {} };" ^
    "if (-not $cfg.mcpServers) { $cfg | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue (New-Object PSObject) -Force };" ^
    "$cfg.mcpServers | Add-Member -NotePropertyName 'docker-bridge' -NotePropertyValue (@{ command = 'uv'; args = @('run', '--python', '3.12', $mcpScript) }) -Force;" ^
    "$cfg | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding UTF8;"

echo.
echo ===============================================================
echo   [SUCCESS] Installed globally for Google Antigravity!
echo ===============================================================
echo   1. The skill is active on: /docker-bridge or "docker bridge"
echo   2. MCP tools (docker_compose_execute, etc.) will auto-detect
echo      docker_switch in your active workspace.
echo ===============================================================
echo.
if "%~1"=="" pause
exit /b 0
