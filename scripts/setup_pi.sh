#!/bin/bash

# Setup script for PC-1 on Raspberry Pi
# Run this with sudo: sudo ./setup_pi.sh

set -e

if [ "$EUID" -ne 0 ]; then 
  echo "Please run as root (sudo ./setup_pi.sh)"
  exit 1
fi

echo "--- PC-1 Setup ---"

# 1. Set Hostname (local patch: pinned to current, no interactive rename)
CURRENT_HOSTNAME=$(hostname)
HOSTNAME="$CURRENT_HOSTNAME"
echo "Keeping current hostname: $HOSTNAME (interactive rename disabled by local patch)."

# 2. Configure Serial Port for Printer
# The thermal printer uses GPIO serial (/dev/serial0 -> /dev/ttyS0)
# We need to disable the serial console but keep the hardware enabled
echo "Configuring serial port for printer..."

# Disable serial console login service
systemctl stop serial-getty@ttyS0.service 2>/dev/null || true
systemctl disable serial-getty@ttyS0.service 2>/dev/null || true
systemctl mask serial-getty@ttyS0.service 2>/dev/null || true

# Use raspi-config non-interactively to:
# - Disable serial console (do_serial_cons 1 = disabled)
# - Enable serial hardware (do_serial_hw 0 = enabled)
raspi-config nonint do_serial_cons 1
raspi-config nonint do_serial_hw 0

echo "Serial port configured for printer use."

# 3. Install dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y nginx avahi-daemon python3-venv python3-pip network-manager dnsmasq-base rfkill dnsutils

# Configure journald to stay bounded and SD-card friendly
echo "Configuring systemd journal limits for SD-card longevity..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/pc-1.conf <<'EOL'
[Journal]
# Keep logs in RAM by default to reduce SD wear.
Storage=volatile
SystemMaxUse=16M
SystemMaxFileSize=2M
RuntimeMaxUse=16M
RuntimeMaxFileSize=2M
RuntimeKeepFree=32M
MaxRetentionSec=3day
Compress=yes
ForwardToSyslog=no
RateLimitIntervalSec=30s
RateLimitBurst=200
SyncIntervalSec=5m
EOL
systemctl restart systemd-journald

# Disable persistent core dumps (can consume significant space after crashes)
echo "Disabling persistent coredumps..."
mkdir -p /etc/systemd/coredump.conf.d
cat > /etc/systemd/coredump.conf.d/pc-1.conf <<'EOL'
[Coredump]
Storage=none
ProcessSizeMax=0
EOL

# Install storage guard to auto-trim logs/cache if disk usage rises
echo "Installing storage guard timer..."
cat > /usr/local/bin/pc1-storage-guard.sh <<'EOL'
#!/bin/bash
set -euo pipefail

WARN_THRESHOLD="${PC1_STORAGE_WARN_PERCENT:-85}"
ACTION_THRESHOLD="${PC1_STORAGE_ACTION_PERCENT:-90}"

usage_percent() {
    df --output=pcent / | awk 'NR==2 {gsub(/%/, "", $1); print int($1)}'
}

ROOT_USAGE="$(usage_percent)"
if [ "$ROOT_USAGE" -lt "$WARN_THRESHOLD" ]; then
    exit 0
fi

logger -t pc1-storage-guard "Root usage at ${ROOT_USAGE}% (warn=${WARN_THRESHOLD}%). Running cleanup."
journalctl --vacuum-size=8M >/dev/null 2>&1 || true
journalctl --vacuum-time=2d >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true
find /tmp -xdev -type f -mtime +3 -delete >/dev/null 2>&1 || true
find /var/tmp -xdev -type f -mtime +7 -delete >/dev/null 2>&1 || true

ROOT_USAGE_AFTER="$(usage_percent)"
if [ "$ROOT_USAGE_AFTER" -ge "$ACTION_THRESHOLD" ]; then
    logger -t pc1-storage-guard "Root usage remains high after cleanup: ${ROOT_USAGE_AFTER}%"
fi
EOL
chmod 0755 /usr/local/bin/pc1-storage-guard.sh

cat > /etc/systemd/system/pc1-storage-guard.service <<'EOL'
[Unit]
Description=PC-1 storage guard cleanup

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pc1-storage-guard.sh
Nice=10
IOSchedulingClass=idle
EOL

cat > /etc/systemd/system/pc1-storage-guard.timer <<'EOL'
[Unit]
Description=Run PC-1 storage guard periodically

[Timer]
OnBootSec=5min
OnUnitActiveSec=6h
RandomizedDelaySec=2min
Persistent=true

[Install]
WantedBy=timers.target
EOL

systemctl daemon-reload
systemctl enable --now pc1-storage-guard.timer
systemctl start pc1-storage-guard.service || true

