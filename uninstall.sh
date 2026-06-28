#!/bin/bash
# =============================================================================
# HestiaCP Node.js Template Uninstaller v3.0
# =============================================================================

set -euo pipefail

TPL_DIR="/usr/local/hestia/data/templates/web/nginx/php-fpm"
PORT_DB="$TPL_DIR/nodejs-ports.db"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'; BOLD='\033[1m'

[ "$EUID" -ne 0 ] && { echo -e "${RED}Must run as root.${NC}"; exit 1; }

echo -e "${YELLOW}${BOLD}⚠️  This will remove the NodeJS template from HestiaCP.${NC}"
echo    "   Your Node.js app files will NOT be deleted."
echo
read -p "Continue? (y/N): " -n 1 -r; echo
[[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Aborted."; exit 0; }

echo -e "${GREEN}Removing template files...${NC}"
rm -f "$TPL_DIR/nodejs.tpl" "$TPL_DIR/nodejs.stpl" "$TPL_DIR/nodejs.sh"
echo "  ✅ Removed nodejs.tpl, nodejs.stpl, nodejs.sh"

echo -e "${YELLOW}Port registry ($PORT_DB) preserved. Delete manually if needed.${NC}"

nginx -t && systemctl restart nginx && echo "  ✅ Nginx restarted"
systemctl restart hestia 2>/dev/null || true && echo "  ✅ HestiaCP restarted"

echo -e "\n${GREEN}${BOLD}✅ Uninstall complete.${NC}"
echo    "   Domains still using the NodeJS template will show 502 until switched to another template."
echo    "   Use HestiaCP Panel → Web → Edit Domain → Web Template to change them."
