#!/bin/sh
set -eu

: "${BASE_DOMAIN:?BASE_DOMAIN is required}"
: "${ADMIN_SUBDOMAIN:?ADMIN_SUBDOMAIN is required}"
: "${ADMIN_AUTH_USER:?ADMIN_AUTH_USER is required}"
: "${ADMIN_AUTH_PASS:?ADMIN_AUTH_PASS is required}"
: "${APACHE_INDEXES:=on}"

BASE_DOMAIN="$(printf '%s' "$BASE_DOMAIN" | tr -d '[:space:]' | sed 's/\.$//')"
ADMIN_SUBDOMAIN="$(printf '%s' "$ADMIN_SUBDOMAIN" | tr -d '[:space:]')"
APACHE_INDEXES="$(printf '%s' "$APACHE_INDEXES" | tr '[:upper:]' '[:lower:]')"

case "$APACHE_INDEXES" in
  on|true|1)   INDEX_OPT="Indexes" ;;
  off|false|0) INDEX_OPT="-Indexes" ;;
  *) echo "Invalid APACHE_INDEXES value: $APACHE_INDEXES"; exit 1 ;;
esac

CONF="/usr/local/apache2/conf/extra/storage.conf"
RUNCONF="/usr/local/apache2/conf/extra/run.conf"
HTPASSWD="/usr/local/apache2/conf/.htpasswd"

# 1) Запускаем воркеры Apache под владельцем смонтированного /var/www
RUN_UID="$(stat -c %u /var/www)"
RUN_GID="$(stat -c %g /var/www)"
cat > "$RUNCONF" <<EOF
User #${RUN_UID}
Group #${RUN_GID}
EOF
htpasswd -bcB "$HTPASSWD" "$ADMIN_AUTH_USER" "$ADMIN_AUTH_PASS"

cat > "$CONF" <<EOF
<VirtualHost *:80>
    ServerName ${ADMIN_SUBDOMAIN}.${BASE_DOMAIN}
    DocumentRoot "/var/www"

    <Directory "/var/www">
        Options Indexes
        AllowOverride None
        Require valid-user

        AuthType Basic
        AuthName "Storage Admin"
        AuthUserFile "${HTPASSWD}"

        DirectoryIndex disabled
        IndexIgnore .*
    </Directory>
</VirtualHost>

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
