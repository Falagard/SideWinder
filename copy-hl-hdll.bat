@echo off
REM Copy civetweb.hdll and sqlite.hdll to Export\hl\bin after HL build
setlocal enabledelayedexpansion

REM Change to the directory where this script is located (project root)
cd /d "%~dp0"

set SRC=native\civetweb\hl\civetweb.hdll
set PREBUILT=native\civetweb\prebuilt\windows\civetweb.hdll
set DEST=Export\hl\bin\civetweb.hdll

REM Ensure destination directory exists
if not exist "Export\hl\bin" mkdir "Export\hl\bin"

REM Copy civetweb.hdll
REM If destination already exists, we're done with civetweb
if not exist "%DEST%" (
	REM Try to copy from build directory first, then prebuilt
	if exist "%SRC%" (
		copy /Y "%SRC%" "%DEST%" >nul 2>&1
	) else if exist "%PREBUILT%" (
		copy /Y "%PREBUILT%" "%DEST%" >nul 2>&1
	) else (
		REM If we get here, neither source exists - but don't fail the build
		REM The file might have been copied by Lime already
		if not exist "%DEST%" (
			echo [copy-hl-hdll.bat] WARNING: civetweb.hdll not found in build or prebuilt directories
			echo [copy-hl-hdll.bat] Please build it by running: native\civetweb\hl\build_hdll.bat
		)
	)
)

REM Copy sqlite.hdll from HashLink installation
set SQLITE_DEST=Export\hl\bin\sqlite.hdll
if not exist "%SQLITE_DEST%" (
	REM Use HASHLINK_PATH environment variable if set, otherwise try default location
	if defined HASHLINK_PATH (
		set SQLITE_SRC=!HASHLINK_PATH!\sqlite.hdll
	) else (
		set SQLITE_SRC=C:\HashLink\sqlite.hdll
	)
	
	if exist "!SQLITE_SRC!" (
		copy /Y "!SQLITE_SRC!" "%SQLITE_DEST%" >nul 2>&1
		echo [copy-hl-hdll.bat] Copied sqlite.hdll from !SQLITE_SRC!
	) else (
		echo [copy-hl-hdll.bat] WARNING: sqlite.hdll not found at !SQLITE_SRC!
		echo [copy-hl-hdll.bat] Set HASHLINK_PATH environment variable to your HashLink installation path
	)
)

REM Exit with success to not break the build
exit /b 0

endlocal
