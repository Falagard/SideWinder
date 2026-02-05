@echo off
REM Copy civetweb.hdll to Export\hl\bin after HL build
setlocal
set SRC=native\civetweb\hl\civetweb.hdll
set DEST=Export\hl\bin\civetweb.hdll

if exist "%SRC%" (
    copy /Y "%SRC%" "%DEST%"
    echo Copied %SRC% to %DEST%
) else (
    echo ERROR: %SRC% not found!
    exit /b 1
)
endlocal
