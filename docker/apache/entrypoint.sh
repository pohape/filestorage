#!/bin/bash
set -eu

: "${BASE_DOMAIN:?BASE_DOMAIN is required}"
: "${ADMIN_SUBDOMAIN:?ADMIN_SUBDOMAIN is required}"
: "${ADMIN_AUTH_USER:?ADMIN_AUTH_USER is required}"
: "${ADMIN_AUTH_PASS:?ADMIN_AUTH_PASS is required}"
: "${PUBLIC_LISTING:=on}"
: "${FILEMANAGER_LANG:=en}"

BASE_DOMAIN="$(printf '%s' "$BASE_DOMAIN" | tr -d '[:space:]' | sed 's/\.$//')"
ADMIN_SUBDOMAIN="$(printf '%s' "$ADMIN_SUBDOMAIN" | tr -d '[:space:]')"
PUBLIC_LISTING="$(printf '%s' "$PUBLIC_LISTING" | tr '[:upper:]' '[:lower:]')"
FILEMANAGER_LANG="$(printf '%s' "$FILEMANAGER_LANG" | tr '[:upper:]' '[:lower:]')"
DOLLAR='$'

CONF="/etc/apache2/sites-available/storage.conf"
HTPASSWD="/etc/apache2/.htpasswd"
FILEMANAGER="/var/www/html/filemanager.php"

# Create htpasswd with admin user
htpasswd -bcB "$HTPASSWD" "$ADMIN_AUTH_USER" "$ADMIN_AUTH_PASS"

# Add protected user if configured
if [ -n "${PROTECTED_SUBDOMAIN:-}" ] && [ -n "${PROTECTED_AUTH_USER:-}" ] && [ -n "${PROTECTED_AUTH_PASS:-}" ]; then
    htpasswd -bB "$HTPASSWD" "$PROTECTED_AUTH_USER" "$PROTECTED_AUTH_PASS"
fi

# Set Apache worker UID/GID to match data directory owner
RUN_UID="$(stat -c %u /data)"
RUN_GID="$(stat -c %g /data)"

sed -i "s/APACHE_RUN_USER=.*/APACHE_RUN_USER=#${RUN_UID}/" /etc/apache2/envvars
sed -i "s/APACHE_RUN_GROUP=.*/APACHE_RUN_GROUP=#${RUN_GID}/" /etc/apache2/envvars

# ============================================================
# ADMIN VirtualHost
# - File manager under Basic Auth, sees entire /data folder
# - Files also under Basic Auth at root (no /files prefix)
# ============================================================
cat > "$CONF" <<EOF
<VirtualHost *:80>
    ServerName ${ADMIN_SUBDOMAIN}.${BASE_DOMAIN}
    DocumentRoot "/data"

    SetEnv FILEMANAGER_MODE "admin"
    SetEnv FILEMANAGER_LANG "${FILEMANAGER_LANG}"
    SetEnv BASE_DOMAIN "${BASE_DOMAIN}"
    SetEnv ADMIN_SUBDOMAIN "${ADMIN_SUBDOMAIN}"

    # File manager script
    Alias /filemanager.php ${FILEMANAGER}

    # All files require auth
    <Directory "/data">
        Options -Indexes
        AllowOverride None
        Require valid-user

        AuthType Basic
        AuthName "Admin"
        AuthUserFile "${HTPASSWD}"

        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} -d
        RewriteRule ^(.*)$ /filemanager.php?path=${DOLLAR}1 [L,PT,QSA]
    </Directory>

    <Files "filemanager.php">
        AuthType Basic
        AuthName "Admin"
        AuthUserFile "${HTPASSWD}"
        Require valid-user
    </Files>

</VirtualHost>
EOF

# ============================================================
# PROTECTED VirtualHost (optional)
# - File manager under Basic Auth
# - Files accessible WITHOUT auth via direct links
# ============================================================
if [ -n "${PROTECTED_SUBDOMAIN:-}" ] && [ -n "${PROTECTED_AUTH_USER:-}" ] && [ -n "${PROTECTED_AUTH_PASS:-}" ]; then
PROTECTED_SUBDOMAIN="$(printf '%s' "$PROTECTED_SUBDOMAIN" | tr -d '[:space:]')"
cat >> "$CONF" <<EOF

<VirtualHost *:80>
    ServerName ${PROTECTED_SUBDOMAIN}.${BASE_DOMAIN}
    DocumentRoot "/data/${PROTECTED_SUBDOMAIN}"

    SetEnv FILEMANAGER_MODE "protected"
    SetEnv FILEMANAGER_LANG "${FILEMANAGER_LANG}"
    SetEnv BASE_DOMAIN "${BASE_DOMAIN}"

    # Alias for file manager
    Alias /filemanager.php ${FILEMANAGER}

    # File manager under Basic Auth
    <Location ~ "^/?$">
        AuthType Basic
        AuthName "Protected"
        AuthUserFile "${HTPASSWD}"
        Require valid-user
    </Location>

    <Files "filemanager.php">
        AuthType Basic
        AuthName "Protected"
        AuthUserFile "${HTPASSWD}"
        Require valid-user
    </Files>

    # Files - no auth required
    <Directory "/data/${PROTECTED_SUBDOMAIN}">
        Options -Indexes
        AllowOverride None
        Require all granted

        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} -d
        RewriteRule ^(.*)$ /filemanager.php?path=${DOLLAR}1 [L,PT,QSA]
    </Directory>
</VirtualHost>
EOF
fi

# ============================================================
# PUBLIC VirtualHost
# - File manager shown if PUBLIC_LISTING=on, hidden if off
# - Files always without auth
# ============================================================
cat >> "$CONF" <<EOF

<VirtualHost *:80>
    ServerName storage.local
    ServerAlias *.${BASE_DOMAIN}

    UseCanonicalName Off
    VirtualDocumentRoot "/data/%1"

    SetEnv FILEMANAGER_MODE "public"
    SetEnv FILEMANAGER_LANG "${FILEMANAGER_LANG}"
    SetEnv BASE_DOMAIN "${BASE_DOMAIN}"

    # Alias for file manager
    Alias /filemanager.php ${FILEMANAGER}

EOF

# Add file manager routing only if PUBLIC_LISTING is enabled
case "$PUBLIC_LISTING" in
    on|true|1)
cat >> "$CONF" <<EOF

    # Directories -> file manager (no auth)
    <Directory "/data">
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} -d
        RewriteRule ^(.*)$ /filemanager.php?path=${DOLLAR}1 [L,PT,QSA]
    </Directory>
EOF
    ;;
    *)
cat >> "$CONF" <<EOF

    # File manager disabled - return 403 for any directory request
    <Directory "/data">
        RewriteEngine On
        RewriteCond %{REQUEST_FILENAME} -d
        RewriteRule ^ - [F,L]
    </Directory>
EOF
    ;;
esac

cat >> "$CONF" <<EOF

    # Files - no auth required
    <Directory "/data">
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Disable default site, enable ours
a2dissite 000-default.conf 2>/dev/null || true
a2ensite storage.conf

# Start Apache
exec apache2-foreground
