@echo off
setlocal
cd /d "%~dp0\.."

echo ========================================
echo Building civetweb.hdll for Linux via Docker
echo ========================================

REM Create output directory if it doesn't exist
if not exist "prebuilt\linux" mkdir "prebuilt\linux"

REM Build the Docker image
echo.
echo [1/3] Building Docker image...
docker build -f hl/Dockerfile -t civetweb-linux-builder .
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Docker build failed. Make sure Docker Desktop is running.
    exit /b 1
)

REM Create a container instance (don't need to run it, just create to copy files)
echo.
echo [2/3] Creating temporary container...
docker create --name temp-civetweb-builder civetweb-linux-builder
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to create container.
    exit /b 1
)

REM Copy the artifact
echo.
echo [3/3] Copying civetweb.hdll to prebuilt/linux/...
docker cp temp-civetweb-builder:/app/hl/civetweb.hdll prebuilt/linux/civetweb.hdll
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to copy civetweb.hdll.
    docker rm temp-civetweb-builder >nul
    exit /b 1
)

REM Cleanup
echo.
echo Cleaning up...
docker rm temp-civetweb-builder >nul

echo.
echo ========================================
echo Success! 
echo Linux artifact located at: native\civetweb\prebuilt\linux\civetweb.hdll
echo ========================================
pause
