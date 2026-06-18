# Authelia Quick Reference Card

## 🚀 Getting Started (5 minutes)

### 1. Generate Secrets

```bash
cd infra-stack/yaml-config/authelia
./generate-secrets.bat  # Windows
# bash generate-secrets.sh  # Linux/Mac
```

### 2. Add to infra-stack/.env

```env
AUTHELIA_JWT_SECRET=<paste-generated>
AUTHELIA_SESSION_SECRET=<paste-generated>
AUTHELIA_STORAGE_ENCRYPTION_KEY=<paste-generated>
```

### 3. Create User Password

```bash
./generate-hash.bat "MySecurePass123!"  # Windows
# bash generate-hash.sh "MySecurePass123!"  # Linux/Mac
```

### 4. Update users_database.yml

Replace password hash in: `infra-stack/yaml-config/authelia/users_database.yml`

### 5. Update Domain

Edit `authelia.yml` → replace `yourdomain.com` → your domain

### 6. Start Services

```bash
npm run setup
npm run start:all
```

---

## 🔗 Important URLs

| Service         | URL                                | Port | Notes         |
| --------------- | ---------------------------------- | ---- | ------------- |
| Authelia Portal | `http://localhost:9091`            | 9091 | Login here    |
| Authelia API    | `http://localhost:9091/api/verify` | 9091 | Used by Nginx |
| Redis           | `localhost:6379`                   | 6379 | Internal only |

---

## ✅ Nginx Proxy Manager Setup (Per Service)

**Add for each protected service:**

1. **Proxy Host Details:**
   - Domain: `service.yourdomain.com`
   - Forward: `service-container:port`

2. **Custom Locations:**
   - Path: `/`
   - Forward: `authelia:9091`
   - Forward Auth: ✓ Enabled
   - Auth URL: `/api/verify?rd=https://$host/`

3. **SSL:**
   - Let's Encrypt certificate
   - Force SSL ✓

---

## 👤 User Management

### Add User

```bash
# 1. Generate hash
./generate-hash.bat "password"

# 2. Add to users_database.yml
username:
  displayname: "Name"
  password: "$argon2id$..."
  email: user@domain.com
  groups:
    - users

# 3. Restart
docker compose restart authelia
```

### Change Password

```bash
# 1. Generate new hash
./generate-hash.bat "newpass"

# 2. Update users_database.yml

# 3. Restart
docker compose restart authelia
```

---

## 🔐 Access Policies

```yaml
# No auth
policy: bypass

# Password only
policy: one_factor

# Password + TOTP (2FA)
policy: two_factor
```

---

## 🧪 Testing

```bash
# Check Authelia health
curl http://localhost:9091/api/state
# Expected: {"status":"ok"}

# Test authentication
curl -i http://localhost:9091/api/verify
# Expected: 401 Unauthorized (no auth)
```

---

## 📋 Checklist

- [ ] Generated secrets (3 values)
- [ ] Added to .env file
- [ ] Updated user passwords
- [ ] Updated domain in authelia.yml
- [ ] Started services (`npm run start:all`)
- [ ] Configured first service in Nginx
- [ ] Tested login
- [ ] Added remaining services to Nginx

---

## 🆘 Quick Fixes

| Problem              | Solution                                           |
| -------------------- | -------------------------------------------------- |
| Can't log in         | Check password hash: `./generate-hash.bat "admin"` |
| Service still public | Enable Forward Auth in Nginx                       |
| Session expires fast | Check Redis running: `docker compose ps redis`     |
| Domain issues        | Update `authelia.yml` with correct domain          |
| TOTP not working     | Check system time (NTP), clear cookies             |

---

## 📞 Help Resources

1. **Setup Guide**: `infra-stack/yaml-config/authelia/SETUP-GUIDE.md`
2. **Nginx Config**: `infra-stack/yaml-config/authelia/NGINX-CONFIG.md`
3. **User Guide**: `infra-stack/yaml-config/authelia/README.md`
4. **Full Guide**: `/AUTHELIA-SSO-SETUP.md`
5. **Official Docs**: https://www.authelia.com/

---

## 📝 Common Commands

```bash
# View logs
docker compose logs -f authelia

# Restart
docker compose restart authelia

# Check status
docker compose ps authelia

# Restart specific service
docker compose restart authelia redis

# View configuration
docker compose exec authelia cat /config/authelia.yml
```

---

## 🎯 Protected Services

- Homepage
- Uptime-Kuma
- Duplicati
- AdGuard Home
- Home Assistant
- Sonarr, Radarr, Lidarr, Readarr
- Prowlarr, Bazarr
- Overseerr
- qBittorrent (optional)

---

## 📦 What's Included

✅ Authelia container (port 9091)
✅ Redis for sessions (port 6379)
✅ Configuration templates
✅ User database template
✅ Password hash generator
✅ Secret generator
✅ Setup automation
✅ Comprehensive guides

---

## 🔑 Default Credentials

**Username**: admin
**Password**: [YOUR PASSWORD HASH]

**Change immediately!**

```bash
./generate-hash.bat "YourNewPassword123!"
```

---

Last Updated: 2025
For the latest, see: /AUTHELIA-SSO-SETUP.md
