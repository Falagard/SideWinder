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

REM Copy sqlite.hdll from HashLink installation
set SQLITE_DEST=Export\hl\bin\sqlite.hdll
if not exist "%SQLITE_DEST%" (
	set SQLITE_SRC=
	
	REM Try 1: Use HASHLINK_PATH environment variable if set
	if defined HASHLINK_PATH (
		if exist "!HASHLINK_PATH!\sqlite.hdll" (
			set SQLITE_SRC=!HASHLINK_PATH!\sqlite.hdll
		)
	)
	
	REM Try 2: Auto-detect by finding hl.exe in PATH
	if "!SQLITE_SRC!"=="" (
		for %%i in (hl.exe) do (
			set HL_PATH=%%~dp$PATH:i
			if not "!HL_PATH!"=="" (
				REM Remove trailing backslash
				set HL_PATH=!HL_PATH:~0,-1!
				if exist "!HL_PATH!\sqlite.hdll" (
					set SQLITE_SRC=!HL_PATH!\sqlite.hdll
				)
			)
		)
	)
	
	REM Try 3: Check default location
	if "!SQLITE_SRC!"=="" (
		if exist "C:\HashLink\sqlite.hdll" (
			set SQLITE_SRC=C:\HashLink\sqlite.hdll
		)
	)
	
	REM Copy if found
	if not "!SQLITE_SRC!"=="" (
		copy /Y "!SQLITE_SRC!" "%SQLITE_DEST%" >nul 2>&1
		echo [copy-hl-hdll.bat] Copied sqlite.hdll from !SQLITE_SRC!
	) else (
		echo [copy-hl-hdll.bat] WARNING: sqlite.hdll not found
		echo [copy-hl-hdll.bat] Tried: HASHLINK_PATH env var, hl.exe location in PATH, C:\HashLink
		echo [copy-hl-hdll.bat] You can set HASHLINK_PATH environment variable to your HashLink installation path
	)
)

REM Exit with success to not break the build
exit /b 0

endlocal
