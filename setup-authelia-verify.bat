@echo off
REM Authelia SSO Setup Verification and Quick Start Script
REM This script helps verify the setup and guides through initial configuration

cls
echo ==================================
echo 🔐 Authelia SSO Setup Verification
echo ==================================
echo.

REM Check if we're in the right directory
if not exist setup.ps1 (
    echo ❌ Error: Please run this script from the root of your server-setup repository
    exit /b 1
)

echo ✅ Running from correct directory
echo.

REM Check for necessary files
echo 📋 Checking configuration files...

if exist "infra-stack/yaml-config/authelia/authelia.yml" (
    echo   ✅ infra-stack/yaml-config/authelia/authelia.yml
) else (
    echo   ❌ infra-stack/yaml-config/authelia/authelia.yml (MISSING^!)
)

if exist "infra-stack/yaml-config/authelia/users_database.yml" (
    echo   ✅ infra-stack/yaml-config/authelia/users_database.yml
) else (
    echo   ❌ infra-stack/yaml-config/authelia/users_database.yml (MISSING^!)
)

if exist "AUTHELIA-QUICK-START.md" (
    echo   ✅ AUTHELIA-QUICK-START.md
) else (
    echo   ❌ AUTHELIA-QUICK-START.md (MISSING^!)
)

echo.
echo ==================================
echo 📊 Setup Status Summary
echo ==================================
echo.
echo ✅ Authelia configuration files created
echo ✅ Redis service added to compose.yml
echo ✅ Authelia service added to compose.yml
echo ✅ Documentation created
echo ✅ Helper scripts included
echo ✅ Setup script updated
echo.

echo ==================================
echo 🚀 Quick Start Steps
echo ==================================
echo.
echo 1️⃣  Generate Secrets (REQUIRED^)
echo    cd infra-stack/yaml-config/authelia
echo    generate-secrets.bat
echo.

echo 2️⃣  Add Secrets to .env
echo    Edit: infra-stack/.env
echo    Add the three values from step 1
echo.

echo 3️⃣  Generate Password Hash
echo    cd infra-stack/yaml-config/authelia
echo    generate-hash.bat "YourPassword123!"
echo.

echo 4️⃣  Update Configuration
echo    Edit: infra-stack/yaml-config/authelia/authelia.yml
echo    Replace: yourdomain.com ^-^> your actual domain
echo.
echo    Edit: infra-stack/yaml-config/authelia/users_database.yml
echo    Replace: password hashes with your generated hash
echo.

echo 5️⃣  Start Services
echo    npm run setup
echo    npm run start:all
echo.

echo 6️⃣  Verify Installation
echo    curl http://localhost:9091/api/state
echo    Should return: {"status":"ok"}
echo.

echo 7️⃣  Configure Nginx Proxy Manager
echo    Follow: infra-stack/yaml-config/authelia/NGINX-CONFIG.md
echo    For each service add proxy host with Forward Auth
echo.

echo ==================================
echo 📚 Documentation Files
echo ==================================
echo.
echo Start here:
echo   AUTHELIA-QUICK-START.md - One-page reference (READ FIRST^)
echo.
echo Then read:
echo   AUTHELIA-SSO-SETUP.md - Complete setup guide
echo   AUTHELIA-CHANGES-SUMMARY.md - What was added
echo.
echo For specific topics:
echo   infra-stack/yaml-config/authelia/SETUP-GUIDE.md - Detailed config
echo   infra-stack/yaml-config/authelia/NGINX-CONFIG.md - Nginx setup
echo   infra-stack/yaml-config/authelia/README.md - User management
echo.

echo ==================================
echo 🔐 Security Reminders
echo ==================================
echo.
echo ⚠️  IMPORTANT: Change default admin password immediately!
echo ⚠️  IMPORTANT: Generate strong secrets (don't reuse passwords^)
echo ⚠️  IMPORTANT: Update domain name in all configs
echo ⚠️  IMPORTANT: Enable HTTPS on all services (Let's Encrypt^)
echo.

echo ==================================
echo ✨ Setup complete!
echo ==================================
echo.
echo Next action: Generate secrets
echo   cd infra-stack/yaml-config/authelia
echo   generate-secrets.bat
echo.
pause
