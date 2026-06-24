#!/bin/bash
# Off-site BorgBackup of the filestorage data directory.
# Runs on the DATA host (the server that holds /data), normally via a systemd timer.
#
# Configuration is read from the project's docker/.env (the same DATA_DIR used by
# docker-compose), so there is a single source of truth. Pruning is intentionally
# NOT done here: the SSH key below is append-only, so a compromised data host
# cannot erase backup history. Pruning runs on the backup host (see prune.sh).
set -uo pipefail

# Path to the filestorage checkout that contains docker/.env (override via env if needed).
PROJECT_DIR="${PROJECT_DIR:-/path/to/filestorage}"
ENV_FILE="$PROJECT_DIR/docker/.env"

# Load config from docker/.env: DATA_DIR (required) and, optionally, BORG_REPO / BORG_SSH_KEY.
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

# DATA_DIR in .env is relative to docker/ (for docker-compose) — resolve to an absolute path.
DATA_DIR_ABS="$(cd "$PROJECT_DIR/docker" && cd "$DATA_DIR" && pwd)"

: "${BORG_REPO:?set BORG_REPO in docker/.env (backup_user@backup_host:/path/to/repo)}"
BORG_SSH_KEY="${BORG_SSH_KEY:-/etc/borg/borg_key}"

export BORG_REPO
export BORG_RSH="ssh -i ${BORG_SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

# Required for an UNENCRYPTED repo so the first non-interactive run is not blocked
# by borg's "unknown unencrypted repository" prompt. Harmless when encrypted.
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
# For an ENCRYPTED repo, also provide the passphrase (see docs/backups.md), e.g.:
# export BORG_PASSCOMMAND="cat /etc/borg/passphrase"

LOG=/var/log/borg-backup.log
exec >>"$LOG" 2>&1

echo "===== $(date -Is) backup start (source: $DATA_DIR_ABS) ====="
borg create \
    --verbose --stats --show-rc \
    --compression zstd,6 \
    --exclude-caches \
    "::$(hostname -s)-data-{now:%Y-%m-%dT%H:%M:%S}" \
    "$DATA_DIR_ABS"
rc=$?
echo "===== $(date -Is) backup end rc=$rc ====="
exit $rc
