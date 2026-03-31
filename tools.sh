#!/bin/bash
#
# System Tools & Dependencies Installation
# Compatible with Ubuntu 24.04 LTS
# ==========================================

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

green() { echo -e "\\033[32;1m${*}\\033[0m"; }
red() { echo -e "\\033[31;1m${*}\\033[0m"; }
yellow() { echo -e "\\033[33;1m${*}\\033[0m"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

clear

# Display banner
echo -e "${CYAN}"
echo "========================================"
echo "  System Tools Installation"
echo "  Ubuntu 24.04 LTS"
echo "========================================"
echo -e "${NC}"
echo ""
echo "  The script will go through an installation process!"
echo "        PAKETSSH.COM SCRIPT ...LOADING..."
echo ""
sleep 1

# Detect network interface
log_info "Detecting network interface..."
NET=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
if [[ -z "$NET" ]]; then
    NET="eth0"
    log_warn "Could not detect network interface, using default: $NET"
else
    log_info "Network interface: $NET"
fi

# System update
log_info "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get dist-upgrade -y -qq

# Install sudo if not present
if ! command -v sudo &> /dev/null; then
    apt-get install -y sudo
fi

# Clean package cache
log_info "Cleaning package cache..."
apt-get clean all -y

# Install debconf-utils for non-interactive configuration
apt-get install -y debconf-utils

# Remove conflicting packages
log_info "Removing conflicting packages..."
apt-get remove --purge -y ufw firewalld exim4 2>/dev/null || true
apt-get autoremove -y

# Pre-configure iptables-persistent
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

# Install core dependencies for Ubuntu 24.04
log_info "Installing core dependencies..."
apt-get install -y --no-install-recommends \
    software-properties-common \
    iptables \
    iptables-persistent \
    netfilter-persistent \
    figlet \
    ruby \
    libxml-parser-perl \
    nmap \
    screen \
    curl \
    wget \
    jq \
    bzip2 \
    gzip \
    coreutils \
    rsyslog \
    iftop \
    htop \
    zip \
    unzip \
    net-tools \
    sed \
    gnupg \
    gnupg2 \
    bc \
    apt-transport-https \
    build-essential \
    dirmngr \
    neofetch \
    screenfetch \
    lsof \
    openssl \
    openvpn \
    easy-rsa \
    fail2ban \
    tmux \
    stunnel4 \
    dropbear \
    socat \
    cron \
    bash-completion \
    ntpdate \
    xz-utils \
    dnsutils \
    lsb-release \
    chrony \
    libnss3-dev \
    libnspr4-dev \
    pkg-config \
    libpam0g-dev \
    libcap-ng-dev \
    libcap-ng-utils \
    libselinux1-dev \
    libcurl4-nss-dev \
    flex \
    bison \
    make \
    libnss3-tools \
    libevent-dev \
    apt \
    git \
    speedtest-cli \
    p7zip-full \
    libjpeg-dev \
    zlib1g-dev \
    python3 \
    python3-pip \
    shc \
    nodejs \
    nginx \
    php \
    php-fpm \
    php-cli \
    php-mysql \
    >/dev/null 2>&1

log_success "Core dependencies installed"

# Install squid (package name changed in Ubuntu 24.04)
log_info "Installing Squid proxy..."
apt-get install -y squid >/dev/null 2>&1 || apt-get install -y squid3 >/dev/null 2>&1
log_success "Squid installed"

# Remove unnecessary packages
log_info "Removing unnecessary packages..."
apt-get autoclean -y >/dev/null 2>&1
apt-get -y --purge remove unscd >/dev/null 2>&1 || true
apt-get -y --purge remove samba* >/dev/null 2>&1 || true
apt-get -y --purge remove apache2* >/dev/null 2>&1 || true
apt-get -y --purge remove bind9* >/dev/null 2>&1 || true
apt-get -y remove sendmail* >/dev/null 2>&1 || true
apt-get autoremove -y >/dev/null 2>&1

# Install and configure vnstat
log_info "Installing vnstat..."
apt-get install -y vnstat >/dev/null 2>&1

# Check if vnstat version is sufficient
VNSTAT_VERSION=$(vnstat --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "0")
if [[ -z "$VNSTAT_VERSION" ]] || (( $(echo "$VNSTAT_VERSION < 2.6" | bc -l) )); then
    log_info "Installing vnstat 2.6 from source..."
    
    # Install build dependencies
    apt-get install -y libsqlite3-dev >/dev/null 2>&1
    
    # Download and compile vnstat 2.6
    cd /root
    if wget -q https://raw.githubusercontent.com/Mrian07/ubuntu24/main/vnstat-2.6.tar.gz; then
        tar zxf vnstat-2.6.tar.gz
        cd vnstat-2.6
        
        if ./configure --prefix=/usr --sysconfdir=/etc && make && make install; then
            log_success "vnstat 2.6 compiled and installed"
        else
            log_error "Failed to compile vnstat"
        fi
        
        cd /root
        rm -f vnstat-2.6.tar.gz
        rm -rf vnstat-2.6
    else
        log_warn "Failed to download vnstat source, using system version"
    fi
else
    log_info "vnstat version $VNSTAT_VERSION is sufficient"
fi

# Configure vnstat
log_info "Configuring vnstat..."
vnstat -u -i "$NET" 2>/dev/null || true
sed -i "s/Interface \"eth0\"/Interface \"$NET\"/g" /etc/vnstat.conf 2>/dev/null || true
chown vnstat:vnstat /var/lib/vnstat -R 2>/dev/null || true

# Enable and start vnstat
systemctl enable vnstat >/dev/null 2>&1
systemctl restart vnstat >/dev/null 2>&1

if systemctl is-active --quiet vnstat; then
    log_success "vnstat is running"
else
    log_warn "vnstat failed to start"
fi

# Final cleanup
log_info "Final cleanup..."
apt-get autoremove -y >/dev/null 2>&1
apt-get autoclean -y >/dev/null 2>&1

# Display summary
clear
echo -e "${GREEN}"
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo -e "${NC}"
echo ""
echo -e "${BLUE}System Information:${NC}"
echo "  • OS: $(lsb_release -d | cut -f2)"
echo "  • Kernel: $(uname -r)"
echo "  • Network Interface: $NET"
echo ""
echo -e "${BLUE}Installed Components:${NC}"
echo "  • Core system tools"
echo "  • Network utilities"
echo "  • Web server (Nginx + PHP)"
echo "  • VPN tools (OpenVPN, Stunnel, Dropbear)"
echo "  • Monitoring tools (vnstat, htop, iftop)"
echo "  • Security tools (fail2ban, iptables)"
echo "  • Development tools (git, nodejs, python3)"
echo ""
echo -e "${BLUE}Services Status:${NC}"

# Check key services
for service in nginx vnstat fail2ban cron; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "  • $service: ${GREEN}✓ Running${NC}"
    else
        echo -e "  • $service: ${YELLOW}○ Not running${NC}"
    fi
done

echo ""
yellow "Dependencies successfully installed..."
log_success "System is ready for VPN script installation!"
echo ""

exit 0
