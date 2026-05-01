# Authelia Configuration

This directory contains configuration files for Authelia, your Single Sign-On (SSO) authentication server.

## Files

- **authelia.yml**: Main Authelia configuration file
  - Server settings
  - Session configuration
  - Storage backend
  - Authentication rules
  - Access control policies
  - TOTP (two-factor authentication) settings

- **users_database.yml**: User database with credentials
  - User accounts with password hashes
  - User groups and roles
  - Display names and email addresses

## Setup Instructions

### 1. Generate Password Hashes

For security, never store plain-text passwords. Generate Argon2id hashes using the Authelia container:

```bash
# In the infra-stack directory
docker run --rm authelia/authelia:latest authelia hash-password "your-password"
```

This will output something like:

```
$argon2id$v=19$m=65540,t=3,p=4$...
```

Copy the hash and replace the existing password hashes in `users_database.yml`.

### 2. Update Configuration

Edit `authelia.yml` and replace:

- `yourdomain.com` with your actual domain
- Update the ENCRYPTION_KEY in your .env file
- Set session domain to match your domain

### 3. Generate Encryption Key

Generate a strong encryption key for session encryption:

```bash
# Generate a 32-byte random key (base64 encoded)
openssl rand -base64 32
```

Add the output to your `.env` file:

```
ENCRYPTION_KEY=<your-generated-key>
```

## Integration with Nginx Proxy Manager

To protect a service with Authelia in Nginx Proxy Manager:

1. Go to Nginx Proxy Manager (port 81)
2. Add or edit a Proxy Host
3. Under "Custom Locations", add:
   - Location: `/`
   - Scheme: `http`
   - Forward Hostname/IP: `authelia`
   - Forward Port: `9091`
   - Auth Type: `Forward Auth`
   - Auth URL: `http://authelia:9091/api/verify?rd=https://$host/`
   - Auth URI: `/api/verify?rd=https://$host/`
   - Auth Parse: Check the box to parse JSON response

Or use the simpler approach with middleware/auth plugins if available in your Nginx version.

## User Management

### Add New Users

1. Edit `users_database.yml`
2. Add entry with generated password hash
3. Assign to appropriate groups
4. Restart Authelia container: `docker compose restart authelia`

### Change Passwords

1. Generate new hash: `docker run --rm authelia/authelia:latest authelia hash-password "new-password"`
2. Update the hash in `users_database.yml`
3. Restart Authelia container

### Reset Forgotten Password

Generate a new hash and update `users_database.yml`, then restart.

## TOTP (Two-Factor Authentication)

TOTP is enabled by default. Users can:

1. Log in to https://authelia.yourdomain.com
2. Generate TOTP secret in their profile
3. Scan QR code with authenticator app (Google Authenticator, Authy, etc.)
4. Confirm by entering the 6-digit code

## Access Control Policies

- **bypass**: No authentication required
- **one_factor**: Username/password only
- **two_factor**: Username/password + TOTP

Adjust the access control rules in `authelia.yml` based on your service requirements.

## Troubleshooting

### Users can't log in

1. Check password hashes in `users_database.yml`
2. Check Authelia logs: `docker compose logs authelia`
3. Verify domain settings match your configuration

### SSO not working with Nginx

1. Verify Nginx custom location is correctly configured
2. Check that Authelia container is running: `docker compose ps authelia`
3. Test Authelia directly: `curl http://localhost:9091/api/verify`

### TOTP not working

1. Ensure system time is synchronized (NTP)
2. Check TOTP issuer name in `authelia.yml` matches what you see in authenticator app
3. Clear TOTP cache by logging out and back in

## Production Checklist

- [ ] Change default passwords for all users
- [ ] Generate strong encryption key
- [ ] Update domain names throughout configuration
- [ ] Enable HTTPS on all services
- [ ] Configure SMTP for password reset emails (if needed)
- [ ] Set up backups for user database
- [ ] Monitor Authelia logs for security issues
- [ ] Configure firewall to limit access to Authelia port 9091
