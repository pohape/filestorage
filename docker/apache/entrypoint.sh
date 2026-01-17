#!/bin/sh
set -eu

: "${BASE_DOMAINS:?BASE_DOMAINS is required (comma-separated)}"

CONF="/usr/local/apache2/conf/extra/storage.conf"

# ServerAlias lines for each base domain
ALIASES=""
OLD_IFS="$IFS"
IFS=","
for d in $BASE_DOMAINS; do
  d="$(echo "$d" | tr -d '[:space:]' | sed 's/\.$//')"
  [ -n "$d" ] || continue
  ALIASES="${ALIASES}    ServerAlias *.${d}\n"
done
IFS="$OLD_IFS"

cat > "$CONF" <<EOF
<VirtualHost *:80>
    ServerName storage.local
$(printf "%b" "$ALIASES")

    UseCanonicalName Off
    VirtualDocumentRoot "/var/www/%1"

    <Directory "/var/www">
        Options Indexes
        AllowOverride None
        Require all granted
        DirectoryIndex disabled
        IndexIgnore .*
    </Directory>
</VirtualHost>
EOF

exec httpd-foreground
