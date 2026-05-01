#!/bin/bash
# Generate Authelia Secrets Script
# Run this script to generate secure secrets for Authelia configuration

echo "🔐 Authelia Secrets Generator"
echo "======================================"
echo ""

# Function to generate base64 secret
generate_secret() {
    openssl rand -base64 32
}

echo "Generating required secrets..."
echo ""

echo "JWT_SECRET (for session tokens):"
JWT=$(generate_secret)
echo $JWT
echo ""

echo "SESSION_SECRET (for session encryption):"
SESSION=$(generate_secret)
echo $SESSION
echo ""

echo "STORAGE_ENCRYPTION_KEY (for database encryption):"
STORAGE=$(generate_secret)
echo $STORAGE
echo ""

echo "======================================"
echo "Add these to your .env file:"
echo ""
echo "AUTHELIA_JWT_SECRET=$JWT"
echo "AUTHELIA_SESSION_SECRET=$SESSION"
echo "AUTHELIA_STORAGE_ENCRYPTION_KEY=$STORAGE"
echo ""
