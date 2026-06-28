# Troubleshooting Guide

## Quick diagnosis

```bash
# 1. Template files present?
ls -la /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs*

# 2. Port allocations
cat /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs-ports.db

# 3. Is the port placeholder replaced?
grep -n "NODEJS_PORT\|proxy_pass" /home/USER/conf/web/DOMAIN/nginx.ssl.conf

# 4. Is the app running?
pm2 status

# 5. Is the port listening?
ss -tlnp | grep :PORT

# 6. Test app directly
curl http://127.0.0.1:PORT/

# 7. Nginx errors
tail -50 /var/log/nginx/domains/DOMAIN.error.log

# 8. PM2 logs
pm2 logs DOMAIN --lines 50

# 9. Template script log
tail -50 /var/log/hestiacp-nodejs-template.log
```

---

## Issue: install.sh exits immediately after printing HestiaCP version

**Cause:** The old script used `v-list-sys-info plain` and `v-list-sys-config plain`
with brittle `awk '{print $5}'` / `awk '{print $2}'`. The output format varies
between HestiaCP versions, causing empty variables and `set -euo pipefail` to kill
the script silently.

**Fix (v3.0):** The installer now reads directly from `/usr/local/hestia/conf/hestia.conf`,
which is stable across versions.

---

## Issue: 502 Bad Gateway

| Cause | Fix |
|-------|-----|
| App not running | `pm2 start ecosystem.config.js` |
| Wrong port in nginx | `v-rebuild-web-domain USER DOMAIN` |
| `NODEJS_PORT` placeholder not replaced | Run rebuild (see below) |
| App crashed | `pm2 logs DOMAIN`, fix error, `pm2 restart DOMAIN` |

**Check if placeholder was replaced:**
```bash
grep "NODEJS_PORT" /home/USER/conf/web/DOMAIN/nginx.ssl.conf
```
If it still says `NODEJS_PORT` (not a real number), the `nodejs.sh` hook did not run
or failed. Fix:

```bash
# Run nodejs.sh manually
bash /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.sh \
     USER DOMAIN IP /home DOCROOT

# Or just rebuild the domain (HestiaCP re-runs nodejs.sh)
v-rebuild-web-domain USER DOMAIN

nginx -t && systemctl restart nginx
```

---

## Issue: Template not visible in HestiaCP dropdown

```bash
ls -la /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.tpl
ls -la /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.stpl

# Fix permissions if needed
chmod 644 /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.tpl
chmod 644 /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.stpl
chmod 755 /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.sh

# Restart HestiaCP so it re-scans templates
systemctl restart hestia
```

---

## Issue: Port conflict (EADDRINUSE)

```bash
# Find what is using the port
ss -tlnp | grep :PORT

# Change the port assignment
nano /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs-ports.db
# Edit line: domain.com:OLD_PORT  →  domain.com:NEW_PORT

nano /home/USER/web/DOMAIN/nodeapp/.env
# Change PORT=OLD_PORT → PORT=NEW_PORT

nano /home/USER/web/DOMAIN/nodeapp/ecosystem.config.js
# Change PORT: OLD_PORT → PORT: NEW_PORT

v-rebuild-web-domain USER DOMAIN
pm2 restart DOMAIN
```

---

## Issue: App stops after server reboot

```bash
# Run as the domain user
pm2 startup       # outputs a command — run it as root
pm2 save          # saves process list

# Verify
systemctl status pm2-USER
```

---

## Issue: nginx config test fails after template install

```bash
nginx -t 2>&1
```

Common cause: duplicate `limit_req_zone` directives in the nginx main config.
The NodeJS template defines per-domain rate limiting zones — they are unique
per domain so this should not conflict. If it does:

```bash
grep -r "limit_req_zone" /etc/nginx/
```

Remove or rename any global zone that clashes.

---

## Emergency rollback

```bash
BACKUP_DIR=$(ls -td /usr/local/hestia/data/templates/web/nginx/php-fpm/backups.* 2>/dev/null | head -1)
if [ -n "$BACKUP_DIR" ]; then
    bash "$BACKUP_DIR/restore.sh"
else
    echo "No backup found — remove template files manually"
    rm -f /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.tpl
    rm -f /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.stpl
    rm -f /usr/local/hestia/data/templates/web/nginx/php-fpm/nodejs.sh
    systemctl restart nginx hestia
fi
```
