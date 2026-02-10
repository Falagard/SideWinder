@echo off
setlocal enabledelayedexpansion

REM Attempt to find vswhere
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" set "VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"

set "VCVARS="

if exist "%VSWHERE%" (
    for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
        set "VS_PATH=%%i"
        if exist "!VS_PATH!\VC\Auxiliary\Build\vcvars64.bat" (
            set "VCVARS=!VS_PATH!\VC\Auxiliary\Build\vcvars64.bat"
        )
    )
)

if "%VCVARS%"=="" (
    REM Fallback to standard paths
    if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
    if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
    if exist "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat" set "VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"
)

if "%VCVARS%"=="" (
    echo Error: Could not find vcvars64.bat. Please run this from a Visual Studio Developer Command Prompt.
    exit /b 1
)

echo Found VS at: %VCVARS%
call "%VCVARS%"

echo Linking SideWinder...
link /out:Export/hlc/bin/SideWinder.exe /subsystem:windows ApplicationMain.obj Export/hlc/bin/fmt.lib Export/hlc/bin/hl.lib Export/hlc/bin/libhl.lib Export/hlc/bin/lime.lib Export/hlc/bin/mysql.lib Export/hlc/bin/ssl.lib Export/hlc/bin/ui.lib Export/hlc/bin/uv.lib native/civetweb/hl/civetweb.lib native\lib\sqlite.lib

if %errorlevel% neq 0 (
    echo Link failed.
    exit /b %errorlevel%
)
echo Link successful!
endlocal
