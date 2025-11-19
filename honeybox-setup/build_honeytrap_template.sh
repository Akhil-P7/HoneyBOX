#!/bin/bash
# build_honeytrap_template.sh
# Build an LXD image with DVWA + Cowrie + simple PCAP rotator and publish it as an alias.
set -euo pipefail
IFS=$'\n\t'

# ----- logging helpers -----
log_info(){ echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_warn(){ echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_error(){ echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

# ----- configuration -----
cd "$(dirname "$0")" || exit 1

TEMPLATE_NAME="honeytrap-template"
BUILDER_NAME="honeytrap-template-build"
BASE_IMAGE="ubuntu:20.04"
PCAP_DIR="/var/log/honeybox/pcaps"
LOG_DIR="/var/log/honeybox"
COWRIE_USER="cowrie"
COWRIE_HOME="/opt/cowrie"
# Optional: set FORCE_REBUILD=1 in environment to force rebuild without interactive prompt.
FORCE_REBUILD="${FORCE_REBUILD:-0}"

# Cleanup handler
cleanup_on_error() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    log_error "Build failed with exit code $rc. Attempting cleanup..."
    if lxc list --format=csv -c n | grep -xq "$BUILDER_NAME"; then
      log_warn "Stopping and removing partial builder container..."
      lxc stop "$BUILDER_NAME" --force >/dev/null 2>&1 || true
      lxc delete "$BUILDER_NAME" --force >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup_on_error EXIT

log_info "=== Honeytrap template builder starting ==="

# If template exists, optionally ask to rebuild (non-interactive if FORCE_REBUILD=1)
if lxc image list --format=csv -c a | grep -q "$TEMPLATE_NAME"; then
  log_warn "Template alias '$TEMPLATE_NAME' already exists."
  if [ "$FORCE_REBUILD" != "1" ]; then
    read -r -p "Template exists. Rebuild? (y/N): " yn || true
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
      log_info "Aborting: not rebuilding."
      exit 0
    fi
  else
    log_info "FORCE_REBUILD=1 set; rebuilding template."
  fi
  log_info "Removing existing template alias (if present)..."
  # remove any image alias matching TEMPLATE_NAME
  if lxc image list --format=csv -c a | grep -q "$TEMPLATE_NAME"; then
    # find fingerprint(s) for that alias and delete them
    for fp in $(lxc image list --format=csv -c f,a | awk -F, -v alias="$TEMPLATE_NAME" '$2==alias{print $1}'); do
      log_info "Deleting image fingerprint $fp"
      lxc image delete "$fp" || true
    done
  fi
fi

# Remove any stale builder
if lxc list --format csv -c n | grep -xq "$BUILDER_NAME"; then
  log_info "Found existing builder container; removing..."
  lxc stop "$BUILDER_NAME" --force >/dev/null 2>&1 || true
  lxc delete "$BUILDER_NAME" --force >/dev/null 2>&1 || true
fi

# Launch builder
log_info "Launching builder container from ${BASE_IMAGE}..."
lxc launch "$BASE_IMAGE" "$BUILDER_NAME"

# wait for container to accept exec
log_info "Waiting for container to respond to commands..."
for i in $(seq 1 30); do
  if lxc exec "$BUILDER_NAME" -- true >/dev/null 2>&1; then
    log_info "Container is responsive."
    break
  fi
  sleep 1
  if [ "$i" -eq 30 ]; then
    log_error "Container did not become responsive in time."
    exit 1
  fi
done

# Ensure /etc/hosts contains hostname (use host-side push to avoid in-container write issues).
log_info "Ensuring container /etc/hosts contains hostname mapping..."
tmp_hosts=$(mktemp)
lxc exec "$BUILDER_NAME" -- bash -lc 'cat /etc/hosts || true' > "$tmp_hosts" || true
container_hostname=$(lxc exec "$BUILDER_NAME" -- hostname)
if ! grep -w -q "$container_hostname" "$tmp_hosts" 2>/dev/null; then
  echo "127.0.1.1 $container_hostname" >> "$tmp_hosts"
  lxc file push "$tmp_hosts" "$BUILDER_NAME"/etc/hosts --mode=0644
  log_info "Wrote hostname entry to /etc/hosts"
else
  log_info "/etc/hosts already has hostname entry"
fi
rm -f "$tmp_hosts"

# DNS probe & fallback:
log_info "Checking container DNS and applying fallback if needed..."
# probe inside container; if probe cannot perform in-container write it will exit 50
lxc exec "$BUILDER_NAME" -- bash -lc '
set -e
if ! timeout 5 bash -c "getent hosts archive.ubuntu.com >/dev/null 2>&1"; then
  echo "[DNS PROBE] DNS resolution failed inside container"
  if echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null 2>&1; then
    echo "[DNS PROBE] Successfully wrote /etc/resolv.conf inside container"
    exit 0
  else
    echo "[DNS PROBE] In-container write failed; requesting host-side push"
    exit 50
  fi
fi
exit 0
' >/tmp/honeybox_dns_probe.out 2>&1 || true

dns_exit=$?
if [ "$dns_exit" -eq 50 ]; then
  log_warn "In-container write to /etc/resolv.conf failed; performing lxc file push from host."
  tmpf=$(mktemp)
  cat > "$tmpf" <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
  if ! lxc file push "$tmpf" "$BUILDER_NAME"/etc/resolv.conf --mode=0644; then
    rm -f "$tmpf"
    log_error "Failed to push resolv.conf into container; aborting"
    exit 1
  fi
  rm -f "$tmpf"
  log_info "resolv.conf pushed into container"
elif [ "$dns_exit" -ne 0 ]; then
  log_warn "DNS probe returned non-zero ($dns_exit). Continuing but apt may fail."
else
  log_info "Container DNS probe OK"
fi

# apt-get update with retries (host executes update inside container)
log_info "Running apt-get update inside container (with retries)..."
retry=0
until lxc exec "$BUILDER_NAME" -- bash -lc "sudo apt-get update -y"; do
  retry=$((retry+1))
  log_warn "apt-get update failed (attempt $retry). Retrying in 5s..."
  sleep 5
  if [ "$retry" -ge 6 ]; then
    log_error "apt-get update failing after $retry attempts. Aborting."
    exit 1
  fi
done
log_info "apt-get update succeeded."

# Upgrade base packages non-interactively
log_info "Upgrading packages (may take a while)..."
lxc exec "$BUILDER_NAME" -- bash -lc "DEBIAN_FRONTEND=noninteractive sudo apt-get -y upgrade" || log_warn "Upgrade step returned non-zero; continuing"

# Install required packages with retries inside container
PACKAGES="apache2 php php-mysqli php-gd mariadb-server git python3 python3-venv python3-pip tcpdump jq"
log_info "Installing packages: $PACKAGES"
retry=0
until lxc exec "$BUILDER_NAME" -- bash -lc "DEBIAN_FRONTEND=noninteractive sudo apt-get install -y $PACKAGES"; do
  retry=$((retry+1))
  log_warn "apt-get install attempt $retry failed; retry in 5s..."
  sleep 5
  if [ "$retry" -ge 5 ]; then
    log_error "Package install failed after $retry attempts; aborting."
    exit 1
  fi
done
log_info "Required packages installed."

# Start mysql (mariadb) before DB config if available
log_info "Starting database service (if available) ..."
lxc exec "$BUILDER_NAME" -- bash -lc '
if command -v systemctl >/dev/null 2>&1 && ps -p 1 -o comm= | grep -q systemd; then
  sudo systemctl start mysql || sudo service mysql start || true
else
  sudo service mysql start || true
fi
' || log_warn "Could not start mysql service (non-fatal)."

# Configure MariaDB for DVWA (best-effort)
log_info "Configuring MariaDB / creating DVWA DB (best-effort)..."
lxc exec "$BUILDER_NAME" -- bash -lc "sudo mysql -e \"CREATE DATABASE IF NOT EXISTS dvwa; CREATE USER IF NOT EXISTS 'dvwa'@'localhost' IDENTIFIED BY 'dvwa'; GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost'; FLUSH PRIVILEGES;\" || true"

# Install DVWA
log_info "Installing DVWA into /var/www/html/dvwa..."
lxc exec "$BUILDER_NAME" -- bash -lc "sudo rm -rf /var/www/html/dvwa || true; sudo git clone https://github.com/digininja/DVWA.git /var/www/html/dvwa || true"
# copy default config and set dvwa DB password
lxc exec "$BUILDER_NAME" -- bash -lc "sudo cp /var/www/html/dvwa/config/config.inc.php.dist /var/www/html/dvwa/config/config.inc.php 2>/dev/null || true; sudo sed -i \"s/'db_password'\\s*=>\\s*'.*'/'db_password' => 'dvwa'/\" /var/www/html/dvwa/config/config.inc.php || true"
# ensure apache permissions and enable rewrite
lxc exec "$BUILDER_NAME" -- bash -lc "sudo chown -R www-data:www-data /var/www/html/dvwa || true; sudo a2enmod rewrite || true"
# restart apache safely (systemd-aware)
lxc exec "$BUILDER_NAME" -- bash -lc '
if command -v systemctl >/dev/null 2>&1 && ps -p 1 -o comm= | grep -q systemd; then
  sudo systemctl restart apache2 || sudo service apache2 restart || true
else
  sudo service apache2 restart || true
fi
' || log_warn "Apache restart returned non-fatal error"

# Install Cowrie
log_info "Preparing Cowrie honeypot skeleton..."
lxc exec "$BUILDER_NAME" -- bash -lc "sudo useradd -m -s /bin/bash ${COWRIE_USER} 2>/dev/null || true"
lxc exec "$BUILDER_NAME" -- bash -lc "sudo rm -rf ${COWRIE_HOME} || true; sudo git clone https://github.com/cowrie/cowrie.git ${COWRIE_HOME} || true"

# --- push and run fix script inside builder to ensure cowrie installs OK ---
log_info "Pushing fix_cowrie.sh into builder and running it (idempotent)..."
if [ -f "./fix_cowrie.sh" ]; then
  lxc file push ./fix_cowrie.sh "$BUILDER_NAME"/tmp/fix_cowrie.sh --mode=0755
  lxc exec "$BUILDER_NAME" -- bash -lc "sudo /tmp/fix_cowrie.sh" || {
    log_warn "fix_cowrie.sh returned nonzero; continuing (template may still work), check /tmp/fix_cowrie.log inside builder"
  }
  log_info "fix_cowrie.sh executed successfully"
else
  log_warn "fix_cowrie.sh not found in current directory; skipping fix step"
fi
# --- end fix block ---

# --- cowrie: relax attrs & requests pins and create venv with robust pip install ---
log_info "Adjusting Cowrie requirements and creating venv with robust install..."

# ----- relax problematic strict pins inside the container's requirements.txt -----
log_info "Relaxing strict version pins in Cowrie requirements to avoid unavailable/yanked versions..."

lxc exec "$BUILDER_NAME" -- bash -lc "sudo bash -lc '
REQ_FILE=\"${COWRIE_HOME}/requirements.txt\"
if [ -f \"\$REQ_FILE\" ]; then
  # make a backup just in case
  cp \"\$REQ_FILE\" \"\$REQ_FILE.orig\" || true

  # Relax exact pins to allow pip resolver to pick a compatible release:
  # - attrs==A.B.C  -> attrs>=25.3.0,<26.0.0
  # - requests==X.Y.Z -> requests>=2.32.2,<3.0.0
  # - urllib3==X.Y.Z -> urllib3>=1.26.0,<3.0.0
  # - idna==... -> idna>=2.8,<4.0
  # - certifi==... -> certifi>=2019.9.11
  # - chardet==... -> chardet>=3.0.4

  sed -i -E \"s/^attrs==[0-9\\.\\-]+/attrs>=25.3.0,<26.0.0/\" \"\$REQ_FILE\" || true
  sed -i -E \"s/^requests==[0-9\\.\\-]+/requests>=2.32.2,<3.0.0/\" \"\$REQ_FILE\" || true
  sed -i -E \"s/^urllib3==[0-9\\.\\-]+/urllib3>=1.26.0,<3.0.0/\" \"\$REQ_FILE\" || true
  sed -i -E \"s/^idna==[0-9\\.\\-]+/idna>=2.8,<4.0/\" \"\$REQ_FILE\" || true
  sed -i -E \"s/^certifi==[0-9\\.\\-]+/certifi>=2019.9.11/\" \"\$REQ_FILE\" || true
  sed -i -E \"s/^chardet==[0-9\\.\\-]+/chardet>=3.0.4/\" \"\$REQ_FILE\" || true

  # Also relax any other exact pins that look like X==Y.Z.W -> X>=Y.Z.W,<Y+1.0.0
  # (This fallback attempts to be conservative for other packages)
  awk '\''{
    if (match(\$0, /^([a-zA-Z0-9_\\-]+)==([0-9]+)\\.([0-9]+)\\.([0-9]+).*$/, m)) {
      pkg = m[1]; maj = m[2]; min = m[3]; patch = m[4];
      # produce: pkg>=maj.min.patch,<((maj+1)).0.0
      printf(\"%s>=%s.%s.%s,<%s.0.0\\n\", pkg, maj, min, patch, maj+1);
    } else {
      print \$0;
    }
  }'\'' \"\$REQ_FILE\" > \"\$REQ_FILE.tmp\" || true

  # replace only if the awk processed file is non-empty
  if [ -s \"\$REQ_FILE.tmp\" ]; then
    mv \"\$REQ_FILE.tmp\" \"\$REQ_FILE\"
  else
    rm -f \"\$REQ_FILE.tmp\" || true
  fi

  echo \"[RELAX] requirements.txt adjusted (backup saved as requirements.txt.orig)\"
else
  echo \"[RELAX] requirements.txt not present; skipping adjustments\"
fi
'"

# Create venv and attempt resilient pip installs
lxc exec "$BUILDER_NAME" -- bash -lc "sudo bash -lc '
cd \"${COWRIE_HOME}\"
python3 -m venv cowrie-env || { echo \"venv creation failed\"; exit 1; }
./cowrie-env/bin/python -m pip install --upgrade pip setuptools wheel || true

# Strategy:
# 1) try pip install -r requirements.txt --prefer-binary
# 2) if that fails, install the two problematic packages explicitly (relaxed ranges)
# 3) finally try pip install -r requirements.txt --no-deps as last resort
if ./cowrie-env/bin/pip install --prefer-binary -r requirements.txt; then
  echo \"[COWRIE] requirements installed (prefer-binary)\" 
else
  echo \"[COWRIE] prefer-binary install failed; trying targeted installs for attrs/requests\"
  ./cowrie-env/bin/pip install \"attrs>=25.3.0,<25.5.0\" \"requests>=2.32.2,<2.33.0\" || true
  if ./cowrie-env/bin/pip install -r requirements.txt --no-deps; then
    echo \"[COWRIE] requirements installed with --no-deps fallback\"
  else
    echo \"[COWRIE] pip install still failed; continuing but Cowrie may not run until dependencies are resolved\"
  fi
fi
'"

# Configure Cowrie logging + minimal config
log_info "Configuring Cowrie logs and basic settings..."
lxc exec "$BUILDER_NAME" -- bash -lc "sudo mkdir -p ${LOG_DIR}/cowrie ${PCAP_DIR} || true; sudo chown -R ${COWRIE_USER}:${COWRIE_USER} ${LOG_DIR} ${PCAP_DIR} ${COWRIE_HOME} || true"

# Create cowrie.cfg on host and push to container (ensure destination dir exists)
log_info "Creating and pushing cowrie.cfg..."
tmp_cfg="$(mktemp)"
cat > "$tmp_cfg" <<'COWRIECFG'
[output_jsonlog]
enabled = true
directory = /var/log/honeybox/cowrie

[ssh]
listen_port = 2222
# keep other settings default for demo
COWRIECFG

# ensure destination dir exists, then push
lxc exec "$BUILDER_NAME" -- bash -lc "sudo mkdir -p ${COWRIE_HOME}/etc || true"
lxc file push "$tmp_cfg" "$BUILDER_NAME${COWRIE_HOME}/etc/cowrie.cfg" --mode=0644 || lxc file push "$tmp_cfg" "$BUILDER_NAME/opt/cowrie/etc/cowrie.cfg" --mode=0644 || true
rm -f "$tmp_cfg"

# Create systemd service for Cowrie (best-effort)
log_info "Creating Cowrie systemd unit (best-effort)..."
tmp_unit="$(mktemp)"
cat > "$tmp_unit" <<'UNIT'
[Unit]
Description=Cowrie SSH Honeypot
After=network.target

[Service]
Type=simple
User=cowrie
WorkingDirectory=/opt/cowrie
ExecStart=/opt/cowrie/cowrie-env/bin/python /opt/cowrie/bin/cowrie start
ExecStop=/opt/cowrie/cowrie-env/bin/python /opt/cowrie/bin/cowrie stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

lxc file push "$tmp_unit" "$BUILDER_NAME/etc/systemd/system/cowrie.service" --mode=0644 || true
rm -f "$tmp_unit"

# Enable cowrie service only if systemd present
lxc exec "$BUILDER_NAME" -- bash -lc '
if command -v systemctl >/dev/null 2>&1 && ps -p 1 -o comm= | grep -q systemd; then
  sudo systemctl daemon-reload || true
  sudo systemctl enable cowrie.service || true
fi
' || true

# Create PCAP rotator script and unit
log_info "Installing PCAP rotator and service..."

# Push pcap rotator script
tmp_rotator="$(mktemp)"
cat > "$tmp_rotator" <<'ROT'
#!/bin/bash
PCAP_DIR=/var/log/honeybox/pcaps
mkdir -p "$PCAP_DIR"
while true; do
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  PCAP_FILE=$PCAP_DIR/pcap_$TIMESTAMP.pcap
  timeout 55s tcpdump -i any -w $PCAP_FILE || true
  ls -1tr $PCAP_DIR | head -n -48 | xargs -r -I {} rm -- $PCAP_DIR/{}
done
ROT

lxc file push "$tmp_rotator" "$BUILDER_NAME/usr/local/bin/honeybox-pcap-rotator" --mode=0755 || true
rm -f "$tmp_rotator"

# Push systemd unit
tmp_unit2="$(mktemp)"
cat > "$tmp_unit2" <<'UNIT2'
[Unit]
Description=Honeybox PCAP Rotator
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/honeybox-pcap-rotator
Restart=always

[Install]
WantedBy=multi-user.target
UNIT2

lxc file push "$tmp_unit2" "$BUILDER_NAME/etc/systemd/system/honeybox-pcap.service" --mode=0644 || true
rm -f "$tmp_unit2"

lxc exec "$BUILDER_NAME" -- bash -lc '
if command -v systemctl >/dev/null 2>&1 && ps -p 1 -o comm= | grep -q systemd; then
  sudo systemctl daemon-reload || true
  sudo systemctl enable honeybox-pcap.service || true
fi
' || true

# Start services (safe)
log_info "Starting services inside builder container..."
lxc exec "$BUILDER_NAME" -- bash -lc '
if command -v systemctl >/dev/null 2>&1 && ps -p 1 -o comm= | grep -q systemd; then
  sudo systemctl start apache2 || sudo service apache2 start || true
  sudo systemctl start mysql || sudo service mysql start || true
  sudo systemctl start cowrie.service || true
  sudo systemctl start honeybox-pcap.service || true
else
  sudo service apache2 start || true
  sudo service mysql start || true
  echo "systemd not PID1; Cowrie/pcap services may require manual start" || true
fi
' || true

# If cowrie service isn't running (systemd absent or failed), attempt background start (safe)
log_info "Ensuring Cowrie is running: fallback background start if necessary..."
lxc exec "$BUILDER_NAME" -- bash -lc '
# check for cowrie process
if pgrep -f "/opt/cowrie/bin/cowrie" >/dev/null 2>&1; then
  echo "Cowrie already running (process found)"
else
  if [ -x /opt/cowrie/cowrie-env/bin/python ]; then
    sudo -u cowrie nohup /opt/cowrie/cowrie-env/bin/python /opt/cowrie/bin/cowrie start >/var/log/honeybox/cowrie/start.log 2>&1 &
    sleep 2
    if pgrep -f "/opt/cowrie/bin/cowrie" >/dev/null 2>&1; then
      echo "Cowrie started via nohup"
    else
      echo "Cowrie failed to start via nohup; check /var/log/honeybox/cowrie/start.log"
    fi
  else
    echo "Cowrie venv/python not present; cannot start fallback"
  fi
fi
' || true

# quick verification: check cowrie process or log
log_info "Verifying cowrie state (process or logs)..."
lxc exec "$BUILDER_NAME" -- bash -lc '
if pgrep -f "/opt/cowrie/bin/cowrie" >/dev/null 2>&1; then
  echo "Cowrie process present"
elif [ -f /var/log/honeybox/cowrie/cowrie.json ] || [ -f /var/log/honeybox/cowrie/start.log ]; then
  echo "Cowrie log file exists (see /var/log/honeybox/cowrie)"
else
  echo "Cowrie not running and no logs found"
fi
' || true

# Build marker & cleanup apt lists
log_info "Writing build marker and cleaning apt cache..."
lxc exec "$BUILDER_NAME" -- bash -lc "sudo bash -lc 'echo \"Honeytrap template built on \$(date)\" > /root/HONEYTRAP_TEMPLATE_BUILT; sudo apt-get clean || true; sudo rm -rf /var/lib/apt/lists/* || true' " || true

# Stop container and publish
log_info "Stopping builder container..."
lxc stop "$BUILDER_NAME"

log_info "Publishing builder as image alias: ${TEMPLATE_NAME}"
# remove old alias images if any
if lxc image list --format=csv -c a | grep -q "$TEMPLATE_NAME"; then
  log_info "Removing previous alias images for $TEMPLATE_NAME"
  for fp in $(lxc image list --format=csv -c f,a | awk -F, -v alias="$TEMPLATE_NAME" '$2==alias{print $1}'); do
    log_info "Deleting image $fp"
    lxc image delete "$fp" || true
  done
fi

lxc publish "$BUILDER_NAME" --alias "$TEMPLATE_NAME"

# remove builder container
log_info "Removing builder instance..."
lxc delete "$BUILDER_NAME" --force || true

# disable trap because we're successful
trap - EXIT
log_info "=== honeytrap-template published successfully as '${TEMPLATE_NAME}' ==="
log_info "You can now create a new sandbox from the template with:"
log_info "  lxc launch ${TEMPLATE_NAME} <name>"