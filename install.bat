@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "ARG1=%~1"
set "ARG2=%~2"

if /i "%ARG1%"=="--agy" goto :do_agy
if /i "%ARG1%"=="--antigravity" goto :do_agy
if /i "%ARG1%"=="zcode" goto :do_zcode
if /i "%ARG1%"=="claude" goto :do_zcode
if /i "%ARG1%"=="opencode" goto :do_opencode
if /i "%ARG1%"=="deepseek" goto :do_deepseek
if /i "%ARG1%"=="universal" goto :do_universal

:: If single path argument provided
if not "%ARG1%"=="" (
    if exist "%ARG1%" (
        echo [INFO] Installing docker_switch into: %ARG1%\docker_switch
        xcopy /E /I /Y "%~dp0docker_switch" "%ARG1%\docker_switch" >nul
        if !ERRORLEVEL! equ 0 (
            echo [OK] docker_switch successfully installed into: %ARG1%\docker_switch
            echo [NEXT STEP] Run "%ARG1%\docker_switch\start-watcher.bat" to start.
        ) else (
            echo [ERROR] Failed to copy docker_switch.
        )
        exit /b 0
    )
)

:menu
cls
echo ===============================================================
echo   Docker Bridge Watcher - Master Multi-Agent Installer
echo ===============================================================
echo Select installation mode:
echo.
echo   [1] Google Antigravity (AGY) - Global Install
echo   [2] ZCode / Claude Code
echo   [3] OpenCode
echo   [4] DeepSeek Harness
echo   [5] Universal (.mcp.json for Cursor / Windsurf / VS Code)
echo   [6] Copy docker_switch only (Manual mode)
echo   [0] Exit
echo ===============================================================
set /p "CHOICE=Enter choice [1-6, 0]: "

if "!CHOICE!"=="1" goto :do_agy
if "!CHOICE!"=="2" goto :do_zcode
if "!CHOICE!"=="3" goto :do_opencode
if "!CHOICE!"=="4" goto :do_deepseek
if "!CHOICE!"=="5" goto :do_universal
if "!CHOICE!"=="6" goto :do_copy_only
if "!CHOICE!"=="0" exit /b 0

echo [ERROR] Invalid selection.
pause
goto :menu

:do_agy
call "%~dp0install-antigravity.bat"
exit /b 0

:do_zcode
call "%~dp0install-zcode.bat" "%ARG2%"
exit /b 0

:do_opencode
call "%~dp0install-opencode.bat" "%ARG2%"
exit /b 0

:do_deepseek
call "%~dp0install-deepseek.bat" "%ARG2%"
exit /b 0

:do_universal
call "%~dp0install-universal.bat" "%ARG2%"
exit /b 0

:do_copy_only
set /p "TARGET_PATH=Enter destination project directory: "
if "!TARGET_PATH!"=="" exit /b 1
for %%I in ("!TARGET_PATH!") do set "TARGET_PATH=%%~fI"
if not exist "!TARGET_PATH!" (
    echo [ERROR] Directory does not exist: !TARGET_PATH!
    pause
    exit /b 1
)
xcopy /E /I /Y "%~dp0docker_switch" "!TARGET_PATH!\docker_switch" >nul
echo [OK] docker_switch installed into !TARGET_PATH!\docker_switch
pause
exit /b 0
