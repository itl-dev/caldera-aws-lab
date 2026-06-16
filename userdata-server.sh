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
# NOTE: do NOT install Ubuntu's `golang-go` here — on 22.04 it is Go 1.18.1, which is
# BELOW CALDERA's required minimum (go >= 1.19, see conf/default.yml). With an old Go,
# CALDERA logs "go does not meet the minimum version of 1.19" and the on-demand sandcat
# compile is unreliable on first boot, so victims time out before the agent registers.
apt-get install -y git python3 python3-pip python3-venv curl tar

# Node.js 20 (CALDERA v5 'magma' Vite build requires Node 20.19+, NOT 18)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Go (>= 1.19) from the official tarball, so CALDERA can compile the sandcat agent.
# Fetch the current stable version string (e.g. go1.23.4) so we never pin a release
# that may not exist; install to /usr/local/go and symlink into /usr/local/bin, which
# is already on the systemd unit's PATH below.
GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)"
curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tgz
rm -rf /usr/local/go
tar -C /usr/local -xzf /tmp/go.tgz
ln -sf /usr/local/go/bin/go /usr/local/bin/go
ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
/usr/local/bin/go version

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
#     Self-signed cert: the browser shows a one-time cert warning ("proceed"). ---
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt-get update -y
apt-get install -y caddy

# Generate an explicit self-signed cert and hand it to Caddy directly.
#   WHY NOT `tls internal`: on a hostname-less `:443` site, Caddy's internal issuer
#   has no name to pre-issue a cert for and won't mint one on-demand for an arbitrary
#   IP/SNI. Connecting by the EC2 public IP then yields NO certificate and a TLS
#   "internal error" alert -> the browser shows "This site can't provide a secure
#   connection" with no way to proceed (not the intended cert *warning*).
#   An explicit cert file is always presented regardless of SNI/IP, so the browser
#   gets the expected one-time self-signed warning and can proceed.
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PUBIP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout /etc/caddy/caldera.key -out /etc/caddy/caldera.crt -days 3650 \
  -subj "/CN=caldera-lab" -addext "subjectAltName=IP:${PUBIP},DNS:localhost"
chown caddy:caddy /etc/caddy/caldera.key /etc/caddy/caldera.crt
chmod 600 /etc/caddy/caldera.key
chmod 644 /etc/caddy/caldera.crt

cat > /etc/caddy/Caddyfile <<'CADDY'
{
	auto_https disable_redirects
}
:443 {
	tls /etc/caddy/caldera.crt /etc/caddy/caldera.key
	reverse_proxy localhost:8888
}
CADDY

systemctl enable caddy
systemctl restart caddy

echo "CALDERA bootstrap finished. UI: https://<public-ip> (self-signed) or SSM port-forward. Tail: journalctl -u caldera -f"
