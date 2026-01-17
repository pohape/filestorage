#!/bin/sh
set -eu

: "${BASE_DOMAIN:?BASE_DOMAIN is required}"

BASE_DOMAIN="$(printf '%s' "$BASE_DOMAIN" | tr -d '[:space:]' | sed 's/\.$//')"
CONF="/usr/local/apache2/conf/extra/storage.conf"
BASE_RE="$(printf '%s' "$BASE_DOMAIN" | sed -e 's/[.[\^$*+?(){|}\\]/\\&/g' -e 's/\./\\./g')"

cat > "$CONF" <<EOF
<VirtualHost *:80>
    ServerName storage.local
    ServerAlias *.${BASE_DOMAIN}

    UseCanonicalName Off

    RewriteEngine On
    RewriteCond %{HTTP_HOST} !\\.${BASE_RE}\$ [NC]
    RewriteRule ^ - [R=404,L]

    # vladivostok.example.com -> /var/www/vladivostok
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
