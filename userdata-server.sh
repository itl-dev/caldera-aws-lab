# ============================================================
#  CALDERA v5 server bootstrap (Ubuntu 22.04, runs as root)
#  - installs deps, clones CALDERA, runs it as a systemd service
#  - systemd => survives the Learner Lab stop/start between sessions
#
#  NOTE: this is the script *body*. Terraform prepends the shebang and a few
#  exported variables (ENABLE_GUACAMOLE, AWS_DEFAULT_REGION, VICTIM_ADMIN_PASSWORD,
#  GUAC_USER, GUAC_PASS) via aws_instance.server user_data in main.tf, so it is
#  not meant to run standalone. `-x` is intentionally OFF so the injected
#  password is not echoed into the bootstrap log.
# ============================================================
set -uo pipefail
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

# --- Point agents at this server's PRIVATE IP (reachable from victims in the VPC) ---
# CALDERA's default `app.contact.http` is http://0.0.0.0:8888, and it embeds that value
# verbatim in the "Deploy an agent" commands shown in the UI. 0.0.0.0 is a bind-all
# wildcard, NOT a routable destination, so a copy-pasted deploy command never connects.
# Rewrite it to this instance's private IP so the UI hands students a working command
# with no IP editing. The server SG only allows 8888 from inside the VPC, and the private
# IP is stable across Learner Lab stop/start. The web app still BINDS on 0.0.0.0 via
# `host:`/`port:` below, so Caddy's localhost:8888 proxy (the browser UI) is unaffected.
IMDS_TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVIP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
if [ -n "${PRIVIP:-}" ]; then
  sed -i "s|^app.contact.http: .*|app.contact.http: http://${PRIVIP}:8888|" /opt/caldera/conf/default.yml
fi

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

if [ "${ENABLE_GUACAMOLE:-false}" = "true" ]; then
  # CALDERA on 443 (default), plus the Guacamole browser-RDP gateway under /guac.
  # `handle` (not handle_path) keeps the /guac prefix so it matches the webapp
  # context; stripping it would land on Tomcat's ROOT instead.
  cat > /etc/caddy/Caddyfile <<'CADDY'
{
	auto_https disable_redirects
}
:443 {
	tls /etc/caddy/caldera.crt /etc/caddy/caldera.key
	handle /guac/* {
		reverse_proxy localhost:8080
	}
	redir /guac /guac/
	handle {
		reverse_proxy localhost:8888
	}
}
CADDY
else
  cat > /etc/caddy/Caddyfile <<'CADDY'
{
	auto_https disable_redirects
}
:443 {
	tls /etc/caddy/caldera.crt /etc/caddy/caldera.key
	reverse_proxy localhost:8888
}
CADDY
fi

systemctl enable caddy
systemctl restart caddy

# ============================================================
#  Apache Guacamole — browser-based RDP gateway (optional)
#  Students open https://<server>/guac/ and get the victims' Windows desktops
#  IN THE BROWSER over 443 — no local RDP client, no SSH key, no extra ports.
#  guacd speaks RDP to victims inside the VPC. user-mapping.xml is (re)built from
#  the running victims via the EC2 API on a timer, so replaced victims are picked
#  up automatically without a re-apply.
# ============================================================
if [ "${ENABLE_GUACAMOLE:-false}" = "true" ]; then
  GUAC_VER=1.3.0   # match Ubuntu 22.04's apt guacd / libguac version
  apt-get install -y guacd libguac-client-rdp0 libguac-client-vnc0 tomcat9 awscli
  curl -fsSL "https://archive.apache.org/dist/guacamole/${GUAC_VER}/binary/guacamole-${GUAC_VER}.war" \
    -o /var/lib/tomcat9/webapps/guac.war

  mkdir -p /etc/guacamole
  cat > /etc/guacamole/guacamole.properties <<'PROPS'
guacd-hostname: localhost
guacd-port: 4822
PROPS

  # Secrets for the sync job, kept out of the world-readable sync script.
  cat > /etc/guacamole/.lab-secrets <<SECRETS
VICTIM_ADMIN_PASSWORD='${VICTIM_ADMIN_PASSWORD:-}'
GUAC_USER='${GUAC_USER:-student}'
GUAC_PASS='${GUAC_PASS:-guacamole}'
AWS_DEFAULT_REGION='${AWS_DEFAULT_REGION:-us-east-1}'
SECRETS
  chmod 600 /etc/guacamole/.lab-secrets

  cat > /usr/local/sbin/guac-sync-connections.sh <<'SYNC'
#!/bin/bash
# Rebuild Guacamole's user-mapping.xml from the currently-running CALDERA victims.
# The file-auth provider auto-reloads on change, so no Tomcat restart is needed.
set -uo pipefail
# set -a so the sourced vars (incl. AWS_DEFAULT_REGION) are EXPORTED to the aws child.
set -a; . /etc/guacamole/.lab-secrets; set +a
OUT=/etc/guacamole/user-mapping.xml
TMP="$(mktemp)"
{
  echo '<user-mapping>'
  echo "    <authorize username=\"${GUAC_USER}\" password=\"${GUAC_PASS}\">"
  aws ec2 describe-instances \
    --filters 'Name=tag:Name,Values=caldera-victim-*' 'Name=instance-state-name,Values=running' \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,PrivateIpAddress]' \
    --output text 2>/dev/null | sort | while read -r NAME IP; do
      [ -z "${IP:-}" ] && continue
      cat <<CONN
        <connection name="${NAME}">
            <protocol>rdp</protocol>
            <param name="hostname">${IP}</param>
            <param name="port">3389</param>
            <param name="username">Administrator</param>
            <param name="password">${VICTIM_ADMIN_PASSWORD}</param>
            <param name="security">any</param>
            <param name="ignore-cert">true</param>
            <param name="resize-method">display-update</param>
            <param name="enable-wallpaper">false</param>
        </connection>
CONN
    done
  echo '    </authorize>'
  echo '</user-mapping>'
} > "$TMP"
install -o root -g tomcat -m 640 "$TMP" "$OUT"
rm -f "$TMP"
SYNC
  chmod 700 /usr/local/sbin/guac-sync-connections.sh

  cat > /etc/systemd/system/guac-sync.service <<'UNIT'
[Unit]
Description=Rebuild Guacamole user-mapping.xml from running CALDERA victims
After=network-online.target tomcat9.service
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/guac-sync-connections.sh
UNIT
  cat > /etc/systemd/system/guac-sync.timer <<'UNIT'
[Unit]
Description=Periodically refresh Guacamole victim connections
[Timer]
OnBootSec=60
OnUnitActiveSec=120
[Install]
WantedBy=timers.target
UNIT

  # Tell Tomcat where GUACAMOLE_HOME is, then bring everything up.
  grep -q GUACAMOLE_HOME /etc/default/tomcat9 || echo 'GUACAMOLE_HOME=/etc/guacamole' >> /etc/default/tomcat9
  systemctl daemon-reload
  systemctl enable guacd tomcat9
  systemctl restart guacd
  systemctl restart tomcat9
  systemctl enable --now guac-sync.timer
  /usr/local/sbin/guac-sync-connections.sh || true
fi

echo "CALDERA bootstrap finished. UI: https://<public-ip> (self-signed) or SSM port-forward. Tail: journalctl -u caldera -f"
