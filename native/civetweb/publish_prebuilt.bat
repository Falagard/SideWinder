@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Publishing CivetWeb Prebuilt Library
echo ========================================
echo.

:: Change to the directory where this script is located
cd /d "%~dp0"

set SRC=hl\civetweb.hdll
set DEST=prebuilt\windows\civetweb.hdll

:: Check if source exists
if not exist "%SRC%" (
    echo ERROR: Local build not found at %SRC%
    echo.
    echo Please build the library first by running:
    echo   rebuild_civetweb.bat
    echo.
    exit /b 1
)

:: Ensure destination directory exists
if not exist "prebuilt\windows" mkdir "prebuilt\windows"

:: Show file information
echo Source: %SRC%
for %%A in ("%SRC%") do (
    echo   Size: %%~zA bytes
    echo   Modified: %%~tA
)
echo.
echo Destination: %DEST%
if exist "%DEST%" (
    for %%A in ("%DEST%") do (
        echo   Current Size: %%~zA bytes
        echo   Current Modified: %%~tA
    )
) else (
    echo   (File does not exist yet)
)
echo.

:: Confirm before overwriting
set /p CONFIRM="Update prebuilt library? This will be tracked in git. (y/N): "
if /i not "%CONFIRM%"=="y" (
    echo.
    echo Cancelled.
    exit /b 0
)

:: Copy the file
copy /Y "%SRC%" "%DEST%" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Failed to copy file!
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================
echo Success!
echo ========================================
echo.
echo Updated: %DEST%
for %%A in ("%DEST%") do (
    echo   Size: %%~zA bytes
    echo   Modified: %%~tA
)
echo.
echo NEXT STEPS:
echo 1. Test the prebuilt library: lime build hl
echo 2. Commit the change: git add %DEST%
echo 3. Include in your commit message that civetweb.hdll was updated
echo.

endlocal
