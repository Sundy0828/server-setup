---

# Authelia with Nginx Proxy Manager - Setup Guide

This guide walks through integrating Authelia SSO with Nginx Proxy Manager to protect all your homelab services.

## Quick Start

### 1. Generate Secrets

Generate three random secrets (use one of these methods):

**Windows:**

```powershell
generate-secrets.bat
```

**Linux/Mac:**

```bash
bash generate-secrets.sh
```

**Docker (any OS):**

```bash
docker run --rm alpine/openssl rand -base64 32
# Run this command 3 times
```

Add the output to `infra-stack/.env`:

```env
AUTHELIA_JWT_SECRET=<generated-value>
AUTHELIA_SESSION_SECRET=<generated-value>
AUTHELIA_STORAGE_ENCRYPTION_KEY=<generated-value>
```

### 2. Update Configuration

Edit `authelia.yml` and replace all instances of `yourdomain.com` with your actual domain.

### 3. Set User Passwords

Edit `users_database.yml` and generate password hashes:

**Windows:**

```powershell
generate-hash.bat "your-secure-password"
```

**Linux/Mac:**

```bash
bash generate-hash.sh "your-secure-password"
```

**Docker:**

```bash
docker run --rm authelia/authelia:latest authelia hash-password "your-secure-password"
```

Replace the hashes in `users_database.yml`.

### 4. Start Services

```bash
cd infra-stack
docker compose up -d
```

Verify Authelia is running:

```bash
docker compose ps authelia
curl http://localhost:9091/api/state
```

## Configuring Nginx Proxy Manager

### Method 1: Using Forward Auth (Recommended)

For each service you want to protect:

