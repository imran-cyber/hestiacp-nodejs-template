#!/bin/bash
# =============================================================================
# HestiaCP Node.js Template Installer - Fixed v3.0
# Tested: HestiaCP 1.9.x | Ubuntu 20.04/22.04/24.04 | Debian 11/12
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL_DIR="/usr/local/hestia/data/templates/web/nginx/php-fpm"
PORT_DB="$TPL_DIR/nodejs-ports.db"
LOG_FILE="/var/log/hestiacp-nodejs-install.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log()     { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info()    { echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"; }
warning() { echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"; }
header()  {
    echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}${BOLD}  $*${NC}"
    echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================
header "PRE-FLIGHT CHECKS"

[ "$EUID" -ne 0 ] && { error "Must run as root. Use: sudo -i"; exit 1; }
success "Running as root"

# OS check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu|debian) success "OS: $NAME $VERSION_ID" ;;
        *) error "Unsupported OS: $ID. Use Ubuntu or Debian."; exit 1 ;;
    esac
else
    error "Cannot detect OS"; exit 1
fi

# HestiaCP check
[ ! -d "/usr/local/hestia" ] && { error "HestiaCP not found at /usr/local/hestia"; exit 1; }
success "HestiaCP installation found"

# ----- FIX 1: Robust version detection -----
# v-list-sys-info output format varies by HestiaCP version.
# We try multiple methods to extract the version safely.
HESTIA_VERSION=""

# Method 1: from hestia.conf
if [ -f /usr/local/hestia/conf/hestia.conf ]; then
    HESTIA_VERSION=$(grep "^VERSION=" /usr/local/hestia/conf/hestia.conf 2>/dev/null | cut -d"'" -f2 || true)
fi

# Method 2: from the binary itself
if [ -z "$HESTIA_VERSION" ]; then
    HESTIA_VERSION=$(cat /usr/local/hestia/conf/hestia.conf 2>/dev/null | grep VERSION | head -1 | tr -d "VERSION='" || true)
fi

# Method 3: fallback
if [ -z "$HESTIA_VERSION" ]; then
    HESTIA_VERSION="unknown"
fi

info "HestiaCP Version: $HESTIA_VERSION"

# ----- FIX 2: Robust web/proxy system detection -----
# v-list-sys-config output is space-separated; awk on $2 is unreliable
# when the value is in column 1 or when output format changes.
WEB_SYSTEM=""
PROXY_SYSTEM=""

if [ -f /usr/local/hestia/conf/hestia.conf ]; then
    WEB_SYSTEM=$(grep   "^WEB_SYSTEM="   /usr/local/hestia/conf/hestia.conf | cut -d"'" -f2 || true)
    PROXY_SYSTEM=$(grep "^PROXY_SYSTEM=" /usr/local/hestia/conf/hestia.conf | cut -d"'" -f2 || true)
fi

# Fallback: try the CLI
if [ -z "$WEB_SYSTEM" ]; then
    WEB_SYSTEM=$(/usr/local/hestia/bin/v-list-sys-config plain 2>/dev/null | grep "^WEB_SYSTEM" | awk '{print $2}' || true)
fi
if [ -z "$PROXY_SYSTEM" ]; then
    PROXY_SYSTEM=$(/usr/local/hestia/bin/v-list-sys-config plain 2>/dev/null | grep "^PROXY_SYSTEM" | awk '{print $2}' || true)
fi

info "Web System: ${WEB_SYSTEM:-not detected}"
info "Proxy System: ${PROXY_SYSTEM:-not detected}"

if [ -n "$WEB_SYSTEM" ] && [ "$WEB_SYSTEM" != "nginx" ]; then
    error "Web system must be 'nginx'. Found: $WEB_SYSTEM"
    exit 1
fi

if [ "$PROXY_SYSTEM" = "apache2" ]; then
    error "Apache2 proxy detected. Disable it first."
    exit 1
fi

success "Nginx + PHP-FPM mode confirmed"

# Template directory
[ ! -d "$TPL_DIR" ] && { error "Template directory not found: $TPL_DIR"; exit 1; }
success "Template directory: $TPL_DIR"

# Required binaries
for cmd in nginx node npm; do
    if command -v "$cmd" &>/dev/null; then
        success "$cmd: $(command -v $cmd)"
    else
        warning "$cmd not found — install it before starting apps"
    fi
done

# PM2 check (warn, don't abort — user may install it later)
if command -v pm2 &>/dev/null; then
    success "pm2: $(command -v pm2)"
else
    warning "PM2 not found. Install with: npm install -g pm2"
    warning "You need PM2 to run Node.js apps. Continuing install..."
fi

# =============================================================================
# BACKUP
# =============================================================================
header "BACKUP PHASE"

BACKUP_DIR="$TPL_DIR/backups.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
info "Backup directory: $BACKUP_DIR"

for file in nodejs.tpl nodejs.stpl nodejs.sh; do
    if [ -f "$TPL_DIR/$file" ]; then
        cp "$TPL_DIR/$file" "$BACKUP_DIR/$file"
        success "Backed up: $file"
    fi
done

if [ -f "$PORT_DB" ]; then
    cp "$PORT_DB" "$BACKUP_DIR/nodejs-ports.db"
    success "Backed up: nodejs-ports.db"
fi

cat > "$BACKUP_DIR/restore.sh" << 'RESTORE_EOF'
#!/bin/bash
BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL_DIR="/usr/local/hestia/data/templates/web/nginx/php-fpm"
echo "Restoring from: $BACKUP_DIR"
for file in nodejs.tpl nodejs.stpl nodejs.sh; do
    [ -f "$BACKUP_DIR/$file" ] && cp "$BACKUP_DIR/$file" "$TPL_DIR/$file" && echo "Restored: $file"
