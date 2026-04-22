#!/usr/bin/env bash
# setup.sh — run on the Raspberry Pi to configure RADIUS-based SSH authentication.
#
# What this does:
#   1. Installs libpam-radius-auth and freeradius-utils
#   2. Installs /etc/pam_radius_auth.conf (backs up any existing one)
#   3. Prepends pam_radius_auth.so to /etc/pam.d/sshd (backs up original)
#   4. Verifies /etc/ssh/sshd_config has required settings
#   5. Creates local shell accounts for RADIUS users (no local password)
#
# Safe to re-run. Existing users, SSH keys, and local passwords are unaffected.
#
# Rollback:
#   sudo cp /etc/pam.d/sshd.bak /etc/pam.d/sshd && sudo systemctl restart sshd

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
# TODO: set these before running
MAC_MINI_IP="MAC_MINI_IP"          # e.g. 192.168.1.10
SHARED_SECRET="radius-shared-secret"
RADIUS_USERS=("radius-testuser" "radius-user2")
# ───────────────────────────────────────────────────────────────────────────────

if [[ "$MAC_MINI_IP" == "MAC_MINI_IP" ]]; then
    echo "ERROR: Set MAC_MINI_IP at the top of this script before running." >&2
    exit 1
fi

echo "==> Installing packages..."
sudo apt-get update -q
sudo apt-get install -y -q libpam-radius-auth freeradius-utils

echo "==> Writing /etc/pam_radius_auth.conf..."
if [[ -f /etc/pam_radius_auth.conf ]]; then
    sudo cp /etc/pam_radius_auth.conf /etc/pam_radius_auth.conf.bak
    echo "    (backed up existing file to /etc/pam_radius_auth.conf.bak)"
fi
sudo tee /etc/pam_radius_auth.conf > /dev/null <<EOF
${MAC_MINI_IP}:1812   ${SHARED_SECRET}   3
EOF
sudo chmod 600 /etc/pam_radius_auth.conf
sudo chown root:root /etc/pam_radius_auth.conf
echo "    Done."

echo "==> Patching /etc/pam.d/sshd..."
if grep -q "pam_radius_auth" /etc/pam.d/sshd; then
    echo "    pam_radius_auth already present — skipping."
else
    sudo cp /etc/pam.d/sshd /etc/pam.d/sshd.bak
    echo "    (backed up original to /etc/pam.d/sshd.bak)"

    # Insert the RADIUS auth line before the first @include or auth line
    # 'sufficient' = if RADIUS succeeds, stop; if it fails, fall through to local auth
    sudo sed -i '1s|^|# RADIUS auth — sufficient means: succeed here OR fall through to local auth\nauth    sufficient      pam_radius_auth.so\n\n|' /etc/pam.d/sshd
    echo "    Done."
fi

echo "==> Checking /etc/ssh/sshd_config..."
SSHD_CONF="/etc/ssh/sshd_config"
NEEDS_RESTART=false

check_or_set() {
    local key="$1" val="$2"
    if grep -qE "^\s*#?\s*${key}\s+${val}" "$SSHD_CONF"; then
        echo "    ${key} ${val} — OK"
    elif grep -qE "^\s*${key}\s+" "$SSHD_CONF"; then
        echo "    WARNING: ${key} is set to something other than '${val}'. Please verify:"
        grep -E "^\s*${key}\s+" "$SSHD_CONF" | sed 's/^/      /'
    else
        echo "    Adding: ${key} ${val}"
        sudo cp "$SSHD_CONF" "${SSHD_CONF}.bak" 2>/dev/null || true
        echo "${key} ${val}" | sudo tee -a "$SSHD_CONF" > /dev/null
        NEEDS_RESTART=true
    fi
}

check_or_set "UsePAM" "yes"
check_or_set "KbdInteractiveAuthentication" "yes"
check_or_set "PasswordAuthentication" "yes"

if $NEEDS_RESTART; then
    echo "==> Restarting sshd..."
    sudo systemctl restart sshd
    echo "    Done."
else
    echo "==> Reloading sshd config..."
    sudo systemctl reload sshd
fi

echo "==> Creating local accounts for RADIUS users..."
for user in "${RADIUS_USERS[@]}"; do
    if id "$user" &>/dev/null; then
        echo "    $user — already exists, skipping."
    else
        sudo useradd -m -s /bin/bash "$user"
        echo "    $user — created (no local password; auth via RADIUS only)."
    fi
done

echo ""
echo "==> Setup complete. Verify connectivity from this Pi:"
echo "    radtest radius-testuser TestPass123! ${MAC_MINI_IP} 0 ${SHARED_SECRET}"
echo ""
echo "==> Then SSH from another machine:"
echo "    ssh radius-testuser@$(hostname -I | awk '{print $1}')"
echo ""
echo "==> Rollback if needed:"
echo "    sudo cp /etc/pam.d/sshd.bak /etc/pam.d/sshd && sudo systemctl restart sshd"
