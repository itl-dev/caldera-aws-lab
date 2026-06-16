#!/bin/bash
# ============================================================
#  CALDERA v5 server bootstrap (Ubuntu 22.04, runs as root)
#  - installs deps, clones CALDERA, runs it as a systemd service
#  - systemd => survives the Learner Lab stop/start between sessions
# ============================================================
set -uxo pipefail
exec > /var/log/caldera-bootstrap.log 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git python3 python3-pip python3-venv golang-go curl

# Node.js 20 (CALDERA v5 'magma' Vite build requires Node 20.19+, NOT 18)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# --- fetch CALDERA ---
cd /opt
if [ ! -d /opt/caldera ]; then
  git clone https://github.com/mitre/caldera.git --recursive
fi
cd /opt/caldera

# --- python venv + deps ---
python3 -m venv /opt/caldera/venv
/opt/caldera/venv/bin/pip install --upgrade pip wheel
/opt/caldera/venv/bin/pip install -r requirements.txt

# --- systemd unit (auto-restart, auto-start after reboot/session restart) ---
cat > /etc/systemd/system/caldera.service <<'UNIT'
[Unit]
Description=MITRE CALDERA
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/caldera
# --insecure uses conf/default.yml (default creds red/admin, admin/admin; API key ADMIN123)
# --build rebuilds the UI on start; reliable but adds a few minutes to first boot
ExecStart=/opt/caldera/venv/bin/python3 server.py --insecure --build
Restart=on-failure
RestartSec=10
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# HOME/GOPATH/GOCACHE are REQUIRED: CALDERA compiles the sandcat agent on demand
# with `go build`, which fails under systemd if $HOME is unset (no build cache / module dir).
Environment=HOME=/root
Environment=GOPATH=/root/go
Environment=GOCACHE=/root/.cache/go-build

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now caldera.service

# --- Caddy reverse proxy: expose the UI on 443 (HTTPS) so a browser can reach it
#     through firewalls that only allow 443 — NO local tooling needed on the client.
#     Self-signed (tls internal): the browser shows a one-time cert warning. ---
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy

cat > /etc/caddy/Caddyfile <<'CADDY'
{
	# self-signed local CA; no ACME/Let's Encrypt dependency (robust offline)
	auto_https disable_redirects
}
:443 {
	tls internal
	reverse_proxy localhost:8888
}
CADDY

systemctl enable caddy
systemctl restart caddy

echo "CALDERA bootstrap finished. UI: https://<public-ip> (self-signed) or SSM port-forward. Tail: journalctl -u caldera -f"
