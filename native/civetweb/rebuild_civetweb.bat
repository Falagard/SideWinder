@echo off
setlocal

:: hashlink setup
set HL_INCLUDE=C:\Src\ge\SideWinder\.haxelib\lime\8,3,0\templates\bin\hl\include
set HL_LIB=C:\Src\ge\SideWinder\.haxelib\lime\8,3,0\templates\bin\hl\Windows64\libhl.lib

:: Setup VS Environment
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat" call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvars64.bat" call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvars64.bat"


:: output
set OUT=hl\civetweb.hdll

echo Building civetweb.hdll...
cl /O2 /I %HL_INCLUDE% /I . /LD /Fe%OUT% /DNO_SSL /DUSE_WEBSOCKET hl\civetweb_hl.c civetweb.c %HL_LIB% /link /DLL /OUT:%OUT%

if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    exit /b %ERRORLEVEL%
)

echo Build success!
copy /Y %OUT% ..\..\Export\hl\bin\civetweb.hdll
