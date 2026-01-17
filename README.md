# filestorage

A small, practical “static file server” for a Linux server/VPS:

- **Caddy on the host** terminates HTTPS and proxies to localhost.
- **Apache in Docker** serves folders from a host-mounted `data/` directory.
- Hostname → folder mapping is automatic:
  - `vse.<BASE_DOMAIN>` → `data/vse`
  - `vladivostok.<BASE_DOMAIN>` → `data/vladivostok`
- An **admin subdomain** (e.g. `dina.<BASE_DOMAIN>`) shows the entire storage root and is protected by **HTTP Basic Auth implemented in Apache**.

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

# user subdomains listing:
APACHE_INDEXES=on  # on/off (case-insensitive)

# admin domain (always lists the whole storage root)
ADMIN_SUBDOMAIN=dina
ADMIN_AUTH_USER=dina
ADMIN_AUTH_PASS=strong-password-here
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
dina.example.com {
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

- user sites: `VirtualDocumentRoot "/var/www/%1"`
- admin site: `DocumentRoot "/var/www"`

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

Important: the admin domain **always shows directory listing**, regardless of `APACHE_INDEXES`.

### Permission model (important detail)

Apache worker processes drop privileges. This project automatically sets the Apache
worker UID/GID to match the owner of the mounted `/var/www` using:

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

Usually invalid `.env` values (for example `APACHE_INDEXES`). Check logs:

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
