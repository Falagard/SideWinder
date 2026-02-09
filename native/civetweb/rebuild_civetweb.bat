@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Building civetweb.hdll for HashLink
echo ========================================

:: --- 1. Find HashLink installation (Targeting Lime 8.3.0) ---
set "LIME_HL_ROOT=C:\Src\ge\SideWinder\.haxelib\lime\8,3,0\templates\bin\hl"
set "HL_INCLUDE=%LIME_HL_ROOT%\include"
set "HL_LIB=%LIME_HL_ROOT%\Windows64\libhl.lib"

if exist "%HL_LIB%" (
    echo Found Lime 8.3.0 HashLink at: %LIME_HL_ROOT%
) else (
    echo WARNING: Lime 8.3.0 HashLink not found at %LIME_HL_ROOT%
    echo Attempting to locate HashLink via HASHLINK_PATH or PATH...
    
    if "%HASHLINK_PATH%"=="" (
        for %%i in (hl.exe) do set HL_EXE=%%~$PATH:i
        if "!HL_EXE!"=="" (
            echo ERROR: Cannot find HashLink installation.
            echo Please set HASHLINK_PATH environment variable.
            exit /b 1
        )
        for %%i in ("!HL_EXE!") do set HASHLINK_PATH=%%~dpi
        set HASHLINK_PATH=!HASHLINK_PATH:~0,-1!
    )
    
    set "HL_INCLUDE=!HASHLINK_PATH!\include"
    if exist "!HASHLINK_PATH!\libhl.lib" (
        set "HL_LIB=!HASHLINK_PATH!\libhl.lib"
    ) else if exist "!HASHLINK_PATH!\Windows64\libhl.lib" (
        set "HL_LIB=!HASHLINK_PATH!\Windows64\libhl.lib"
    ) else (
        echo ERROR: Cannot find libhl.lib in !HASHLINK_PATH!
        exit /b 1
    )
)

:: --- 2. Setup Visual Studio Environment ---
echo Setting up Visual Studio build environment...
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: Cannot find vswhere.exe. Please ensure Visual Studio is installed.
    exit /b 1
)

for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -property installationPath`) do set VS_PATH=%%i
if "%VS_PATH%"=="" (
    echo ERROR: Cannot locate Visual Studio installation.
    exit /b 1
)

set "VCVARS=%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" (
    echo ERROR: Cannot find vcvars64.bat at %VCVARS%
    exit /b 1
)

call "%VCVARS%" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Failed to setup Visual Studio environment.
    exit /b 1
)

:: --- 3. Compile and Link ---
set OUT_DIR=hl
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
set OUT=%OUT_DIR%\civetweb.hdll

echo Compiling and Linking %OUT%...
cl /O2 /I "%HL_INCLUDE%" /I . /LD /Fe%OUT% /DNO_SSL /DUSE_WEBSOCKET hl\civetweb_hl.c civetweb.c "%HL_LIB%" /link /DLL /OUT:%OUT%

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Build failed!
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================
echo Build success!
echo ========================================
echo.
echo Output: %OUT%
echo.
echo This is a LOCAL development build (git-ignored).
echo To update the prebuilt version for source control, run:
echo   publish_prebuilt.bat
echo.
echo The copy-hl-hdll.bat script will automatically use this
echo build when running "lime build hl".
endlocal
