@echo off
REM Generate Authelia Secrets Script for Windows
REM Run this script to generate secure secrets for Authelia configuration

setlocal enabledelayedexpansion

echo.
echo 🔐 Authelia Secrets Generator
echo ======================================
echo.

REM Check if openssl is available, otherwise use Docker
set USE_DOCKER=0
where openssl >nul 2>nul
if errorlevel 1 (
    where docker >nul 2>nul
    if errorlevel 1 (
        echo Error: Neither openssl nor docker is installed or in PATH
        echo Please install one of:
        echo   - OpenSSL: https://slproweb.com/products/Win32OpenSSL.html
        echo   - Docker: https://www.docker.com/products/docker-desktop
        exit /b 1
    )
    set USE_DOCKER=1
    echo Note: Using Docker to generate secrets since openssl is not installed
    echo.
)

echo Generating required secrets...
echo.

echo JWT_SECRET ^(for session tokens^):
if %USE_DOCKER%==1 (
    docker run --rm alpine/openssl rand -base64 32
) else (
    openssl rand -base64 32
)
echo.

echo SESSION_SECRET ^(for session encryption^):
if %USE_DOCKER%==1 (
    docker run --rm alpine/openssl rand -base64 32
) else (
    openssl rand -base64 32
)
echo.

echo STORAGE_ENCRYPTION_KEY ^(for database encryption^):
if %USE_DOCKER%==1 (
    docker run --rm alpine/openssl rand -base64 32
) else (
    openssl rand -base64 32
)
echo.

echo ======================================
echo Add these to your .env file
echo ======================================
