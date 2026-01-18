#!/bin/sh
set -eu

cd "$(dirname "$0")"

# Source .env if exists
[ -f .env ] && . ./.env

PROFILES=""

# Enable FTP profile if all FTP variables are set
if [ -n "${FTP_USER:-}" ] && [ -n "${FTP_PASS:-}" ] && [ -n "${FTP_FOLDER:-}" ]; then
    PROFILES="--profile ftp"
fi

docker compose $PROFILES up -d --build "$@"
