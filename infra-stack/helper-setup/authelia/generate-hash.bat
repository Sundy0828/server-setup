@echo off
REM Generate Authelia User Password Hashes for Windows
REM Run this script to create password hashes for users

setlocal enabledelayedexpansion

echo.
echo 🔐 Authelia User Hash Generator
echo ======================================
echo.

if "%1"=="" (
    echo Usage: generate-hash.bat ^<password^>
    echo.
    echo Example:
    echo   generate-hash.bat "MySecurePassword123!"
    echo.
    echo Or use Docker directly:
    echo   docker run --rm authelia/authelia:latest authelia hash-password "MySecurePassword123!"
    exit /b 1
)

REM Generate hash using Docker
docker run --rm authelia/authelia:latest authelia hash-password "%1"

echo.
echo Copy the hash output above into users_database.yml
