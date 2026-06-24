# filestorage

A small, practical “static file server” for a Linux server/VPS:

- **Caddy on the host** terminates HTTPS and proxies to localhost.
- **Apache in Docker** serves folders from a host-mounted `data/` directory and powers a lightweight file manager.
- Hostname → folder mapping is automatic:
  - `vse.<BASE_DOMAIN>` → `data/vse`
  - `vladivostok.<BASE_DOMAIN>` → `data/vladivostok`
- An **admin subdomain** (e.g. `admin.<BASE_DOMAIN>`) shows the entire storage root and is protected by **HTTP Basic Auth**. Direct file links are available at the root (`/some/file.txt`), without `/files`. The admin file manager shows disk usage (used/free) with a progress bar.
- An optional **protected subdomain** (e.g. `vladivostok.<BASE_DOMAIN>`) shows a file manager under Basic Auth, while direct file links remain public (also without `/files`).

The container mounts your data **read-only**. Uploads/edits are done via SSH/SFTP on the host.

---

## Repository layout

```
Caddyfile.example
docker/
  docker-compose.yaml
  .env.example
  apache/
    Dockerfile
    entrypoint.sh
```

---

## Requirements

- Linux server/VPS
- DNS A/AAAA records for your subdomains pointing to the server
- Caddy installed on the host (ports 80/443)
- Docker Engine + Docker Compose v2

### Install Docker (Ubuntu)

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker $USER
# log out and back in so the group change applies
```

### Install Caddy (Ubuntu)

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | sudo tee /usr/share/keyrings/caddy-stable-archive-keyring.gpg >/dev/null
curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

---

## Quick start

### 1) Clone

```bash
cd ~
git clone https://github.com/pohape/filestorage
cd filestorage
```

### 2) Create your storage directory on the host

By default the compose file expects `../data` relative to `docker/docker-compose.yaml`,
so create `~/data` next to your repo (or change `DATA_DIR` in `.env`).

```bash
mkdir -p ~/data/vse ~/data/vladivostok
echo "hello" > ~/data/vse/test.txt
```

### 3) Configure `.env`

```bash
cd docker
cp .env.example .env
vim .env
chmod 600 .env
```

Example:

```dotenv
DATA_DIR=../data
BASE_DOMAIN=example.com

# file manager language (en/ru)
FILEMANAGER_LANG=en

# admin domain (always lists the whole storage root)
ADMIN_SUBDOMAIN=admin
ADMIN_AUTH_USER=admin
ADMIN_AUTH_PASS=strong-password-here

# protected subdomain with HTTP Basic Auth (optional)
PROTECTED_SUBDOMAIN=vladivostok
PROTECTED_AUTH_USER=vladivostok
PROTECTED_AUTH_PASS=strong-password-here

# public subdomain for shareable links (optional)
# if set, admin copy-links for that folder point to this public subdomain
PUBLIC_SUBDOMAIN=vse

# public subdomains file manager (on/off)
# on  = file manager is shown (no auth required)
# off = file manager is hidden, only direct file access works
PUBLIC_LISTING=on

```

### 4) Start Apache container

```bash
docker compose up -d --build
docker ps
docker logs apache --tail=50
```

Apache listens only on `127.0.0.1:8080` and is not exposed directly to the internet.

### 5) Configure Caddy on the host

Copy the example and edit it:

```bash
sudo cp ~/filestorage/Caddyfile.example /etc/caddy/Caddyfile
sudo vim /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Add your real domains. Example (explicit blocks):

```caddy
{
    email you@example.com
}

vladivostok.example.com {
    reverse_proxy 127.0.0.1:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}

vse.example.com {
    reverse_proxy 127.0.0.1:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}

# admin domain (Basic Auth is enforced by Apache, not by Caddy)
admin.example.com {
    reverse_proxy 127.0.0.1:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
```

---

## How it works

### Hostname → folder mapping

Apache uses `mod_vhost_alias` and:

- user sites: `VirtualDocumentRoot "/data/%1"`
- admin site: `DocumentRoot "/data"` with a file manager routed to directories

`%1` is the first label of the host name. For example:

- `vse.example.com` → `vse`
- `vladivostok.example.com` → `vladivostok`

So your host directory structure should be:

```
data/
  vse/
  vladivostok/
  ...
```

### Admin domain with Basic Auth (Apache-side)

The admin vhost is generated at container start and requires `Require valid-user`
with a bcrypt htpasswd file. Credentials are taken from `.env`.

