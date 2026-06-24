#!/bin/bash
# Off-site BorgBackup of the filestorage data directory.
# Runs on the DATA host (the server that holds the data dir), normally via a
# systemd timer. Configuration is read from the project's docker/.env (the same
# DATA_DIR used by docker-compose) so there is a single source of truth.
#
# Pruning is intentionally NOT done here: the SSH key below is append-only, so a
# compromised data host cannot erase backup history. Pruning runs on the backup
# host instead (see prune.sh and the "Off-site backups" section of the README).
set -uo pipefail

# Path to the filestorage checkout that contains docker/.env.
# Edit this, or pass it via the environment (e.g. systemd Environment=PROJECT_DIR=...).
PROJECT_DIR="${PROJECT_DIR:-/path/to/filestorage}"
ENV_FILE="$PROJECT_DIR/docker/.env"

[ -r "$ENV_FILE" ] || { echo "ERROR: cannot read $ENV_FILE (set PROJECT_DIR correctly)" >&2; exit 1; }

# Read one compose-style KEY=value from .env, without sourcing it (no shell
# execution, no secrets pulled into this process's environment).
env_get() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -n1 | tr -d '\r'; }

DATA_DIR="$(env_get DATA_DIR)"
BORG_REPO="${BORG_REPO:-$(env_get BORG_REPO)}"
BORG_SSH_KEY="${BORG_SSH_KEY:-$(env_get BORG_SSH_KEY)}"
BORG_SSH_KEY="${BORG_SSH_KEY:-/etc/borg/borg_key}"

: "${DATA_DIR:?DATA_DIR not found in $ENV_FILE}"
: "${BORG_REPO:?set BORG_REPO in docker/.env (backup_user@backup_host:/path/to/repo)}"

# DATA_DIR may be relative to docker/ (compose default: ../data) or absolute — resolve it.
DATA_DIR_ABS="$(cd "$PROJECT_DIR/docker" 2>/dev/null && cd "$DATA_DIR" 2>/dev/null && pwd)"
: "${DATA_DIR_ABS:?cannot resolve DATA_DIR='$DATA_DIR' to an existing directory}"

export BORG_REPO
export BORG_RSH="ssh -i ${BORG_SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

# Lets the first non-interactive run accept an UNENCRYPTED repo without prompting.
# Harmless when the repo is encrypted.
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
# For an ENCRYPTED repo, also provide the passphrase (see the README), e.g.:
# export BORG_PASSCOMMAND="cat /etc/borg/passphrase"

# Log to a file AND to the terminal/journal (so manual runs and `journalctl` both work).
LOG=/var/log/borg-backup.log
exec > >(tee -a "$LOG") 2>&1

echo "===== $(date -Is) backup start (source: $DATA_DIR_ABS) ====="
borg create \
    --verbose --stats --show-rc \
    --compression zstd,6 \
    --exclude-caches \
    "::$(hostname -s)-data-{now:%Y-%m-%dT%H:%M:%S}" \
    "$DATA_DIR_ABS"
rc=$?
echo "===== $(date -Is) backup end rc=$rc ====="
exit "$rc"