# Stop and disable standalone dnsmasq service if it exists (we use NM's internal dnsmasq)
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true
systemctl mask dnsmasq 2>/dev/null || true

# Configure NetworkManager to use dnsmasq for DNS
echo "Configuring NetworkManager for captive portal support..."
mkdir -p /etc/NetworkManager/conf.d
mkdir -p /etc/NetworkManager/dnsmasq.d

# Enable dnsmasq plugin in NetworkManager
cat > /etc/NetworkManager/conf.d/00-use-dnsmasq.conf <<EOF
[main]
dns=dnsmasq
EOF

# Disable WiFi power saving to reduce Pi Zero/Zero 2 W disconnects on
# always-on devices. This is managed by NetworkManager so it persists
# across reboots and reconnects.
cat > /etc/NetworkManager/conf.d/10-wifi-powersave-off.conf <<EOF
[connection]
wifi.powersave=2
EOF

# Local patch: NM restart deferred to avoid dropping the current SSH session.
# Configs in /etc/NetworkManager/conf.d/ take effect at next reboot.
echo "NetworkManager configs written; restart deferred to next reboot."

# Add user to groups for printer access
echo "Adding $SUDO_USER to 'lp' and 'dialout' groups for printer access..."
usermod -a -G lp,dialout "$SUDO_USER"

