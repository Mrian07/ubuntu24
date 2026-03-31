#!/bin/bash
#
# Backup, Restore & Bandwidth Management Setup
# Compatible with Ubuntu 24.04 LTS
# ==========================================

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Display banner
echo -e "${BLUE}"
echo "========================================"
echo "  Backup & Bandwidth Setup - Ubuntu 24.04"
echo "========================================"
echo -e "${NC}"

cd /root

# Install rclone for Ubuntu 24.04
log_info "Installing rclone..."
if ! command -v rclone &> /dev/null; then
    apt-get update -qq
    apt-get install -y rclone >/dev/null 2>&1
    log_success "Rclone installed"
else
    log_info "Rclone already installed"
fi

# Configure rclone
log_info "Configuring rclone..."
mkdir -p /root/.config/rclone
printf "q\n" | rclone config >/dev/null 2>&1 || true

if wget -q -O /root/.config/rclone/rclone.conf "https://raw.githubusercontent.com/Mrian07/ubuntu24/main/install/rclone.conf"; then
    log_success "Rclone configuration downloaded"
else
    log_warn "Failed to download rclone config, using default"
fi

# Install wondershaper for bandwidth management
log_info "Installing wondershaper..."
if [[ -d wondershaper ]]; then
    rm -rf wondershaper
fi

if git clone -q https://github.com/casper9/wondershaper.git 2>/dev/null; then
    cd wondershaper
    if make install >/dev/null 2>&1; then
        log_success "Wondershaper installed"
    else
        log_warn "Wondershaper installation failed"
    fi
    cd /root
    rm -rf wondershaper
else
    log_warn "Failed to clone wondershaper repository"
fi

# Download management scripts
log_info "Downloading management scripts..."
cd /usr/bin

declare -A scripts=(
    ["backup"]="https://raw.githubusercontent.com/Mrian07/ubuntu24/main/menu/backup.sh"
    ["restore"]="https://raw.githubusercontent.com/Mrian07/ubuntu24/main/menu/restore.sh"
    ["cleaner"]="https://raw.githubusercontent.com/Mrian07/ubuntu24/main/install/cleaner.sh"
    ["xp"]="https://raw.githubusercontent.com/Mrian07/ubuntu24/main/install/xp.sh"
)

for script in "${!scripts[@]}"; do
    if wget -q -O "$script" "${scripts[$script]}"; then
        chmod +x "/usr/bin/$script"
        log_success "Downloaded and installed: $script"
    else
        log_error "Failed to download: $script"
    fi
done

cd /root

# Setup cron jobs
log_info "Setting up cron jobs..."

# Cleaner cron (runs every 2 minutes)
if [[ ! -f "/etc/cron.d/cleaner" ]]; then
    cat > /etc/cron.d/cleaner <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/2 * * * * root /usr/bin/cleaner
EOF
    log_success "Created cleaner cron job"
else
    log_info "Cleaner cron job already exists"
fi

# Expiry check cron (runs daily at midnight)
if [[ ! -f "/etc/cron.d/xp_otm" ]]; then
    cat > /etc/cron.d/xp_otm <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 0 * * * root /usr/bin/xp
EOF
    log_success "Created expiry check cron job"
else
    log_info "Expiry check cron job already exists"
fi

# Backup cron (runs daily at 5 AM)
if [[ ! -f "/etc/cron.d/bckp_otm" ]]; then
    cat > /etc/cron.d/bckp_otm <<'EOF'
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 5 * * * root /usr/bin/bottelegram
EOF
    log_success "Created backup cron job"
else
    log_info "Backup cron job already exists"
fi

# Set proper permissions for cron files
chmod 644 /etc/cron.d/cleaner 2>/dev/null || true
chmod 644 /etc/cron.d/xp_otm 2>/dev/null || true
chmod 644 /etc/cron.d/bckp_otm 2>/dev/null || true

# Create retention config
cat > /home/re_otm <<'EOF'
7
EOF
log_info "Created retention configuration (7 days)"

# Restart cron service for Ubuntu 24.04
log_info "Restarting cron service..."
if systemctl restart cron >/dev/null 2>&1; then
    log_success "Cron service restarted"
else
    log_error "Failed to restart cron service"
fi

# Verify cron service is running
if systemctl is-active --quiet cron; then
    log_success "Cron service is running"
else
    log_error "Cron service is not running"
fi

# Display summary
echo ""
echo -e "${GREEN}========================================"
echo "  Installation Complete!"
echo -e "========================================${NC}"
echo ""
echo -e "${BLUE}Installed Components:${NC}"
echo "  • Rclone (cloud backup)"
echo "  • Wondershaper (bandwidth management)"
echo "  • Backup script (/usr/bin/backup)"
echo "  • Restore script (/usr/bin/restore)"
echo "  • Cleaner script (/usr/bin/cleaner)"
echo "  • Expiry checker (/usr/bin/xp)"
echo ""
echo -e "${BLUE}Cron Jobs:${NC}"
echo "  • Cleaner: Every 2 minutes"
echo "  • Expiry check: Daily at 00:00"
echo "  • Backup: Daily at 05:00"
echo ""
echo -e "${YELLOW}Usage:${NC}"
echo "  • Run backup: backup"
echo "  • Run restore: restore"
echo "  • Check cron: crontab -l"
echo "  • View logs: journalctl -u cron -f"
echo ""

# Cleanup
log_info "Cleaning up..."
rm -f /root/set-br.sh

log_success "Setup completed successfully!"

exit 0
