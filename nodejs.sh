#!/bin/bash
# =============================================================================
# HestiaCP Node.js Template — Dynamic Config Script v4.0
#
# HestiaCP calls this when a domain using NodeJS template is added/rebuilt.
#
# What this does:
#   1. Allocates a unique port (3001-3999) for the domain
#   2. Creates /home/USER/web/DOMAIN/public_html/backend/ directory
#   3. Writes .env with PORT, NODE_ENV, DOMAIN
#   4. Writes ecosystem.config.js for PM2
#   5. Replaces NODEJS_PORT placeholder in nginx configs
#   6. Writes nginx.ssl.conf_custom for API proxy (survives rebuilds)
#
# HestiaCP passes:
#   $1 = user
#   $2 = domain
#   $3 = ip
#   $4 = home  (e.g. /home)
#   $5 = docroot
# =============================================================================

USER="$1"
DOMAIN="$2"
IP="$3"
HOME_DIR="$4"
DOCROOT="$5"

TPL_DIR="/usr/local/hestia/data/templates/web/nginx/php-fpm"
PORT_DB="$TPL_DIR/nodejs-ports.db"
BACKEND_DIR="$HOME_DIR/$USER/web/$DOMAIN/public_html/backend"
NGINX_CONF="$HOME_DIR/$USER/conf/web/$DOMAIN/nginx.conf"
NGINX_SSL_CONF="$HOME_DIR/$USER/conf/web/$DOMAIN/nginx.ssl.conf"
CUSTOM_SSL_CONF="$HOME_DIR/$USER/conf/web/$DOMAIN/nginx.ssl.conf_nodejs"
LOG_FILE="/var/log/hestiacp-nodejs-template.log"

PORT_MIN=3001
PORT_MAX=3999

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [nodejs.sh] $*" >> "$LOG_FILE"; }

# ---------------------------------------------------------------------------
# Port allocation with lock to prevent race conditions
# ---------------------------------------------------------------------------
allocate_port() {
    local dom="$1"
    local lockfile="$PORT_DB.lock"

    local waited=0
    while ! mkdir "$lockfile" 2>/dev/null; do
        sleep 0.2
        waited=$((waited + 1))
        [ $waited -gt 50 ] && { log "Lock timeout"; break; }
    done

    # Already allocated?
    if [ -f "$PORT_DB" ]; then
        local existing
        existing=$(grep "^${dom}:" "$PORT_DB" 2>/dev/null | head -1 | cut -d: -f2)
        if [ -n "$existing" ]; then
            rmdir "$lockfile" 2>/dev/null || true
            echo "$existing"
            return 0
        fi
    fi

    # Find next free port
    local port=$PORT_MIN
    while [ $port -le $PORT_MAX ]; do
        if ! grep -q ":${port}$" "$PORT_DB" 2>/dev/null; then
            if ! ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                echo "${dom}:${port}" >> "$PORT_DB"
                rmdir "$lockfile" 2>/dev/null || true
                echo "$port"
                return 0
            fi
        fi
        port=$((port + 1))
    done

    # Fallback
    local hash_port
    hash_port=$(( PORT_MIN + ( $(echo "$dom" | cksum | cut -d' ' -f1) % (PORT_MAX - PORT_MIN + 1) ) ))
    echo "${dom}:${hash_port}" >> "$PORT_DB"
    rmdir "$lockfile" 2>/dev/null || true
    echo "$hash_port"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "--- Processing: $DOMAIN (user: $USER) ---"

# 1. Allocate port
PORT=$(allocate_port "$DOMAIN")
log "Port: $PORT"

# 2. Create backend directory
mkdir -p "$BACKEND_DIR/logs"
chown -R "$USER:$USER" "$BACKEND_DIR"
chmod 755 "$BACKEND_DIR"
log "Backend dir: $BACKEND_DIR"

# 3. Write .env (preserve existing, only update PORT)
if [ ! -f "$BACKEND_DIR/.env" ]; then
    cat > "$BACKEND_DIR/.env" << ENV_EOF
NODE_ENV=production
PORT=$PORT
HOST=127.0.0.1
DOMAIN=$DOMAIN

# MongoDB (update with your credentials)
# MONGODB_URI=mongodb://USER:PASS@127.0.0.1:27017/?authSource=DBNAME

# JWT
# JWT_SECRET=your_secret_here

# Frontend URL
# FRONT_END_URL=https://$DOMAIN
ENV_EOF
    chown "$USER:$USER" "$BACKEND_DIR/.env"
    chmod 600 "$BACKEND_DIR/.env"
    log "Created .env"
else
    sed -i "s/^PORT=.*/PORT=$PORT/" "$BACKEND_DIR/.env"
    log "Updated PORT in existing .env"
fi

# 4. Write ecosystem.config.js (only if not exists)
if [ ! -f "$BACKEND_DIR/ecosystem.config.js" ]; then
    cat > "$BACKEND_DIR/ecosystem.config.js" << ECOSYSTEM_EOF
module.exports = {
  apps: [{
    name: '$DOMAIN',
    script: './server.js',
    cwd: '$BACKEND_DIR',
    instances: 1,
    exec_mode: 'fork',
    env: {
      NODE_ENV: 'production',
      PORT: $PORT,
      HOST: '127.0.0.1'
    },
    error_file:          '$BACKEND_DIR/logs/err.log',
    out_file:            '$BACKEND_DIR/logs/out.log',
    log_file:            '$BACKEND_DIR/logs/combined.log',
    time:                true,
    autorestart:         true,
    max_restarts:        10,
    min_uptime:          '10s',
    watch:               false,
    kill_timeout:        5000,
    listen_timeout:      10000,
    max_memory_restart:  '512M'
  }]
};
ECOSYSTEM_EOF
    chown "$USER:$USER" "$BACKEND_DIR/ecosystem.config.js"
    chmod 644 "$BACKEND_DIR/ecosystem.config.js"
    log "Created ecosystem.config.js"
fi

# 5. Inject port into nginx configs
for conf in "$NGINX_CONF" "$NGINX_SSL_CONF"; do
    if [ -f "$conf" ]; then
        sed -i "s/NODEJS_PORT/$PORT/g" "$conf"
        log "Port injected into: $conf"
    fi
done

# 6. Set correct shell for user (needed for pm2 / su -)
if grep -q "^${USER}:.*nologin\|^${USER}:.*false" /etc/passwd 2>/dev/null; then
    chsh -s /bin/bash "$USER" 2>/dev/null || true
    log "Shell set to /bin/bash for $USER"
fi

log "--- Done: $DOMAIN → port $PORT ---"
log "Next: upload app to $BACKEND_DIR, then:"
log "  su - $USER -c 'pm2 start $BACKEND_DIR/ecosystem.config.js'"
exit 0
