#!/bin/sh
set -eu

cd "$(dirname "$0")/docker"

[ -f .env ] && . ./.env

PROFILES=""
if [ -n "${FTP_USER:-}" ] && [ -n "${FTP_PASS:-}" ] && [ -n "${FTP_FOLDER:-}" ]; then
    PROFILES="--profile ftp"
fi

docker compose $PROFILES build "$@"
