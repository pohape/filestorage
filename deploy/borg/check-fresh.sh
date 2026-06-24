#!/bin/bash
# Print "FRESH ..." (exit 0) if the newest archive is younger than MAX_AGE_HOURS,
# otherwise "STALE ..." (exit 1). Designed for the uptime monitor's `commands:`
# section (search_string: "FRESH"). Runs ON THE BACKUP HOST.
set -uo pipefail

# ---- configure ----
REPO="/path/to/borg-repo"          # local path to the repository on this host
MAX_AGE_HOURS=8                    # backups run every 6h; older than this ⇒ stale
# For an ENCRYPTED repo also export the passphrase, e.g.:
# export BORG_PASSCOMMAND="cat /path/to/passphrase"
# -------------------

last=$(borg list --last 1 --format '{time}{NL}' "$REPO" 2>/dev/null | head -1)
[ -n "$last" ] || { echo "STALE: no archives in repo"; exit 1; }

last_epoch=$(date -d "$last" +%s 2>/dev/null) || { echo "STALE: cannot parse archive time '$last'"; exit 1; }
age_h=$(( ($(date +%s) - last_epoch) / 3600 ))

if [ "$age_h" -lt "$MAX_AGE_HOURS" ]; then
    echo "FRESH: last backup ${age_h}h ago"
else
    echo "STALE: last backup ${age_h}h ago (threshold ${MAX_AGE_HOURS}h)"
    exit 1
fi
