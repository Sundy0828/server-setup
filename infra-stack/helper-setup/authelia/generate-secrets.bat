@echo off
REM Generate Authelia Secrets Script for Windows
REM Run this script to generate secure secrets for Authelia configuration

setlocal enabledelayedexpansion

echo.
echo 🔐 Authelia Secrets Generator
echo ======================================
echo.

REM Check if openssl is available, otherwise use PowerShell's cryptographic functions
set USE_OPENSSL=0
where openssl >nul 2>nul
if %errorlevel% equ 0 (
    set USE_OPENSSL=1
) else (
    echo Note: Using PowerShell to generate secrets since openssl is not installed
    echo.
)

echo Generating required secrets...
echo.

echo JWT_SECRET ^(for session tokens^):
if %USE_OPENSSL%==1 (
    openssl rand -base64 32
) else (
    powershell -NoProfile -Command "$bytes = New-Object byte[] 24; (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes); [Convert]::ToBase64String($bytes)"
)
echo.

echo SESSION_SECRET ^(for session encryption^):
if %USE_OPENSSL%==1 (
    openssl rand -base64 32
) else (
    powershell -NoProfile -Command "$bytes = New-Object byte[] 24; (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes); [Convert]::ToBase64String($bytes)"
)
echo.

echo STORAGE_ENCRYPTION_KEY ^(for database encryption^):
if %USE_OPENSSL%==1 (
    openssl rand -base64 32
) else (
    powershell -NoProfile -Command "$bytes = New-Object byte[] 24; (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes); [Convert]::ToBase64String($bytes)"
)
echo.

echo ======================================
echo Add these to your .env file
echo ======================================
