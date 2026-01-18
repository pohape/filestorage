#!/bin/sh
set -eu

cd "$(dirname "$0")"

[ -f .env ] && . ./.env

FTP_ENABLED=""
PROFILES=""

if [ -n "${FTP_USER:-}" ] && [ -n "${FTP_PASS:-}" ] && [ -n "${FTP_FOLDER:-}" ]; then
    PROFILES="--profile ftp"
    FTP_ENABLED=1
fi

docker compose $PROFILES up -d "$@"

echo ""
echo "=== Running services ==="
echo ""
echo "HTTP:"
echo "  https://*.${BASE_DOMAIN}"
echo "  https://${ADMIN_SUBDOMAIN}.${BASE_DOMAIN} (admin)"
if [ -n "$FTP_ENABLED" ]; then
    FTP_IP=$(curl -s ifconfig.co)
    echo ""
    echo "FTP:"
    echo "  ftp://${FTP_IP}"
    echo "  User: ${FTP_USER}"
    echo "  Password: ${FTP_PASS}"
    echo "  Folder: ${FTP_FOLDER}"
fi
echo ""