1. **Go to Nginx Proxy Manager** (http://localhost:81)
2. **Add or Edit a Proxy Host**
3. **Details tab:**
   - Domain: `service.yourdomain.com`
   - Scheme: `http`
   - Forward Hostname/IP: `<service-container-name>`
   - Forward Port: `<service-port>`

4. **Custom Locations tab:**
   - Click "Add Custom Location"
   - Location: `/`
   - Scheme: `http`
   - Forward Hostname/IP: `authelia`
   - Forward Port: `9091`
   - Enable: "Forward Authentication"
   - Authentication URI: `/api/verify?rd=https://$host/`

5. **SSL tab:**
   - Request a new SSL certificate (Let's Encrypt)
   - Enable Redirect HTTP to HTTPS
   - Enable Force SSL
   - Enable HTTP/2

### Method 2: Using Access Control Lists

Alternative method using Nginx access control:

1. Go to Access Lists
2. Create a new list
3. Add Authelia server details
4. Apply to proxy hosts

## Architecture

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTPS
       ↓
┌─────────────────────────────────────┐
│   Nginx Proxy Manager (Port 443)    │
│   - SSL/TLS Termination             │
│   - Request Forwarding              │
│   - Forward Auth to Authelia        │
└──────┬──────────────────────────────┘
       │ (Unauthenticated Request)
       ↓
┌──────────────────┐
│   Authelia       │ (Port 9091)
│   - Verify Auth  │
│   - Login Portal │
│   - Session Mgmt │
└────────┬─────────┘
         │ (Auth Check)
         ↓
    ✓ Authenticated
         │
         ↓ (Redirect to service)
┌──────────────────────┐
│  Protected Service   │
│  (e.g., Homepage)    │
└──────────────────────┘
```

## Protecting Services

### Services that should be protected (add to authelia.yml):

- Homepage
- Uptime-Kuma
- Duplicati
- Overseerr
- Sonarr, Radarr, Lidarr, Readarr, Prowlarr, Bazarr
- Homeassistant
- AdGuard Home

### Services that might not need protection:

- Plex (has own auth)
- qBittorrent (optional - can be internal only)

## Nginx Configuration Examples

### Homepage

```
Domain: homepage.yourdomain.com
Forward to: homepage:3000
With Forward Auth: authelia:9091
```

### Sonarr

```
Domain: sonarr.yourdomain.com
Forward to: sonarr:8989
With Forward Auth: authelia:9091
```

## Advanced Configuration

### Enable TOTP (Two-Factor Authentication)

TOTP is already enabled in the default config. Users can:

1. Log into the Authelia portal: `https://authelia.yourdomain.com`
2. Click on their username
3. Add TOTP device
4. Scan QR code with authenticator (Google Authenticator, Authy, Microsoft Authenticator)
5. Confirm with 6-digit code

Then update access control to require two_factor:

```yaml
- domain:
    - admin.yourdomain.com
  policy: two_factor
```

### Enable Password Reset via Email

Edit the `authelia.yml` SMTP section:

```yaml
notifier:
  disable_startup_check: false
  smtp:
    host: smtp.gmail.com
    port: 587
    username: your-email@gmail.com
    password: your-app-password
    sender: jerrod.sunderland@gmail.com
    identifier: localhost
    starttls: true
    trusted_cert: ""
```

Add to `.env`:

```env
AUTHELIA_NOTIFIER_SMTP_HOST=smtp.gmail.com
AUTHELIA_NOTIFIER_SMTP_PORT=587
AUTHELIA_NOTIFIER_SMTP_USERNAME=your-email@gmail.com
AUTHELIA_NOTIFIER_SMTP_PASSWORD=your-app-password
AUTHELIA_NOTIFIER_SMTP_SENDER=jerrod.sunderland@gmail.com
```

### Add More Users

1. Edit `users_database.yml`
2. Generate password hash: `bash generate-hash.sh "password"`
3. Add entry:
   ```yaml
   newuser:
     displayname: "New User"
     password: "$argon2id$v=19$m=65540,t=3,p=4$..."
     email: newuser@yourdomain.com
     groups:
       - users
   ```
4. Restart Authelia: `docker compose restart authelia`

### Different Access Policies

```yaml
access_control:
  rules:
    # No auth required
    - domain: "public.yourdomain.com"
      policy: bypass

    # Password only
    - domain: "standard.yourdomain.com"
      policy: one_factor

    # Password + TOTP
    - domain: "admin.yourdomain.com"
      policy: two_factor

    # Limited by group
    - domain: "apps.yourdomain.com"
      policy: one_factor
      users:
        - admin
        - power_user
```

## Troubleshooting

### Login page shows but won't authenticate

1. Check user hashes: `docker compose logs authelia | grep password`
2. Verify users_database.yml format
3. Restart container: `docker compose restart authelia`

### "Invalid credentials" for correct password

- Verify password hash is correct: `bash generate-hash.sh "test"` and compare
- Check users_database.yml isn't using old hashes
- Clear browser cookies and try again

### Nginx can't reach Authelia

1. Verify container is running: `docker compose ps authelia`
2. Check Nginx logs: `docker compose logs nginx`
3. Test Authelia directly: `curl http://authelia:9091/api/state`

### TOTP not working

- System time must be synchronized (check NTP)
- TOTP tokens only valid for 30 seconds
- Ensure authenticator app has correct time

### Session keeps expiring

- Increase inactivity timeout in authelia.yml:
  ```yaml
  session:
    inactivity: 1h # Increase from 15m
  ```

## Nginx Proxy Manager Forward Auth Configuration Details

When setting up forward authentication in Nginx, the typical configuration is:

```
location / {
    auth_request /api/verify;
    auth_request_set $remote_user $upstream_http_remote_user;
    auth_request_set $remote_groups $upstream_http_remote_groups;
    proxy_pass http://service:port;
}

location = /api/verify {
    internal;
    proxy_pass http://authelia:9091;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
}
```

Nginx Proxy Manager should handle this automatically when you enable Forward Authentication.

## Security Best Practices

1. ✅ **Always use HTTPS** - Configure SSL certificates for all domains
2. ✅ **Strong Passwords** - Use passwords with mixed case, numbers, and symbols
3. ✅ **Enable TOTP** - For admin accounts at minimum
4. ✅ **Regular Backups** - Back up users_database.yml and encryption keys
5. ✅ **Monitor Logs** - Check Authelia logs regularly for failed login attempts
6. ✅ **Change Default Credentials** - Replace default admin password immediately
7. ✅ **Update Regularly** - Keep Authelia container image updated
8. ✅ **Limit Access** - Don't expose Authelia portal publicly without reason

## Additional Resources

- [Authelia Official Documentation](https://www.authelia.com/)
- [Nginx Proxy Manager Documentation](https://nginxproxymanager.com/)
- [Forward Authentication Concepts](https://www.authelia.com/integration/proxies/)
