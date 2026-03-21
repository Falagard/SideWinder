@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Building sqlite.hdll for HashLink (Advanced Features)
echo ========================================

:: --- 1. Find HashLink (Targeting SideWinder's local lib) ---
set "LIME_HL_ROOT=%~dp0..\..\.haxelib\lime\8,3,0\templates\bin\hl"
set "HL_INCLUDE=%LIME_HL_ROOT%\include"
set "HL_LIB=%LIME_HL_ROOT%\Windows64\libhl.lib"

if not exist "%HL_LIB%" (
    echo ERROR: Cannot find libhl.lib at %HL_LIB%
    exit /b 1
)

:: --- 2. Setup VS Environment ---
for /f "usebackq tokens=*" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath`) do set VS_PATH=%%i
call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1

:: --- 3. Compile with Advanced Flags ---
set OUT=sqlite.hdll
set FLAGS=/DSQLITE_ENABLE_FTS5 /DSQLITE_ENABLE_RTREE /DSQLITE_ENABLE_GEOPOLY /DSQLITE_ENABLE_JSON1 /DSQLITE_ENABLE_MATH_FUNCTIONS /DSQLITE_ENABLE_DBSTAT_VTAB /DSQLITE_ENABLE_SESSION /DSQLITE_ENABLE_PREUPDATE_HOOK /DSQLITE_USE_ALLOCA /DSQLITE_THREADSAFE=1

echo Compiling with: %FLAGS%
cl /O2 /I "%HL_INCLUDE%" /I . /LD /Fe%OUT% %FLAGS% sqlite.c sqlite3.c "%HL_LIB%" /link /DLL /OUT:%OUT%

if %ERRORLEVEL% EQU 0 (
    echo Build Success: %OUT%
    echo.
    echo Copying to SideWinder prebuilt locations...
    if not exist "..\civetweb\prebuilt\windows" mkdir "..\civetweb\prebuilt\windows"
    copy /Y sqlite.hdll ..\civetweb\prebuilt\windows\sqlite.hdll
) else (
    echo Build Failed!
)
endlocal
