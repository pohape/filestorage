#!/bin/sh
set -eu

: "${FTP_USER:?FTP_USER is required}"
: "${FTP_PASS:?FTP_PASS is required}"
: "${FTP_FOLDER:?FTP_FOLDER is required}"

FTP_ROOT="/mnt/data/${FTP_FOLDER}"

if [ ! -d "$FTP_ROOT" ]; then
    echo "Error: Directory $FTP_ROOT does not exist"
    exit 1
fi

# Match UID/GID to mounted volume owner
RUN_UID="$(stat -c %u "$FTP_ROOT")"
RUN_GID="$(stat -c %g "$FTP_ROOT")"

# Create FTP user with correct UID/GID
addgroup -g "$RUN_GID" ftpgroup 2>/dev/null || true
adduser -D -h "$FTP_ROOT" -u "$RUN_UID" -G ftpgroup "$FTP_USER" 2>/dev/null || true
echo "$FTP_USER:$FTP_PASS" | chpasswd

# Generate vsftpd config
cat > /etc/vsftpd/vsftpd.conf <<EOF
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=21100
pasv_max_port=21102
seccomp_sandbox=NO
background=NO
EOF

exec vsftpd /etc/vsftpd/vsftpd.conf