done
[ -f "$BACKUP_DIR/nodejs-ports.db" ] && cp "$BACKUP_DIR/nodejs-ports.db" "$TPL_DIR/nodejs-ports.db"
nginx -t && systemctl restart nginx
echo "Restore complete!"
RESTORE_EOF
chmod +x "$BACKUP_DIR/restore.sh"
success "Emergency restore script created"

# =============================================================================
# PORT REGISTRY
# =============================================================================
header "PORT REGISTRY SETUP"

if [ ! -f "$PORT_DB" ]; then
    touch "$PORT_DB"
    chmod 644 "$PORT_DB"
    success "Created port registry: $PORT_DB"
else
    success "Port registry exists: $PORT_DB"
    if [ -s "$PORT_DB" ]; then
        info "Current allocations:"
        while IFS= read -r line; do echo "  $line"; done < "$PORT_DB"
    fi
fi

# =============================================================================
# INSTALL TEMPLATES
# =============================================================================
header "TEMPLATE INSTALLATION"

# --- nodejs.tpl (HTTP) ---
info "Installing nodejs.tpl (HTTP)..."
cp "$SCRIPT_DIR/nodejs.tpl" "$TPL_DIR/nodejs.tpl"
chmod 644 "$TPL_DIR/nodejs.tpl"
success "nodejs.tpl installed"

# --- nodejs.stpl (HTTPS) ---
info "Installing nodejs.stpl (HTTPS)..."
cp "$SCRIPT_DIR/nodejs.stpl" "$TPL_DIR/nodejs.stpl"
chmod 644 "$TPL_DIR/nodejs.stpl"
success "nodejs.stpl installed"

# --- nodejs.sh (dynamic config) ---
info "Installing nodejs.sh (port allocator)..."
cp "$SCRIPT_DIR/nodejs.sh" "$TPL_DIR/nodejs.sh"
chmod 755 "$TPL_DIR/nodejs.sh"
success "nodejs.sh installed"

# =============================================================================
# AUTO-FIX: Remove conflicting ssl_session_cache from all domain confs
# =============================================================================
# HestiaCP's nginx.conf already declares: shared:SSL:20m (globally)
# If any domain conf also declares it (different size), nginx will refuse
# to start. We remove the duplicate from every domain ssl conf before
# testing, so the global setting takes effect cleanly.
# =============================================================================
header "AUTO-FIX: SSL SESSION CACHE CONFLICT"

NGINX_DOMAINS_DIR="/etc/nginx/conf.d/domains"
FIXED_COUNT=0

if [ -d "$NGINX_DOMAINS_DIR" ]; then
    for conf in "$NGINX_DOMAINS_DIR"/*.ssl.conf; do
        [ -f "$conf" ] || continue
        if grep -q "ssl_session_cache.*shared:SSL" "$conf" 2>/dev/null; then
            sed -i '/ssl_session_cache.*shared:SSL/d' "$conf"
            info "Fixed: $(basename $conf)"
            FIXED_COUNT=$((FIXED_COUNT + 1))
        fi
    done
fi

if [ "$FIXED_COUNT" -gt 0 ]; then
    success "Removed duplicate ssl_session_cache from $FIXED_COUNT domain conf(s)"
else
    success "No ssl_session_cache conflicts found"
fi

# =============================================================================
# NGINX VALIDATION
# =============================================================================
header "NGINX VALIDATION"

info "Testing nginx configuration..."
if nginx -t 2>&1 | tee -a "$LOG_FILE"; then
    success "Nginx configuration is valid"
else
    error "Nginx config test FAILED — restoring backups..."
    bash "$BACKUP_DIR/restore.sh"
    exit 1
fi

# =============================================================================
# REGISTER & RESTART
# =============================================================================
header "HESTIACP REGISTRATION"

systemctl restart nginx
success "Nginx restarted"

systemctl restart hestia 2>/dev/null || true
success "HestiaCP restarted"

sleep 2

if /usr/local/hestia/bin/v-list-web-templates 2>/dev/null | grep -qi "nodejs"; then
    success "Template 'NodeJS' visible in HestiaCP"
else
    warning "Template not auto-detected yet. Try refreshing the HestiaCP panel."
fi

# =============================================================================
# SUMMARY
# =============================================================================
header "INSTALLATION COMPLETE"

echo -e "
${GREEN}${BOLD}✅ HestiaCP Node.js Template installed successfully!${NC}

${CYAN}📁 Template files:${NC}
   $TPL_DIR/nodejs.tpl
   $TPL_DIR/nodejs.stpl
   $TPL_DIR/nodejs.sh

${CYAN}📋 Port registry:${NC}
   $PORT_DB

${CYAN}💾 Backup + restore script:${NC}
   $BACKUP_DIR/restore.sh

${CYAN}🚀 Next steps:${NC}
   1. HestiaCP Panel → Web → Add Web Domain
      → Advanced Options → Web Template NGINX: ${YELLOW}NodeJS${NC}
      → Enable SSL + Let's Encrypt

   2. Upload your Node.js app to:
      /home/USERNAME/web/DOMAIN/nodeapp/

   3. Start with PM2 (as the domain user):
      ${YELLOW}cd ~/web/DOMAIN/nodeapp && pm2 start ecosystem.config.js${NC}

${CYAN}📖 Docs:${NC}
   $SCRIPT_DIR/docs/MULTI_APP_GUIDE.md

${YELLOW}⚠️  NOTE:${NC} Your app MUST listen on process.env.PORT (not a hardcoded port).
"

info "Installed files:"
ls -la "$TPL_DIR/nodejs"*