Important: the admin domain **always shows the file manager**, regardless of `PUBLIC_LISTING`.

### Protected vs public subdomains

- **Protected** (`PROTECTED_SUBDOMAIN` set): root (`/`) shows the file manager under Basic Auth, while direct files are public.
- **Public** (any other subdomain): file manager at `/` only if `PUBLIC_LISTING=on`; direct files are always public.

### File manager URLs

The file manager uses “pretty” paths. Instead of `/?path=...` it shows directories like:

```
https://admin.example.com/Reports/2025/?sort=name&order=asc
```

### Admin disk usage

On the admin domain the file manager displays a usage bar based on `/data`:

- Used, free, and total space
- Percent used (progress bar)
Note: used space is calculated from the `/data` directory only (via `du`), so
other files on the same disk are not counted.

### Admin copy links for protected subdomain

If `PROTECTED_SUBDOMAIN` is set, the admin file manager will copy links for that
folder to the protected subdomain (e.g. `https://vladivostok.<BASE_DOMAIN>/...`)
so you can share links with non-admin users.

If `PUBLIC_SUBDOMAIN` is set, the admin file manager will copy links for that
folder to the public subdomain (e.g. `https://vse.<BASE_DOMAIN>/...`).

### Permission model (important detail)

Apache worker processes drop privileges. This project automatically sets the Apache
worker UID/GID to match the owner of the mounted `/data` using:

- `stat -c %u /var/www`
- `stat -c %g /var/www`

This is generated into `conf/extra/run.conf` by `docker/apache/entrypoint.sh`.

That avoids “works in shell but 403 in browser” permission issues, without loosening host permissions.

---

## Adding a new subdomain

1) Create a folder:

```bash
mkdir -p ~/data/new
```

2) Add a DNS record for `new.<BASE_DOMAIN>` pointing to the server.

3) Add a block in `/etc/caddy/Caddyfile` for the new hostname and reload Caddy:

```bash
sudo systemctl reload caddy
```

No Apache restart is needed for new folders (only when changing `.env`).

---

## SFTP / uploads (host-side)

Uploads are done via SSH/SFTP to the host filesystem (recommended).

Example: create a limited user who can upload only into `~/data/vladivostok`
(no chroot; only Unix permissions + a convenience symlink):

```bash
sudo groupadd -f storage
sudo useradd -m -s /bin/bash vladivostok
sudo usermod -aG storage $USER
sudo usermod -aG storage vladivostok

sudo chown -R $USER:storage /home/$USER/data/vladivostok
sudo chmod 2770 /home/$USER/data/vladivostok

# allow traversing but not listing your home/data directories
sudo chmod 751 /home/$USER
sudo chmod 751 /home/$USER/data

# entry point for the user
sudo ln -s /home/$USER/data/vladivostok /home/vladivostok/storage
```

User connects with:

```bash
sftp vladivostok@your-server
# then: cd storage
```

---

## Troubleshooting

### Caddy returns 502

Caddy cannot reach Apache on localhost.

```bash
docker ps
docker logs apache --tail=200
ss -ltnp | grep 8080
curl -i -H "Host: vse.<BASE_DOMAIN>" http://127.0.0.1:8080/
```

### Container restarting in a loop

Usually invalid `.env` values. Check logs:

```bash
docker logs apache --tail=200
```

### Port 8080 already in use

Change the host port in `docker/docker-compose.yaml`, e.g. `8081:80`,
and update Caddy upstream to `127.0.0.1:8081`.

---

## Security notes

- The web container mounts storage **read-only** by default.
- Keep `docker/.env` private (`chmod 600 docker/.env`), as it contains admin credentials.
- Prefer SSH keys over passwords for SFTP.
- For public deployments, consider adding rate limiting and access logs at the Caddy layer.

---

## Brute-force protection (fail2ban)

fail2ban runs on the **host** (it is not part of the Docker stack) and bans IPs
that repeatedly fail to authenticate over SSH and FTP.

FTP needs a small bit of plumbing: vsftpd runs in a container, so its auth log is
exposed to the host. The `ftp` container already writes
`/var/log/vsftpd/vsftpd.log` (own format, with `FAIL LOGIN` lines) and the compose
file bind-mounts that path to the host, so the host fail2ban can read it. SSH logs
are read straight from the systemd journal.

