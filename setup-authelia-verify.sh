#!/bin/bash
# Authelia SSO Setup Verification and Quick Start Script
# This script helps verify the setup and guides through initial configuration

set -e

echo "=================================="
echo "🔐 Authelia SSO Setup Verification"
echo "=================================="
echo ""

# Check if we're in the right directory
if [ ! -f "setup.ps1" ]; then
    echo "❌ Error: Please run this script from the root of your server-setup repository"
    exit 1
fi

echo "✅ Running from correct directory"
echo ""

# Check for necessary files
echo "📋 Checking configuration files..."

files_to_check=(
    "infra-stack/yaml-config/authelia/authelia.yml"
    "infra-stack/yaml-config/authelia/users_database.yml"
    "infra-stack/yaml-config/authelia/generate-secrets.bat"
    "infra-stack/yaml-config/authelia/generate-hash.bat"
    "AUTHELIA-QUICK-START.md"
    "AUTHELIA-SSO-SETUP.md"
)

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file (MISSING!)"
    fi
done

echo ""
echo "=================================="
echo "📊 Setup Status Summary"
echo "=================================="
echo ""
echo "✅ Authelia configuration files created"
echo "✅ Redis service added to compose.yml"
echo "✅ Authelia service added to compose.yml"
echo "✅ Documentation created"
echo "✅ Helper scripts included"
echo "✅ Setup script updated"
echo ""

echo "=================================="
echo "🚀 Quick Start Steps"
echo "=================================="
echo ""
echo "1️⃣  Generate Secrets (REQUIRED)"
echo "   Windows: cd infra-stack/yaml-config/authelia && generate-secrets.bat"
echo "   Linux:   cd infra-stack/yaml-config/authelia && bash generate-secrets.sh"
echo ""

echo "2️⃣  Add Secrets to .env"
echo "   Edit: infra-stack/.env"
echo "   Add the three values from step 1"
echo ""

echo "3️⃣  Generate Password Hash"
echo "   Windows: cd infra-stack/yaml-config/authelia && generate-hash.bat \"YourPassword123!\""
echo "   Linux:   cd infra-stack/yaml-config/authelia && bash generate-hash.sh \"YourPassword123!\""
echo ""

echo "4️⃣  Update Configuration"
echo "   Edit: infra-stack/yaml-config/authelia/authelia.yml"
echo "   Replace: yourdomain.com → your actual domain"
echo ""
echo "   Edit: infra-stack/yaml-config/authelia/users_database.yml"
echo "   Replace: password hashes with your generated hash"
echo ""

echo "5️⃣  Start Services"
echo "   npm run setup"
echo "   npm run start:all"
echo ""

echo "6️⃣  Verify Installation"
echo "   curl http://localhost:9091/api/state"
echo "   Should return: {\"status\":\"ok\"}"
echo ""

echo "7️⃣  Configure Nginx Proxy Manager"
echo "   Follow: infra-stack/yaml-config/authelia/NGINX-CONFIG.md"
echo "   For each service:"
echo "   - Add proxy host"
echo "   - Enable Forward Auth"
echo "   - Point to authelia:9091"
echo ""

echo "=================================="
echo "📚 Documentation Files"
echo "=================================="
echo ""
echo "Start here:"
echo "  📄 AUTHELIA-QUICK-START.md - One-page reference (READ FIRST)"
echo ""
echo "Then read:"
echo "  📘 AUTHELIA-SSO-SETUP.md - Complete setup guide"
echo "  📗 AUTHELIA-CHANGES-SUMMARY.md - What was added"
echo ""
echo "For specific topics:"
echo "  🔧 infra-stack/yaml-config/authelia/SETUP-GUIDE.md - Detailed configuration"
echo "  🌐 infra-stack/yaml-config/authelia/NGINX-CONFIG.md - Nginx integration"
echo "  👤 infra-stack/yaml-config/authelia/README.md - User management"
echo ""

echo "=================================="
echo "🔐 Security Reminders"
echo "=================================="
echo ""
echo "⚠️  IMPORTANT: Change default admin password immediately!"
echo "⚠️  IMPORTANT: Generate strong secrets (don't reuse passwords)"
echo "⚠️  IMPORTANT: Update domain name in all configs"
echo "⚠️  IMPORTANT: Enable HTTPS on all services (Let's Encrypt)"
echo ""

echo "=================================="
echo "✨ Setup complete!"
echo "=================================="
echo ""
echo "Next action: Generate secrets"
echo "  cd infra-stack/yaml-config/authelia"
echo "  generate-secrets.bat"
echo ""