# 4. Configure Nginx Reverse Proxy
echo "Configuring Nginx..."
cat > /etc/nginx/sites-available/paper-console <<EOL
server {
    listen 80 default_server;
    server_name _;
    client_max_body_size 3M;

    location / {
        proxy_pass http://127.0.1.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOL

# Link and reload
ln -sf /etc/nginx/sites-available/paper-console /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# 5. Create Systemd Service
# Attempt to locate the project directory based on script location
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
USER_NAME=${SUDO_USER:-$USER}

echo "Configuring Systemd Service..."
echo "Project Directory: $PROJECT_DIR"
echo "User: $USER_NAME"

# Create/Update virtual environment
echo "Checking virtual environment..."
VENV_DIR="$PROJECT_DIR/.venv"

if [ ! -d "$VENV_DIR" ]; then
    echo "Creating new virtual environment..."
    sudo -u "$USER_NAME" python3 -m venv "$VENV_DIR"
fi

# Install/Upgrade dependencies
echo "Installing Python dependencies..."
if [ -f "$PROJECT_DIR/requirements-pi.txt" ]; then
    sudo -u "$USER_NAME" "$VENV_DIR/bin/pip" install -r "$PROJECT_DIR/requirements-pi.txt"
elif [ -f "$PROJECT_DIR/requirements.txt" ]; then
    sudo -u "$USER_NAME" "$VENV_DIR/bin/pip" install -r "$PROJECT_DIR/requirements.txt"
else
    echo "Warning: requirements.txt not found!"
fi

# Check for venv (now guaranteed to exist)
PYTHON_EXEC="python3"
if [ -d "$VENV_DIR" ]; then
    PYTHON_EXEC="$VENV_DIR/bin/python"
    echo "Using venv at $VENV_DIR"
else
    echo "Warning: No venv found. Using system python3."
fi

echo "Provisioning Device Password..."
DEVICE_CONFIG_DIR="/etc/pc1"
DEVICE_PASSWORD_FILE="$DEVICE_CONFIG_DIR/device_password"
DEVICE_MANAGED_FILE="$DEVICE_CONFIG_DIR/device_managed"

mkdir -p "$DEVICE_CONFIG_DIR"
chown root:"$USER_NAME" "$DEVICE_CONFIG_DIR"
# Keep the directory group-writable so the app service user can recreate the
# managed password file after image scrubbing or first-boot recovery.
chmod 0770 "$DEVICE_CONFIG_DIR"

if [ -f "$DEVICE_PASSWORD_FILE" ]; then
    DEVICE_PASSWORD=$(tr -d '\r\n' < "$DEVICE_PASSWORD_FILE")
else
    DEVICE_PASSWORD=""
fi

if [ "${#DEVICE_PASSWORD}" -lt 8 ]; then
    DEVICE_PASSWORD=$(PYTHONPATH="$PROJECT_DIR" "$PYTHON_EXEC" - <<'PY'
from app.device_password import generate_device_password

print(generate_device_password())
PY
)
    printf '%s\n' "$DEVICE_PASSWORD" > "$DEVICE_PASSWORD_FILE"
fi

touch "$DEVICE_MANAGED_FILE"
chown root:"$USER_NAME" "$DEVICE_PASSWORD_FILE" "$DEVICE_MANAGED_FILE"
chmod 0660 "$DEVICE_PASSWORD_FILE"
chmod 0640 "$DEVICE_MANAGED_FILE"

echo "Syncing Linux login password with Device Password..."
printf '%s:%s\n' "$USER_NAME" "$DEVICE_PASSWORD" | chpasswd

# Make WiFi script executable
echo "Setting up WiFi AP script..."
chmod +x "$PROJECT_DIR/scripts/wifi_ap_nmcli.sh"
# Ensure the script uses LF line endings (avoid /bin/bash^M issues after editing on Windows)
sed -i 's/\r$//' "$PROJECT_DIR/scripts/wifi_ap_nmcli.sh" || true

# Give sudo access for WiFi management AND service control (no password required)
echo "Configuring sudo permissions for WiFi management and service control..."
cat > /etc/sudoers.d/pc-1-wifi <<EOL
$USER_NAME ALL=(ALL) NOPASSWD: $PROJECT_DIR/scripts/wifi_ap_nmcli.sh
$USER_NAME ALL=(ALL) NOPASSWD: /bin/bash $PROJECT_DIR/scripts/wifi_ap_nmcli.sh
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/bash $PROJECT_DIR/scripts/wifi_ap_nmcli.sh
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/nmcli
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/rm -f /etc/NetworkManager/dnsmasq.d/captive-portal.conf
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/pkill -HUP -f dnsmasq.*NetworkManager
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl restart pc-1.service
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl start pc-1.service
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl stop pc-1.service
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl status pc-1.service
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart pc-1.service
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl start pc-1.service
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop pc-1.service
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl status pc-1.service
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/timedatectl *
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/date -s *
$USER_NAME ALL=(ALL) NOPASSWD: /usr/sbin/hwclock --systohc
$USER_NAME ALL=(ALL) NOPASSWD: /usr/sbin/chpasswd
$USER_NAME ALL=(ALL) NOPASSWD: /usr/sbin/ntpdate -s *
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl enable ssh
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl disable ssh
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl start ssh
$USER_NAME ALL=(ALL) NOPASSWD: /bin/systemctl stop ssh
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl enable ssh
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl disable ssh
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl start ssh
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop ssh
$USER_NAME ALL=(ALL) NOPASSWD: /usr/bin/raspi-config nonint do_ssh *
EOL
chmod 0440 /etc/sudoers.d/pc-1-wifi

# Remove any user service if it exists (switching back to system service)
echo "Checking for old user service to remove..."
if [ -f "/home/$USER_NAME/.config/systemd/user/pc-1.service" ]; then
    sudo -u "$USER_NAME" systemctl --user stop pc-1.service || true
    sudo -u "$USER_NAME" systemctl --user disable pc-1.service || true
    rm -f "/home/$USER_NAME/.config/systemd/user/pc-1.service"
    sudo -u "$USER_NAME" systemctl --user daemon-reload
fi

cat > /etc/systemd/system/pc-1.service <<EOL
[Unit]
Description=PC-1 Paper Console
After=network.target
# Start limit: max 5 restarts per 300 seconds (5 min), then stop trying
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
User=$USER_NAME
WorkingDirectory=$PROJECT_DIR
ExecStart=/bin/bash $PROJECT_DIR/run.sh
Restart=always
RestartSec=10
KillSignal=SIGINT
TimeoutStopSec=10
Environment=PYTHONUNBUFFERED=1
Environment=PC1_LOG_LEVEL=WARNING
Environment=UVICORN_LOG_LEVEL=warning
Environment=UVICORN_ACCESS_LOG=0
LogRateLimitIntervalSec=30s
LogRateLimitBurst=200
# Memory limits to prevent runaway processes (256MB is generous for this app)
MemoryMax=256M

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable pc-1.service
# Local patch: do not start now — no printer wired yet, would crash-loop.
echo "pc-1.service enabled; not starting now. Run 'sudo systemctl start pc-1.service' when printer is wired."

# Local patch: skipped default-user-dirs wipe and XDG override.
# None of Desktop/Documents/Downloads/Music/Pictures/Public/Templates/Videos
# exist on this host, and overwriting ~/.config/user-dirs.* is more invasive than needed.
echo "Default-user-dirs wipe skipped by local patch."

echo ""
echo "=========================================="
echo "         SETUP COMPLETE"
echo "=========================================="
echo ""
echo "Your device will be accessible at: http://$HOSTNAME.local"
echo ""
echo "A reboot is required for serial port changes"
echo "to take effect (required for printing)."
echo ""

read -p "Reboot now? [Y/n]: " REBOOT_CHOICE
REBOOT_CHOICE=${REBOOT_CHOICE:-Y}

if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
    echo "Rebooting in 3 seconds..."
    sleep 3
    reboot
else
    echo ""
    echo "Remember to reboot manually before using the printer:"
    echo "  sudo reboot"
    echo ""
    echo "After reboot, check status with:"
    echo "  sudo systemctl status pc-1.service"
fi
echo "=========================================="
