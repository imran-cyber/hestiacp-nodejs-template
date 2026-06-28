# Multi-App Deployment Guide

## Architecture

```
Server (HestiaCP + Nginx)
├── user1
│   ├── api.domain.com   → Port 3001  (Express API)
│   └── app.domain.com   → Port 3002  (React/Next.js)
├── user2
│   └── api.client.com   → Port 3003  (MERN backend)
└── user3
    └── ws.client.com    → Port 3004  (Socket.IO)
```

Each user's PM2 processes are isolated — no user can see or stop another's apps.

---

## Pattern 1: Pure API backend

App lives in `/home/USER/web/DOMAIN/nodeapp/`.  
All requests hit Express. Frontend is a separate domain.

```javascript
// src/server.js
const express = require('express');
const app = express();

app.use(express.json());
app.get('/api/health', (req, res) => res.json({ ok: true }));

const PORT = process.env.PORT;  // always from env
app.listen(PORT, '127.0.0.1');
```

---

## Pattern 2: MERN — separate API and static frontend

Two domains, two nodeapp directories, two ports.

```
api.myapp.com   → port 3001  (Express API)
app.myapp.com   → port 3002  (Vite/React static served by Node or nginx)
```

Or, for a single domain with both:
- Put built React files in `/home/USER/web/DOMAIN/public/`
- Serve them from nginx's `root` directive (they are already there)
- Proxy only `/api/` to Express

To do that, add a custom nginx snippet at:
`/home/USER/conf/web/DOMAIN/nginx.ssl.conf_custom`

```nginx
# Serve Vite build from public/
location / {
    root  /home/USER/web/DOMAIN/public;
    index index.html;
    try_files $uri $uri/ /index.html;
}

# Proxy API calls to Express
location /api/ {
    proxy_pass         http://127.0.0.1:PORT;
    proxy_http_version 1.1;
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto $scheme;
    proxy_connect_timeout 60s;
    proxy_read_timeout    60s;
}
```

Then rebuild: `v-rebuild-web-domain USER DOMAIN`

---

## Adding a new app

```bash
# 1. HestiaCP Panel → Web → Add Domain → Template: NodeJS → Save
# 2. SSH as user
ssh USER@server

# 3. Upload app
cd ~/web/DOMAIN/nodeapp
git clone https://github.com/yourrepo/app.git .
npm install --production

# 4. Start
pm2 start ecosystem.config.js
pm2 save
```

---

## Managing multiple apps

```bash
pm2 status               # all apps for this user
pm2 logs DOMAIN          # live logs
pm2 restart DOMAIN       # restart one app
pm2 reload DOMAIN        # zero-downtime reload
pm2 delete DOMAIN        # stop and remove from PM2
```

---

## PM2 auto-start on server reboot

Run this once per user:
```bash
pm2 startup              # prints a command — run it as root
pm2 save                 # saves current process list
```

---

## Cluster mode (high-traffic apps)

Edit `ecosystem.config.js`:
```javascript
instances: 'max',      // use all CPU cores
exec_mode: 'cluster',
```

Then restart: `pm2 delete DOMAIN && pm2 start ecosystem.config.js`
