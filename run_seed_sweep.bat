@echo off
setlocal

:: === SETUP QUARTUS PATH ===
set QUARTUS_BIN=F:\QuartusStuff\Quartus_Pro\quartus\bin64
set PATH=%QUARTUS_BIN%;%PATH%

:: === CONFIGURATION ===
set PROJECT_NAME=header_parser
set REVISION_NAME=header_parser
set TCL_SCRIPT=sweep_seeds_and_lock.tcl
set SCRIPT_DIR=tcl
set FULL_SCRIPT_PATH=%SCRIPT_DIR%\%TCL_SCRIPT%

:: === TIMESTAMPED LOG FILE ===
for /f %%i in ('powershell -command "Get-Date -Format yyyyMMdd_HHmmss"') do set TIMESTAMP=%%i
set LOG_FILE=seed_sweep_log_%TIMESTAMP%.txt

:: === CHECKS ===
echo.
echo [INFO] Quartus Seed Sweep Starting
echo [INFO] Project:      %PROJECT_NAME%
echo [INFO] Revision:     %REVISION_NAME%
echo [INFO] Tcl Script:   %FULL_SCRIPT_PATH%
echo [INFO] Log File:     %LOG_FILE%
echo.

:: Check if quartus_sh exists
where quartus_sh >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] quartus_sh not found. Check that Quartus is installed and PATH is set.
    pause
    exit /b 1
) else (
    echo [CHECK] Found Quartus tools: quartus_sh is in PATH
)

:: Check if Tcl script exists
if exist %FULL_SCRIPT_PATH% (
    echo [CHECK] Found Tcl script: %FULL_SCRIPT_PATH%
) else (
    echo [ERROR] Tcl script not found: %FULL_SCRIPT_PATH%
    pause
    exit /b 1
)

:: Check if project file exists
if exist %PROJECT_NAME%.qpf (
    echo [CHECK] Found project file: %PROJECT_NAME%.qpf
) else (
    echo [ERROR] Project file not found: %PROJECT_NAME%.qpf
    pause
    exit /b 1
)

:: Check if revision file exists
if exist %REVISION_NAME%.qsf (
    echo [CHECK] Found revision file: %REVISION_NAME%.qsf
) else (
    echo [ERROR] Revision file not found: %REVISION_NAME%.qsf
    pause
    exit /b 1
)

:: === RUN SCRIPT ===
quartus_sh -t %FULL_SCRIPT_PATH% >> %LOG_FILE% 2>&1

:: === FINISH ===
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Seed sweep script failed. Check %LOG_FILE% for full output.
) else (
    echo.
    echo [SUCCESS] Seed sweep completed successfully!
    echo [INFO] Best seed placement and constraints saved in %LOG_FILE% and .qsf
)

endlocal
pause