@echo off
REM Build script for civetweb.hdll (HashLink native library)
REM Compiles CivetWeb bridge for HashLink on Windows

setlocal enabledelayedexpansion

echo ========================================
echo Building civetweb.hdll for HashLink
echo ========================================
echo.

REM ==============================
REM 1. Find HashLink installation
REM ==============================
set HASHLINK_PATH=%HASHLINK_PATH%

if "%HASHLINK_PATH%"=="" (
    echo HASHLINK_PATH not set, attempting to locate Lime's HashLink...
    
    REM Try to find Lime's HashLink installation
    set "LIME_HL_PATH=C:\HaxeToolkit\haxe\lib\lime\8,2,2\templates\bin\hl"
    if exist "!LIME_HL_PATH!\Windows64\libhl.lib" (
        set HASHLINK_PATH=!LIME_HL_PATH!
        echo Found Lime's HashLink at: !HASHLINK_PATH!
    ) else (
        REM Fallback: try to find hl.exe in PATH
        for %%i in (hl.exe) do set HL_EXE=%%~$PATH:i
        if "!HL_EXE!"=="" (
            echo ERROR: Cannot find HashLink installation
            echo Please set HASHLINK_PATH environment variable to your HashLink installation directory
            echo Example: set HASHLINK_PATH=C:\HaxeToolkit\haxe\lib\lime\8,2,2\templates\bin\hl
            exit /b 1
        )
        for %%i in ("!HL_EXE!") do set HASHLINK_PATH=%%~dpi
        set HASHLINK_PATH=!HASHLINK_PATH:~0,-1!
        echo Found HashLink at: !HASHLINK_PATH!
    )
) else (
    echo Using HASHLINK_PATH: %HASHLINK_PATH%
)

REM Verify HashLink files exist
if not exist "%HASHLINK_PATH%\include\hl.h" (
    echo ERROR: Cannot find hl.h in %HASHLINK_PATH%\include\
    echo Please verify HASHLINK_PATH is correct
    exit /b 1
)

REM Check for libhl.lib in both possible locations
set "HL_LIB_PATH="
if exist "%HASHLINK_PATH%\libhl.lib" (
    set "HL_LIB_PATH=%HASHLINK_PATH%"
    echo Found libhl.lib in root directory ^(standalone HashLink^)
    goto :hl_lib_found
)
if exist "%HASHLINK_PATH%\Windows64\libhl.lib" (
    set "HL_LIB_PATH=%HASHLINK_PATH%\Windows64"
    echo Found libhl.lib in Windows64 subdirectory ^(Lime's HashLink^)
    goto :hl_lib_found
)

echo ERROR: Cannot find libhl.lib in either:
echo   - %HASHLINK_PATH%\libhl.lib ^(standalone HashLink^)
echo   - %HASHLINK_PATH%\Windows64\libhl.lib ^(Lime's HashLink^)
echo Please verify HASHLINK_PATH is correct
exit /b 1

:hl_lib_found
echo HashLink headers and libraries found OK
echo.

REM ==============================
REM 2. Setup Visual Studio environment
REM ==============================
echo Setting up Visual Studio build environment...

REM Try to find vswhere
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: Cannot find vswhere.exe
    echo Please ensure Visual Studio 2017 or later is installed
    exit /b 1
)

REM Find latest Visual Studio installation
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -property installationPath`) do (
    set VS_PATH=%%i
)

if "%VS_PATH%"=="" (
    echo ERROR: Cannot locate Visual Studio installation
    exit /b 1
)

echo Found Visual Studio at: %VS_PATH%

REM Setup build environment
set "VCVARS=%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCVARS%" (
    echo ERROR: Cannot find vcvars64.bat at %VCVARS%
    exit /b 1
)

REM Call vcvars64.bat to setup environment
call "%VCVARS%" >nul 2>&1
if errorlevel 1 (
    echo ERROR: Failed to setup Visual Studio environment
    exit /b 1
)

echo Build environment configured
echo.

REM ==============================
REM 3. Clean previous build artifacts
REM ==============================
if exist civetweb.obj del /Q civetweb.obj
if exist civetweb_hl.obj del /Q civetweb_hl.obj
if exist civetweb.hdll del /Q civetweb.hdll
if exist civetweb.lib del /Q civetweb.lib
if exist civetweb.exp del /Q civetweb.exp

REM ==============================
REM 4. Compile civetweb.c (CivetWeb library)
REM ==============================
echo [1/3] Compiling civetweb.c...
cl /c /O2 /MD /nologo ^
    /DNO_SSL ^
    /DUSE_WEBSOCKET ^
    ..\civetweb.c ^
    /Fo:civetweb.obj

if errorlevel 1 (
    echo ERROR: Failed to compile civetweb.c
    exit /b 1
)
echo civetweb.obj created successfully
echo.

REM ==============================
REM 5. Compile civetweb_hl.c (HashLink bindings)
REM ==============================
echo [2/3] Compiling civetweb_hl.c...
cl /c /O2 /MD /nologo ^
    /I"%HASHLINK_PATH%\include" ^
    /I.. ^
    /DNO_SSL ^
    /DUSE_WEBSOCKET ^
    civetweb_hl.c ^
    /Fo:civetweb_hl.obj

if errorlevel 1 (
    echo ERROR: Failed to compile civetweb_hl.c
    exit /b 1
)
echo civetweb_hl.obj created successfully
echo.

REM ==============================
REM 6. Link into civetweb.hdll
REM ==============================
echo [3/3] Linking civetweb.hdll...
echo Using library path: %HL_LIB_PATH%

REM Copy libhl.lib to current directory to avoid path issues with commas
copy "%HL_LIB_PATH%\libhl.lib" . >nul
if errorlevel 1 (
    echo ERROR: Failed to copy libhl.lib
    exit /b 1
)

link /DLL /NOLOGO ^
    /OUT:civetweb.hdll ^
    civetweb_hl.obj civetweb.obj ^
    libhl.lib ws2_32.lib

if errorlevel 1 (
    echo ERROR: Failed to link civetweb.hdll
    exit /b 1
)

echo.
echo ========================================
echo Build completed successfully!
echo ========================================
echo Output: civetweb.hdll
echo.
echo Next steps:
echo 1. Copy civetweb.hdll to Export/hl/bin/ (or use copy-hl-hdll.bat)
echo 2. Run: lime build hl
echo 3. Run: lime test hl
echo.
echo The civetweb.hdll will be automatically copied to Export/hl/bin/ when you run 'lime build hl'

endlocal