A ready-to-use config is provided in [`deploy/fail2ban/jail.local`](deploy/fail2ban/jail.local).
The `vsftpd` jail bans only the FTP ports (`20,21` + the passive range
`21100-21102`), **not** SSH — so a banned FTP client keeps its SSH session, and you
cannot lock yourself out of SSH while testing FTP. Legit logins are unaffected:
only failed auth is counted, so a correct password never accumulates bans.

### Install

```bash
# 1) make sure the ftp container is (re)built so it writes the host-mounted log
mkdir -p /var/log/vsftpd
cd docker && docker compose --profile ftp up -d --build ftp

# 2) install fail2ban on the host and drop in the config
sudo apt install -y fail2ban
sudo cp deploy/fail2ban/jail.local /etc/fail2ban/jail.local
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
```

### Verify

```bash
sudo fail2ban-client status            # should list: sshd, vsftpd
sudo fail2ban-client status vsftpd     # failed/banned counters
```

To test, attempt a few wrong-password FTP logins from another host: after
`maxretry` (5) within `findtime` (10m) the IP is banned for `bantime` (1h).
Unban manually with:

```bash
sudo fail2ban-client set vsftpd unbanip <IP>
```

---

## Off-site backups (BorgBackup) + monitoring

Automated, versioned, off-site backups of the data directory using
[BorgBackup](https://www.borgbackup.org/), with a freshness check wired into a
Telegram uptime monitor so you get alerted if backups stop running.

### Why Borg

- **Versioned snapshots** — restore the data as it was at any past point, not
  just "latest". A plain `rsync` mirror cannot do this: a deleted or corrupted
  file is gone from the mirror too.
- **Deduplication + compression** — dozens of snapshots of mostly-unchanged data
  cost barely more than one.
- **Append-only protection** — the data host can only *add* archives; it cannot
  delete history. So a compromised/ransomwared data host cannot destroy backups.
- **Optional encryption** — see below.

### Architecture

```
DATA host (this project)                         BACKUP host (big disk, off-site)
  /data  ──borg create (every 6h)──►  ssh ──►  borg repo  (append-only for the data host)
                                                  └─ prune + compact run locally here
```

- **Push from the data host** over SSH, on a systemd timer.
- The data host authenticates with a **dedicated, restricted SSH key** that can
  only run `borg serve --append-only` on the repo path — nothing else.
- **Pruning runs on the backup host**, locally, because the append-only key
  cannot delete. This keeps the deletion authority on the more-trusted side.

Ready-to-edit templates live in [`deploy/borg/`](deploy/borg):
`backup.sh`, `borg-backup.service`, `borg-backup.timer` (data host);
`prune.sh`, `check-fresh.sh` (backup host).

### Encryption: enable or disable

Borg can encrypt the repository or not. Choose at **repo creation time** with the
`--encryption` flag of `borg init`. This is the one decision to make up front.

| Mode | `borg init --encryption=` | Restore needs | Use when |
|---|---|---|---|
| **Off** | `none` | nothing — just `borg extract` | Data is not secret and you want the simplest, fastest recovery with no keys/passphrases to manage. |
| **On** | `repokey-blake2` | passphrase (key is stored *in* the repo) | Data is sensitive and the backup host is not fully trusted (e.g. third-party storage). |

**Unencrypted (`none`)** — simplest. No passphrase anywhere. The only extra step
is allowing non-interactive access (already handled by `backup.sh`, which exports
`BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes`).

**Encrypted (`repokey-blake2`)** — every `borg` command that touches the repo
needs the passphrase. Provide it via `BORG_PASSCOMMAND` (uncomment the line in
`backup.sh`, `prune.sh`, `check-fresh.sh`), e.g. store it in `/etc/borg/passphrase`
(`chmod 600`). **Keep the passphrase and an exported copy of the key
(`borg key export`) somewhere safe and separate — without them the backup is
unrecoverable.**

> You can't flip encryption on an existing repo — re-init a fresh one and back up
> again.

### Setup

#### 1. Install Borg (both hosts)

```bash
sudo apt install -y borgbackup        # Debian/Ubuntu
```

#### 2. Dedicated SSH key (data host → backup host)

On the **data host**, create a key used *only* for backups:

```bash
sudo mkdir -p /etc/borg
sudo ssh-keygen -t ed25519 -N "" -f /etc/borg/borg_key -C "borg@$(hostname -s)"
sudo cat /etc/borg/borg_key.pub
```

On the **backup host**, add that public key to `~/.ssh/authorized_keys` **with a
forced, restricted command** so it can do nothing but append to the repo:

```
command="borg serve --append-only --restrict-to-path /path/to/borg-repo",restrict ssh-ed25519 AAAA... borg@datahost
```

`restrict` disables PTY/agent/port forwarding; `--append-only` blocks deletion;
`--restrict-to-path` confines it to the repo location (subdirectories included).

#### 3. Repository layout + init (backup host)

Keep the repo and its helper scripts together, but the scripts **outside** the
repo directory (Borg manages the repo dir — don't drop files inside it):

```
/path/to/borg-repo/
├── repo/            ← the Borg repository itself
├── prune.sh
├── check-fresh.sh
└── *.log
```

Initialize the repository — pick the encryption mode (see table above):

```bash
borg init --encryption=none          /path/to/borg-repo/repo   # unencrypted
# or
borg init --encryption=repokey-blake2 /path/to/borg-repo/repo  # encrypted
```

> The `--restrict-to-path` above points at `/path/to/borg-repo`, which covers the
> `repo/` subdirectory.

#### 4. Backup script + timer (data host)

1. Add the destination to the project's `docker/.env`:

   ```dotenv
   BORG_REPO=backup_user@backup_host:/path/to/borg-repo/repo
   BORG_SSH_KEY=/etc/borg/borg_key
   ```

   `backup.sh` reads `DATA_DIR` from the same `docker/.env` (resolving the
   compose-relative `../data` to an absolute path), so there's one source of truth.

2. Install the script and units:

   ```bash
   sudo install -m 750 deploy/borg/backup.sh /usr/local/bin/borg-backup.sh
   # set PROJECT_DIR inside the script to your checkout path
   sudo cp deploy/borg/borg-backup.service deploy/borg/borg-backup.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now borg-backup.timer
   ```

3. Run once by hand to verify:

   ```bash
   sudo /usr/local/bin/borg-backup.sh
   sudo systemctl list-timers borg-backup.timer
   ```

#### 5. Prune + compact (backup host)

Retention is applied locally on the backup host (the data host can't delete).
Edit `REPO` in `deploy/borg/prune.sh`, install it next to the repo, and schedule
it daily at a time that doesn't overlap a backup:

```cron
30 3 * * * /path/to/borg-repo/prune.sh
```

Default policy (in `prune.sh`): keep everything from the **last 2 days** (all
intraday runs), then **7 daily**, **4 weekly**, **6 monthly**. `borg compact`
afterwards actually frees the pruned space.

### Restore

List archives and restore — on the backup host (fast, local) or from anywhere
with repo access:

```bash
borg list  /path/to/borg-repo/repo                       # all snapshots
borg list  /path/to/borg-repo/repo::ARCHIVE              # files in one snapshot

# extract a whole snapshot (into ./<paths>) ...
cd /tmp/restore && borg extract /path/to/borg-repo/repo::ARCHIVE
# ... or a single file/subdir:
borg extract /path/to/borg-repo/repo::ARCHIVE path/inside/data/file.txt

# browse interactively:
borg mount /path/to/borg-repo/repo /mnt/borg && ls /mnt/borg
```

(With an **encrypted** repo, every command above also needs the passphrase.)

### Monitoring: alert if backups stop

Use a self-hosted [uptime monitor with Telegram alerts](https://github.com/pohape/self-hosted-tg-alerts-uptime-monitor).
Its `commands:` checks run a shell command and alert when the command exits
non-zero **or** its output doesn't contain `search_string` — and send a RESTORE
message once it recovers.

`deploy/borg/check-fresh.sh` prints `FRESH ...` (exit 0) when the newest archive
is younger than `MAX_AGE_HOURS` (default 8h — one missed 6-hourly run is
tolerated, a sustained outage is not), otherwise `STALE ...` (exit 1).

Install it on the **backup host** (where the repo is local) and add a check to the
monitor's `config.yaml`:

```yaml
commands:
  filestorage_backup_fresh:
    command: "/path/to/borg-repo/check-fresh.sh"
    search_string: "FRESH"
    schedule: "0 1,7,13,19 * * *"   # ~1h after each 6-hourly backup window
    timeout: 60
    tg_chats_to_notify:
      - 'YOUR_TELEGRAM_CHAT_ID'
```

If a backup run fails or the timer stops, no new archive appears, the script goes
`STALE`, and the monitor sends a Telegram alert; when backups resume it sends a
recovery notice. For an encrypted repo, set `BORG_PASSCOMMAND` in `check-fresh.sh`
too.
