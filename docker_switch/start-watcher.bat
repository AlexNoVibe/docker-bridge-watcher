@echo off
chcp 65001 >nul
cd /d "%~dp0watcher"
call "start-watcher.bat"
