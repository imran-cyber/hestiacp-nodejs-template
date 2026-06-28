# Node.js App Deployment Guide — HestiaCP v4.0

এই guide অনুসরণ করলে যেকোনো Node.js/MERN app কোনো extra config ছাড়াই deploy হবে।

---

## Architecture (প্রতিটা domain এর জন্য)

```
Internet
   ↓ HTTPS
Nginx (HestiaCP)
   ├── /api/*  →  proxy  →  Node.js (port 3001, 3002, ... auto)
   └── /*      →  static →  /home/USER/web/DOMAIN/public_html/
                             (React build files এখানে)
```

---

## File Structure

```
/home/USER/web/DOMAIN/
├── public_html/              ← React build files এখানে (index.html, static/)
│   └── backend/              ← Node.js app এখানে
│       ├── server.js         ← entry point
│       ├── .env              ← auto-generated (PORT, NODE_ENV, DOMAIN)
│       ├── ecosystem.config.js ← auto-generated (PM2 config)
│       ├── logs/
│       └── node_modules/
└── conf/web/DOMAIN/
    └── nginx.ssl.conf        ← auto-configured
```

---

## Step-by-Step Deployment

### Step 1 — HestiaCP Panel এ Domain Add করুন

1. HestiaCP → Web → **Add Web Domain**
2. Domain enter করুন (e.g. `myapp.com`)
3. **Advanced Options** → Web Template NGINX: **NodeJS**
4. Enable SSL + Let's Encrypt → **Save**

এটা automatically করবে:
- ✅ Port allocate (3001, 3002, ...)
- ✅ `/home/USER/web/DOMAIN/public_html/backend/` directory তৈরি
- ✅ `.env` file তৈরি (PORT সহ)
- ✅ `ecosystem.config.js` তৈরি
- ✅ Nginx config করা

---

### Step 2 — Backend Upload করুন

```bash
# Backend files এখানে রাখুন
/home/USER/web/DOMAIN/public_html/backend/

# server.js MUST listen on process.env.PORT
# ✅ CORRECT:
const PORT = process.env.PORT || 3001;
app.listen(PORT, '127.0.0.1', () => console.log(`Running on ${PORT}`));
```

**⚠️ Important — server.js এর শুরুতে dotenv থাকতে হবে:**
```javascript
require('dotenv').config();  // ← প্রথম line এ এটা থাকতে হবে
const express = require('express');
// ...
```

---

### Step 3 — Backend এর .env Configure করুন

Auto-generated .env:
```
/home/USER/web/DOMAIN/public_html/backend/.env
```

Edit করুন:
```bash
nano /home/USER/web/DOMAIN/public_html/backend/.env
```

```env
NODE_ENV=production
PORT=3001                    # ← এটা পরিবর্তন করবেন না
HOST=127.0.0.1
DOMAIN=myapp.com

# MongoDB
MONGODB_URI=mongodb://MONGO_USER:MONGO_PASS@127.0.0.1:27017/?authSource=DBNAME

# JWT
JWT_SECRET=your_random_secret_here

# Frontend URL (CORS এর জন্য)
FRONT_END_URL=https://myapp.com
```

---

### Step 4 — Dependencies Install করুন

```bash
su - USER -c "cd /home/USER/web/DOMAIN/public_html/backend && npm install --production"
```

---

### Step 5 — PM2 দিয়ে Backend Start করুন

```bash
# Start
su - USER -c "pm2 start /home/USER/web/DOMAIN/public_html/backend/ecosystem.config.js"

# Save (reboot এ auto-start)
su - USER -c "pm2 save"

# Verify
su - USER -c "pm2 list"
su - USER -c "pm2 logs DOMAIN --lines 20"
```

**PM2 auto-startup (একবার করলেই হবে):**
```bash
su - USER -c "pm2 startup"
# উপরের command একটা line দেবে, সেটা root এ run করুন
su - USER -c "pm2 save"
```

---

### Step 6 — Frontend Build করুন

```bash
# React/Vite build
su - USER -c "cd /home/USER/web/DOMAIN/public_html/frontend && npm install && npm run build"

# Build files (dist/ বা build/) public_html এ copy করুন
cp -r /home/USER/web/DOMAIN/public_html/frontend/dist/* \
      /home/USER/web/DOMAIN/public_html/

# অথবা Vite এ outDir সেট করুন: vite.config.js
# build: { outDir: '../', emptyOutDir: false }
```

---

### Step 7 — Verify করুন

```bash
# Port listen করছে কিনা
ss -tlnp | grep :PORT

# API কাজ করছে কিনা
curl https://DOMAIN/api/

# Frontend আসছে কিনা
curl -I https://DOMAIN
```

---

## Common Issues & Fix

### ❌ 502 Bad Gateway
```bash
# App চলছে কিনা
su - USER -c "pm2 list"

# Port match করছে কিনা
grep PORT /home/USER/web/DOMAIN/public_html/backend/.env
ss -tlnp | grep node

# App restart করুন
su - USER -c "pm2 restart DOMAIN"
```

### ❌ PORT load হচ্ছে না (app 5000 এ চলছে)
```bash
# server.js এর প্রথম line এ dotenv আছে কিনা দেখুন
head -3 /home/USER/web/DOMAIN/public_html/backend/server.js

# না থাকলে যোগ করুন
sed -i '1s/^/require("dotenv").config();\n/' \
  /home/USER/web/DOMAIN/public_html/backend/server.js

su - USER -c "pm2 restart DOMAIN"
```

### ❌ su - USER → "This account is currently not available"
```bash
chsh -s /bin/bash USER
```
> nodejs.sh v4.0 এ এটা automatically হয়।

### ❌ nginx restart failed (ssl_session_cache conflict)
```bash
sed -i '/ssl_session_cache.*shared:SSL/d' \
  /etc/nginx/conf.d/domains/DOMAIN.ssl.conf
nginx -t && systemctl restart nginx
```
> install.sh v4.0 এ এটা automatically হয়।

### ❌ Frontend 404 (React routes কাজ করছে না)
nginx এর `try_files $uri $uri/ /index.html` থাকলে ঠিক হবে।
> nodejs.stpl v4.0 এ এটা built-in।

---

## Multiple Apps (Same Server)

প্রতিটা domain এর জন্য শুধু Step 1-7 repeat করুন।
Port automatically আলাদা হবে (3001, 3002, 3003...).

```
myapp1.com    → port 3001
myapp2.com    → port 3002
client1.com   → port 3003
```

---

## PM2 Quick Commands

```bash
# সব app দেখুন
su - USER -c "pm2 list"

# Logs দেখুন
su - USER -c "pm2 logs DOMAIN --lines 50"

# Restart (code update এর পর)
su - USER -c "pm2 restart DOMAIN"

# Stop
su - USER -c "pm2 stop DOMAIN"

# Delete
su - USER -c "pm2 delete DOMAIN"
```
