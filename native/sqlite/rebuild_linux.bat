@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Building sqlite.hdll for Linux (via Docker)
echo ========================================

:: --- Settings ---
set "HL_INCLUDE_DIR=%~dp0..\..\.haxelib\lime\8,3,0\templates\bin\hl\include"
set "HL_LIB_DIR=%~dp0..\..\.haxelib\lime\8,3,0\templates\bin\hl\Linux64"
set "SRC_DIR=%~dp0"

:: --- 1. Check Source Files ---
if not exist "sqlite3.c" (
    echo ERROR: sqlite3.c missing. Run rebuild_sqlite.bat first to download it.
    exit /b 1
)

:: --- 2. Run Docker Container ---
:: Mount project root as /workspace
:: Mount HL include as /hl/include
:: Mount HL linux libs as /hl/lib
echo Starting build in ubuntu:latest container...
docker run --rm ^
    -v "%~dp0..\..:/workspace" ^
    -v "%HL_INCLUDE_DIR%:/hl/include" ^
    -v "%HL_LIB_DIR%:/hl/lib" ^
    -w /workspace/native/sqlite ^
    ubuntu:latest ^
    bash -c "apt-get update && apt-get install -y gcc libc6-dev && chmod +x rebuild_sqlite.sh && ./rebuild_sqlite.sh"


if %ERRORLEVEL% EQU 0 (
    echo.
    echo Linux Build Success!
) else (
    echo.
    echo Linux Build Failed!
)
endlocal
