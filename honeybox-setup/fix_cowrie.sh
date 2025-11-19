#!/usr/bin/env bash
# fix_cowrie.sh
# Run INSIDE the container (as root) or via lxc exec.
# Idempotent: safe to run multiple times.

set -euo pipefail
IFS=$'\n\t'

COWRIE_DIR="/opt/cowrie"
VENV_DIR="$COWRIE_DIR/cowrie-env"
COWRIE_USER="cowrie"
LOG="/tmp/fix_cowrie.log"

echo "[fix_cowrie] $(date) - starting" | tee -a "$LOG"

# 1) Ensure system build dependencies (best-effort, non-fatal)
echo "[fix_cowrie] installing system build-deps (apt-get may be slow)..." | tee -a "$LOG"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y build-essential python3-dev libssl-dev libffi-dev libjpeg-dev zlib1g-dev libxml2-dev libxslt1-dev libpq-dev gcc curl || true

# 2) Ensure cowrie user exists
if ! id -u "$COWRIE_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$COWRIE_USER" || true
fi

# 3) If repo missing, exit with message (this script expects /opt/cowrie)
if [ ! -d "$COWRIE_DIR" ]; then
  echo "[fix_cowrie] ERROR: $COWRIE_DIR not found. Clone cowrie first." | tee -a "$LOG"
  exit 2
fi

cd "$COWRIE_DIR"

# 4) Relax a few strict pins that commonly fail on some pip/pypi combos
# Only change those lines if they exist.
echo "[fix_cowrie] relaxing common strict pins in requirements.txt" | tee -a "$LOG"
sed -i -E 's/^urllib3==[0-9\.]+/urllib3>=1.26.0/' requirements.txt || true
sed -i -E 's/^requests==[0-9\.]+/requests>=2.25.0/' requirements.txt || true
sed -i -E 's/^attrs==[0-9\.]+/attrs>=23.0.0/' requirements.txt || true
sed -i -E 's/^urllib3==[0-9\.]+/urllib3>=1.26.0/' requirements.txt || true

# 5) Recreate venv as cowrie user (safe)
if [ -d "$VENV_DIR" ]; then
  echo "[fix_cowrie] removing existing venv" | tee -a "$LOG"
  rm -rf "$VENV_DIR" || true
fi
echo "[fix_cowrie] creating fresh venv" | tee -a "$LOG"
python3 -m venv "$VENV_DIR"
chown -R "$COWRIE_USER":"$COWRIE_USER" "$VENV_DIR"

# 6) Upgrade pip/setuptools inside venv
echo "[fix_cowrie] upgrading pip/setuptools/wheel" | tee -a "$LOG"
"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel || true

# 7) Try preinstall frequently problematic packages to give pip binary wheels where possible
echo "[fix_cowrie] preinstalling key binary packages (cryptography, twisted, pyOpenSSL) ..." | tee -a "$LOG"
"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel || true
"$VENV_DIR/bin/pip" install --upgrade cryptography pyOpenSSL twisted bcrypt service_identity pyasn1 || true

# 8) Attempt full requirements install with retries and fallback strategy
install_requirements() {
  local attempts=0
  while [ $attempts -lt 4 ]; do
    attempts=$((attempts+1))
    echo "[fix_cowrie] pip install -r attempt $attempts" | tee -a "$LOG"
    if "$VENV_DIR/bin/pip" install -r requirements.txt; then
      echo "[fix_cowrie] pip install -r succeeded" | tee -a "$LOG"
      return 0
    fi
    echo "[fix_cowrie] pip install -r failed (attempt $attempts). Retrying in 5s..." | tee -a "$LOG"
    sleep 5
  done

  # fallback: try no-deps install (best-effort) so cowrie console scripts get created
  echo "[fix_cowrie] trying pip install --no-deps as last-resort fallback" | tee -a "$LOG"
  if "$VENV_DIR/bin/pip" install --no-deps -r requirements.txt; then
    echo "[fix_cowrie] --no-deps pip install succeeded (partial). Continue." | tee -a "$LOG"
    return 0
  fi

  echo "[fix_cowrie] All pip attempts failed. Exiting with nonfatal status; manual intervention likely required." | tee -a "$LOG"
  return 1
}

install_requirements || true

# 9) Install cowrie package into venv so console scripts appear
echo "[fix_cowrie] installing Cowrie package into venv" | tee -a "$LOG"
if [ -f "setup.py" ]; then
  "$VENV_DIR/bin/python" setup.py install || "$VENV_DIR/bin/pip" install . || true
else
  "$VENV_DIR/bin/pip" install . || true
fi

# 10) Ensure bin/cowrie exists and is executable; if not, try to create a minimal wrapper
if [ ! -x "$COWRIE_DIR/bin/cowrie" ]; then
  echo "[fix_cowrie] cowrie launcher missing; creating proper bash wrapper" | tee -a "$LOG"
  mkdir -p "$COWRIE_DIR/bin" || true
  cat > "$COWRIE_DIR/bin/cowrie" <<'EOF'
#!/usr/bin/env bash
COWRIE_HOME="/opt/cowrie"
VENV="$COWRIE_HOME/cowrie-env"

exec "$VENV/bin/python" "$COWRIE_HOME/src/cowrie" "$@"
EOF
  chmod +x "$COWRIE_DIR/bin/cowrie"
else
  echo "[fix_cowrie] cowrie console script present." | tee -a "$LOG"
fi

# 11) chown everything to cowrie user
chown -R "$COWRIE_USER":"$COWRIE_USER" "$COWRIE_DIR" || true

# 12) Try to start cowrie once (non-blocking)
echo "[fix_cowrie] attempting to start cowrie (non-blocking)..." | tee -a "$LOG"
if [ -f "$COWRIE_DIR/bin/cowrie" ]; then
  sudo -u "$COWRIE_USER" bash "$COWRIE_DIR/bin/cowrie" start 2>&1 | tee -a "$LOG" || true
else
  echo "[fix_cowrie] bin/cowrie script not found; skipping start attempt" | tee -a "$LOG"
fi

# 13) quick check: listening on 2222 inside container
if ss -tlnp 2>/dev/null | grep -q ":2222"; then
  echo "[fix_cowrie] Cowrie appears to be listening on port 2222" | tee -a "$LOG"
else
  echo "[fix_cowrie] Cowrie not listening (yet) - check logs at /opt/cowrie/log or run script again" | tee -a "$LOG"
fi

echo "[fix_cowrie] done" | tee -a "$LOG"
exit 0