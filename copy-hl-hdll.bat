@echo off
REM Copy civetweb.hdll to Export\hl\bin after HL build
setlocal

REM Change to the directory where this script is located (project root)
cd /d "%~dp0"

set SRC=native\civetweb\hl\civetweb.hdll
set PREBUILT=native\civetweb\prebuilt\windows\civetweb.hdll
set DEST=Export\hl\bin\civetweb.hdll

REM If destination already exists, we're done
if exist "%DEST%" (
    exit /b 0
)

REM Ensure destination directory exists
if not exist "Export\hl\bin" mkdir "Export\hl\bin"

REM Try to copy from build directory first, then prebuilt
if exist "%SRC%" (
    copy /Y "%SRC%" "%DEST%" >nul 2>&1
    exit /b 0
)

if exist "%PREBUILT%" (
    copy /Y "%PREBUILT%" "%DEST%" >nul 2>&1
    exit /b 0
)

REM If we get here, neither source exists - but don't fail the build
REM The file might have been copied by Lime already
if exist "%DEST%" (
    exit /b 0
)

echo [copy-hl-hdll.bat] WARNING: civetweb.hdll not found in build or prebuilt directories
echo [copy-hl-hdll.bat] Please build it by running: native\civetweb\hl\build_hdll.bat
REM Exit with success anyway to not break the build
exit /b 0

endlocal
