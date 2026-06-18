---

# Nginx Proxy Manager Forward Auth Configuration Examples

This file contains example configurations for setting up forward authentication with Authelia in Nginx Proxy Manager.

## Web UI Configuration

### Step-by-Step for Each Service

**Example: Protecting Homepage**

1. **Log into Nginx Proxy Manager** → `http://localhost:81`
   - Email: `admin@example.com`
   - Password: `changeme` (change this!)

2. **Proxy Hosts** → **Add Proxy Host**

3. **Details Tab:**

   ```
   Domain Names: homepage.yourdomain.com
   Scheme: http
   Forward Hostname/IP: homepage
   Forward Port: 3000
   Block Common Exploits: ✓ Checked
   Websockets Support: ✓ Checked
   Buffering: OFF
   ```

4. **Custom Locations Tab:**

   ```
   Click "Add Custom Location"

   Location: /
   Forward Scheme: http
   Forward Hostname/IP: authelia
   Forward Port: 9091

   Check "Forward Authentication"
   Auth URL: /api/verify?rd=https://$host/
   Auth URI: /api/verify?rd=https://$host/

   Advanced (Custom Nginx Configuration):
   auth_request_set $remote_user $upstream_http_remote_user;
   auth_request_set $remote_groups $upstream_http_remote_groups;
   auth_request_set $remote_name $upstream_http_remote_name;
   auth_request_set $remote_email $upstream_http_remote_email;
   ```

5. **SSL Tab:**

   ```
   SSL Certificate: Request a new SSL certificate
   Certificate Provider: Let's Encrypt
   Enable HTTP/2 Support: ✓
   Redirect HTTP to HTTPS: ✓
   Force SSL: ✓
   HSTS Enabled: ✓
   HSTS Subdomains: ✓
   ```

6. **Access Tab (Optional):**
   - Can restrict by IP address if needed

7. **Click Save**

### Services Configuration Template

Copy and modify for each service:

**Uptime-Kuma:**

```
Domain: uptime-kuma.yourdomain.com
Forward to: uptime-kuma:3001
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**Sonarr:**

```
Domain: sonarr.yourdomain.com
Forward to: sonarr:8989
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**Radarr:**

```
Domain: radarr.yourdomain.com
Forward to: radarr:7878
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**Lidarr:**

```
Domain: lidarr.yourdomain.com
Forward to: lidarr:8686
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**Readarr:**

```
Domain: readarr.yourdomain.com
Forward to: readarr:8787
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**Prowlarr:**

```
Domain: prowlarr.yourdomain.com
Forward to: prowlarr:9696
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**Bazarr:**

```
Domain: bazarr.yourdomain.com
Forward to: bazarr:6767
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**Overseerr:**

```
Domain: overseerr.yourdomain.com
Forward to: overseerr (note: uses internal port from compose)
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**qBittorrent (if exposing):**

```
Domain: qbittorrent.yourdomain.com
Forward to: gluetun:8080
Forward Auth: authelia:9091 (/api/verify?rd=https://$host/)
```

**Authelia Portal (NO authentication):**

```
Domain: authelia.yourdomain.com
Forward to: authelia:9091
Forward Auth: DISABLED
```

## Manual Nginx Configuration (Advanced)

If you need to configure this manually in a docker-compose file or standalone:

### Authelia HTTP Backend

```nginx
upstream authelia {
    server authelia:9091;
}

# Forward auth location
location = /api/verify {
    internal;
    proxy_pass http://authelia/api/verify;

    # Required headers for Authelia
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Original-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    # Uncomment for debugging
    # access_log /var/log/nginx/authelia_verify.log;
}

# Example protected service
server {
    server_name homepage.yourdomain.com;

    location / {
        auth_request /api/verify;

        # Capture response headers from auth_request
        auth_request_set $remote_user $upstream_http_remote_user;
        auth_request_set $remote_groups $upstream_http_remote_groups;
        auth_request_set $remote_name $upstream_http_remote_name;
        auth_request_set $remote_email $upstream_http_remote_email;

        # Forward request to service
        proxy_pass http://homepage:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Remote-User $remote_user;
        proxy_set_header Remote-Groups $remote_groups;
        proxy_set_header Remote-Name $remote_name;
        proxy_set_header Remote-Email $remote_email;
    }
}
```

## Docker Compose Service Configuration

If adding to your own nginx service (advanced):

```yaml
services:
  nginx:
    image: nginx:latest
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - homelab
    depends_on:
      - authelia
```

## Testing Authelia

### Health Check

```bash
curl http://localhost:9091/api/state
# Should return: {"status":"ok"}
```

### Test Verify Endpoint

```bash
curl -i http://localhost:9091/api/verify
# Should return: 401 Unauthorized (without auth)
```

### Test with Valid Session

```bash
# First authenticate to get session
curl -X POST http://localhost:9091/api/firstfactor \
  -d '{"username":"admin","password":"admin"}' \
  -H "Content-Type: application/json" \
  -c cookies.txt

# Then verify with session
curl -b cookies.txt http://localhost:9091/api/verify
# Should return: 200 OK
```

## Common Issues and Solutions

### "Bad Gateway" Error

- Check Authelia container is running: `docker compose ps authelia`
- Verify Nginx can reach Authelia: `docker compose exec nginx curl http://authelia:9091/api/state`
- Check Nginx logs: `docker compose logs nginx`

### Service Accessible Without Auth

- Verify Forward Auth is enabled in Nginx Proxy Manager
- Check Custom Location is set to "/" not "/index"
- Clear browser cache and try incognito window

### Redirect Loop

- Check `default_redirection_url` in authelia.yml
- Verify domain matches what's in the browser
- Make sure HTTPS is working (let's encrypt certificate)

### Session Expires Immediately

- Check session cookie domain matches your domain
- Verify system time is correct (NTP)
- Increase session timeout in authelia.yml if needed

## Debugging

Enable auth request logging in Nginx:

```nginx
location = /api/verify {
    # ... config above ...
    access_log /var/log/nginx/authelia_verify.log;
    error_log /var/log/nginx/authelia_verify_error.log debug;
}
```

View Authelia logs:

```bash
docker compose logs -f authelia
```

View full request/response:

```bash
curl -v -b cookies.txt http://localhost:9091/api/verify
```
