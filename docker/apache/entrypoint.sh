#!/bin/sh
set -eu

: "${BASE_DOMAIN:?BASE_DOMAIN is required}"
: "${APACHE_INDEXES:=on}"

BASE_DOMAIN="$(printf '%s' "$BASE_DOMAIN" | tr -d '[:space:]' | sed 's/\.$//')"
CONF="/usr/local/apache2/conf/extra/storage.conf"

case "$APACHE_INDEXES" in
  on|ON|true|1)
    INDEX_OPT="Indexes"
    ;;
  off|OFF|false|0)
    INDEX_OPT="-Indexes"
    ;;
  *)
    echo "Invalid APACHE_INDEXES value: $APACHE_INDEXES (use on/off)"
    exit 1
    ;;
esac

cat > "$CONF" <<EOF
<VirtualHost *:80>
    ServerName storage.local
    ServerAlias *.${BASE_DOMAIN}

    UseCanonicalName Off
    VirtualDocumentRoot "/var/www/%1"

    <Directory "/var/www">
        Options $INDEX_OPT
        AllowOverride None
        Require all granted
        DirectoryIndex disabled
        IndexIgnore .*
    </Directory>
</VirtualHost>
EOF

exec httpd-foreground
