#!/bin/bash
# Generate Authelia User Password Hashes
# Run this script to create password hashes for users

# This requires the authelia container to be running
# Or you can generate hashes directly with:
# docker run --rm authelia/authelia:latest authelia hash-password "your-password"

echo "🔐 Authelia User Hash Generator"
echo "======================================"
echo ""

if [ -z "$1" ]; then
    echo "Usage: ./generate-hash.sh <password>"
    echo ""
    echo "Example:"
    echo "  ./generate-hash.sh 'MySecurePassword123!'"
    echo ""
    echo "Or use Docker directly:"
    echo "  docker run --rm authelia/authelia:latest authelia hash-password 'MySecurePassword123!'"
    exit 1
fi

# Generate hash using Docker
docker run --rm authelia/authelia:latest authelia hash-password "$1"

echo ""
echo "Copy the hash output above into users_database.yml"
