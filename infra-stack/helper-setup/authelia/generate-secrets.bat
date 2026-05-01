@echo off
REM Generate Authelia Secrets Script for Windows
REM Run this script to generate secure secrets for Authelia configuration

setlocal enabledelayedexpansion

echo.
echo 🔐 Authelia Secrets Generator
echo ======================================
echo.

REM Check if openssl is available
where openssl >nul 2>nul
if errorlevel 1 (
    echo Error: openssl is not installed or not in PATH
    echo Please install OpenSSL or use: docker run --rm alpine/openssl rand -base64 32
    exit /b 1
)

echo Generating required secrets...
echo.

echo JWT_SECRET (for session tokens^):
openssl rand -base64 32
echo.

echo SESSION_SECRET (for session encryption^):
openssl rand -base64 32
echo.

echo STORAGE_ENCRYPTION_KEY (for database encryption^):
openssl rand -base64 32
echo.

echo ======================================
echo Add these to your .env file
echo ======================================
