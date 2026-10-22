@echo off
set LOG_FILE=%~dp0..\logs\continuous.log
if exist "%LOG_FILE%" (
    type "%LOG_FILE%"
) else (
    echo [INFO] Log file %LOG_FILE% does not exist yet. Ensure watcher is running.
)
