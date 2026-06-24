#!/bin/bash
# Prune + compact the Borg repository.
# Runs ON THE BACKUP HOST (locally), because the data host's key is append-only
# and therefore cannot delete anything. Schedule via cron (see docs/backups.md).
set -uo pipefail

# ---- configure ----
REPO="/path/to/borg-repo"          # local path to the repository on this host
# For an ENCRYPTED repo also export the passphrase, e.g.:
# export BORG_PASSCOMMAND="cat /path/to/passphrase"
# -------------------

LOG="$(dirname "$REPO")/borg-prune.log"
exec >>"$LOG" 2>&1

echo "===== $(date -Is) prune start ====="
borg prune --list --stats \
    --glob-archives '*-data-*' \
    --keep-within=2d --keep-daily=7 --keep-weekly=4 --keep-monthly=6 \
    "$REPO"
prc=$?
borg compact "$REPO"
crc=$?
echo "===== $(date -Is) prune end prune_rc=$prc compact_rc=$crc ====="
exit $(( prc | crc ))
