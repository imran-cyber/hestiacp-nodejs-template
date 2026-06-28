# HestiaCP Node.js Template v3.0

Production-grade Node.js template for HestiaCP 1.9.x.  
**Nginx + PHP-FPM only** (Apache must be disabled).

---

## Files

```
hestiacp-nodejs-template/
├── install.sh        ← Run this as root
├── uninstall.sh
├── nodejs.tpl        ← HTTP nginx template
├── nodejs.stpl       ← HTTPS/SSL nginx template
├── nodejs.sh         ← Port allocator + PM2 config generator
└── docs/
    ├── MULTI_APP_GUIDE.md
    └── TROUBLESHOOTING.md
```

---

## Installation

```bash
cd /root/hestiacp-nodejs-template
chmod +x install.sh uninstall.sh nodejs.sh
./install.sh
```

---

## How to deploy a Node.js app

### 1. Add domain in HestiaCP panel

- Web → Add Web Domain → enter your domain
- Advanced Options → **Web Template NGINX: NodeJS**
- Enable SSL + Let's Encrypt → Save

This automatically:
- Allocates a unique port (3001–3999) for the domain
- Creates `/home/USER/web/DOMAIN/nodeapp/` with logs/
- Generates `.env` (PORT, NODE_ENV, DOMAIN)
- Generates `ecosystem.config.js` for PM2

### 2. Upload your app

```bash
# SSH as the domain user
ssh USER@your-server.com
cd ~/web/DOMAIN/nodeapp

# Clone or copy files here
git clone https://github.com/yourrepo/app.git .
npm install --production
```

### 3. Start with PM2

```bash
cd ~/web/DOMAIN/nodeapp
pm2 start ecosystem.config.js
pm2 save          # persist across reboots
pm2 status        # verify it's running
```

### 4. Verify

```bash
# Check allocated port
grep DOMAIN /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs-ports.db

# Test app directly
curl http://127.0.0.1:PORT/

# Test via domain
curl -I https://DOMAIN
```

---

## IMPORTANT: Your app must read PORT from environment

```javascript
// server.js / src/server.js
const PORT = process.env.PORT || 3001;
app.listen(PORT, '127.0.0.1', () => {
  console.log(`Server running on port ${PORT}`);
});
```

The template supports both the backend-only setup and the MERN-style
split where nginx serves the React frontend from `public/` and proxies
`/api/` to Express. See `docs/MULTI_APP_GUIDE.md` for that pattern.

---

## Port registry

All port allocations are stored in:
```
/usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs-ports.db
```

Format: `domain.com:3001`

To manually change a domain's port:
```bash
# 1. Edit registry
nano /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs-ports.db

# 2. Update .env
nano /home/USER/web/DOMAIN/nodeapp/.env

# 3. Rebuild nginx config
v-rebuild-web-domain USER DOMAIN

# 4. Restart app
pm2 restart DOMAIN
```

---

## Troubleshooting

**502 Bad Gateway**
```bash
pm2 status                        # is the app running?
pm2 logs DOMAIN --lines 50        # check for errors
ss -tlnp | grep :PORT             # is it listening?
curl http://127.0.0.1:PORT/       # test directly
```

**Template not in HestiaCP dropdown**
```bash
ls /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.*
systemctl restart hestia
```

**Port placeholder still in nginx config**
```bash
grep NODEJS_PORT /home/USER/conf/web/DOMAIN/nginx.ssl.conf
# If found, run:
v-rebuild-web-domain USER DOMAIN
```

See `docs/TROUBLESHOOTING.md` for more.
