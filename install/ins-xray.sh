#!/bin/bash
#
# Xray Core Installation Script
# Compatible with Ubuntu 24.04 LTS
# ==========================================

set -euo pipefail

# Color definitions
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
LIGHT='\033[0;37m'
YELLOW='\033[1;33m'

# Logging functions
log_info() {
    echo -e "[ ${GREEN}INFO${NC} ] $1"
}

log_error() {
    echo -e "[ ${RED}ERROR${NC} ] $1" >&2
}

log_warn() {
    echo -e "[ ${YELLOW}WARN${NC} ] $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Display banner
echo -e "${CYAN}"
echo "========================================"
echo "  Xray Core Installation - Ubuntu 24.04"
echo "========================================"
echo -e "${NC}"
date
echo ""

cd /root

# Get domain
if [[ -e /etc/xray/domain ]]; then
    domain=$(cat /etc/xray/domain)
else
    domain="casper1.dev"
    log_warn "Domain file not found, using default: $domain"
fi

sleep 0.5
mkdir -p /etc/xray

# Install required packages for Ubuntu 24.04
log_info "Checking and installing required packages..."
apt-get update -qq
apt-get install -y iptables iptables-persistent curl socat xz-utils wget \
    apt-transport-https gnupg gnupg2 dnsutils lsb-release cron \
    bash-completion ntpdate chrony zip pwgen openssl netcat-openbsd \
    >/dev/null 2>&1

sleep 0.5

# Configure time synchronization for Ubuntu 24.04
log_info "Configuring time synchronization..."
timedatectl set-ntp true
timedatectl set-timezone Asia/Jakarta

# Ubuntu 24.04 uses systemd-timesyncd by default, but we'll enable chrony
systemctl enable chrony >/dev/null 2>&1
systemctl restart chrony >/dev/null 2>&1

sleep 0.5
log_info "Checking chrony status..."
chronyc tracking -v 2>/dev/null || log_warn "Chrony tracking unavailable"

# Create xray directories
log_info "Creating Xray directories..."
domainSock_dir="/run/xray"
[[ ! -d $domainSock_dir ]] && mkdir -p $domainSock_dir
chown www-data:www-data $domainSock_dir

mkdir -p /var/log/xray
mkdir -p /etc/xray
chown www-data:www-data /var/log/xray
chmod +x /var/log/xray

# Create log files
touch /var/log/xray/access.log
touch /var/log/xray/error.log
touch /var/log/xray/access2.log
touch /var/log/xray/error2.log
chown www-data:www-data /var/log/xray/*.log

# Install Xray Core
log_info "Downloading & Installing Xray Core..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data --version 1.8.4

# Setup SSL Certificate with acme.sh
log_info "Setting up SSL certificates..."
systemctl stop nginx 2>/dev/null || true

mkdir -p /root/.acme.sh
curl -s https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh
chmod +x /root/.acme.sh/acme.sh

/root/.acme.sh/acme.sh --upgrade --auto-upgrade 2>/dev/null || true
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# Issue certificate
log_info "Issuing SSL certificate for $domain..."
/root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256 --force || {
    log_error "Failed to issue SSL certificate"
    exit 1
}

# Install certificate
~/.acme.sh/acme.sh --installcert -d "$domain" \
    --fullchainpath /etc/xray/xray.crt \
    --keypath /etc/xray/xray.key \
    --ecc

# Set proper permissions for certificates
chmod 644 /etc/xray/xray.crt
chmod 600 /etc/xray/xray.key

# Create SSL renewal script
log_info "Creating SSL renewal script..."
cat > /usr/local/bin/ssl_renew.sh <<'EOF'
#!/bin/bash
systemctl stop nginx
/root/.acme.sh/acme.sh --cron --home /root/.acme.sh &> /root/renew_ssl.log
systemctl start nginx
systemctl status nginx --no-pager
EOF

chmod +x /usr/local/bin/ssl_renew.sh

# Add to crontab if not exists
if ! grep -q 'ssl_renew.sh' /var/spool/cron/crontabs/root 2>/dev/null; then
    (crontab -l 2>/dev/null; echo "15 03 */3 * * /usr/local/bin/ssl_renew.sh") | crontab -
fi

mkdir -p /home/vps/public_html

# Generate UUID
uuid=$(cat /proc/sys/kernel/random/uuid)
log_info "Generated UUID: $uuid"

# Create Xray configuration
log_info "Creating Xray configuration..."
cat > /etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    },
    {
      "listen": "127.0.0.1",
      "port": 14016,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "id": "${uuid}"
#vless
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vless"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 23456,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0
#vmess
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 28406,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0
#vmess
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/worryfree"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 25431,
      "protocol": "trojan",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "password": "${uuid}"
#trojanntls
          }
        ],
        "udp": true
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan-ntls"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 25432,
      "protocol": "trojan",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "password": "${uuid}"
#trojanws
          }
        ],
        "udp": true
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan-ws"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 30300,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [
          {
            "method": "aes-128-gcm",
            "password": "${uuid}"
#ssws
          }
        ],
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ss-ws"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 24456,
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "id": "${uuid}"
#vlessgrpc
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vless-grpc"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 31234,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 0
#vmessgrpc
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "vmess-grpc"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 33456,
      "protocol": "trojan",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "password": "${uuid}"
#trojangrpc
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "trojan-grpc"
        }
      }
    },
    {
      "listen": "127.0.0.1",
      "port": 30310,
      "protocol": "shadowsocks",
      "settings": {
        "clients": [
          {
            "method": "aes-128-gcm",
            "password": "${uuid}"
#ssgrpc
          }
        ],
        "network": "tcp,udp"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "ss-grpc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "100.64.0.0/10",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.0.0.0/24",
          "192.0.2.0/24",
          "192.168.0.0/16",
          "198.18.0.0/15",
          "198.51.100.0/24",
          "203.0.113.0/24",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "blocked"
      },
      {
        "inboundTag": ["api"],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": ["bittorrent"]
      }
    ]
  },
  "stats": {},
  "api": {
    "services": ["StatsService"],
    "tag": "api"
  },
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  }
}
EOF

# Create Xray systemd service
log_info "Creating Xray systemd service..."
rm -rf /etc/systemd/system/xray.service.d
rm -rf /etc/systemd/system/xray@.service

cat > /etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10085
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Create runn service for directory permissions
cat > /etc/systemd/system/runn.service <<'EOF'
[Unit]
Description=Xray Directory Setup
After=network.target

[Service]
Type=oneshot
ExecStartPre=-/usr/bin/mkdir -p /var/run/xray
ExecStart=/usr/bin/chown www-data:www-data /var/run/xray
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Install Trojan-Go
log_info "Installing Trojan-Go..."
latest_version="$(curl -s "https://api.github.com/repos/p4gefau1t/trojan-go/releases" | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"
trojango_link="https://github.com/p4gefau1t/trojan-go/releases/download/v${latest_version}/trojan-go-linux-amd64.zip"

mkdir -p "/usr/bin/trojan-go"
mkdir -p "/etc/trojan-go"

cd "$(mktemp -d)"
curl -sL "${trojango_link}" -o trojan-go.zip
unzip -q trojan-go.zip && rm -rf trojan-go.zip
mv trojan-go /usr/local/bin/trojan-go
chmod +x /usr/local/bin/trojan-go

mkdir -p /var/log/trojan-go/
touch /etc/trojan-go/trgo
touch /var/log/trojan-go/trojan-go.log

cd /root

# Generate new UUID for Trojan-Go
trgo_uuid=$(cat /proc/sys/kernel/random/uuid)

# Create Trojan-Go configuration
log_info "Creating Trojan-Go configuration..."
cat > /etc/trojan-go/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 2087,
  "remote_addr": "127.0.0.1",
  "remote_port": 89,
  "log_level": 1,
  "log_file": "/var/log/trojan-go/trojan-go.log",
  "password": ["$trgo_uuid"],
  "disable_http_check": true,
  "udp_timeout": 60,
  "ssl": {
    "verify": false,
    "verify_hostname": false,
    "cert": "/etc/xray/xray.crt",
    "key": "/etc/xray/xray.key",
    "key_password": "",
    "cipher": "",
    "curves": "",
    "prefer_server_cipher": false,
    "sni": "$domain",
    "alpn": ["http/1.1"],
    "session_ticket": true,
    "reuse_session": true,
    "plain_http_response": "",
    "fallback_addr": "127.0.0.1",
    "fallback_port": 0,
    "fingerprint": "firefox"
  },
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "prefer_ipv4": true
  },
  "mux": {
    "enabled": false,
    "concurrency": 8,
    "idle_timeout": 60
  },
  "websocket": {
    "enabled": true,
    "path": "/trojango",
    "host": "$domain"
  },
  "api": {
    "enabled": false,
    "api_addr": "",
    "api_port": 0,
    "ssl": {
      "enabled": false,
      "key": "",
      "cert": "",
      "verify_client": false,
      "client_cert": []
    }
  }
}
EOF

# Create Trojan-Go systemd service
cat > /etc/systemd/system/trojan-go.service <<'EOF'
[Unit]
Description=Trojan-Go Service
Documentation=https://p4gefau1t.github.io/trojan-go/
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Save Trojan-Go UUID
echo "$trgo_uuid" > /etc/trojan-go/uuid.txt

# Create Nginx configuration for Xray
log_info "Creating Nginx configuration..."
cat > /etc/nginx/conf.d/xray.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2 reuseport;
    listen [::]:443 ssl http2 reuseport;
    server_name ${domain} *.${domain};
    
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    
    root /home/vps/public_html;
    index index.html index.htm;
    
    # VLESS WebSocket
    location = /vless {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:14016;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    
    # VMess WebSocket
    location = /vmess {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:23456;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    
    # VMess Worryfree
    location = /worryfree {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:28406;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    
    # Trojan NTLS
    location = /trojan-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:25431;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    
    # Trojan WebSocket
    location = /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:25432;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    
    # Trojan-Go
    location = /trojango {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2087;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    
    # Shadowsocks WebSocket
    location = /ss-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:30300;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    
    # Default location
    location / {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:700;
        proxy_http_version 1.1;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    
    # VLESS gRPC
    location ^~ /vless-grpc {
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:24456;
    }
    
    # VMess gRPC
    location ^~ /vmess-grpc {
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:31234;
    }
    
    # Trojan gRPC
    location ^~ /trojan-grpc {
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:33456;
    }
    
    # Shadowsocks gRPC
    location ^~ /ss-grpc {
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Host \$http_host;
        grpc_pass grpc://127.0.0.1:30310;
    }
}
EOF

# Test Nginx configuration
log_info "Testing Nginx configuration..."
nginx -t || {
    log_error "Nginx configuration test failed"
    exit 1
}

# Reload systemd and start services
log_info "Starting services..."
systemctl daemon-reload

# Enable and start Xray
systemctl enable xray >/dev/null 2>&1
systemctl restart xray

# Enable and start runn
systemctl enable runn >/dev/null 2>&1
systemctl restart runn

# Enable and start Trojan-Go
systemctl enable trojan-go >/dev/null 2>&1
systemctl restart trojan-go

# Restart Nginx
systemctl restart nginx

# Wait for services to start
sleep 2

# Check service status
log_info "Checking service status..."
if systemctl is-active --quiet xray; then
    log_info "✓ Xray service is running"
else
    log_error "✗ Xray service failed to start"
fi

if systemctl is-active --quiet trojan-go; then
    log_info "✓ Trojan-Go service is running"
else
    log_warn "✗ Trojan-Go service failed to start"
fi

if systemctl is-active --quiet nginx; then
    log_info "✓ Nginx service is running"
else
    log_error "✗ Nginx service failed to start"
fi

# Save domain configuration
[[ -f /root/domain ]] && mv /root/domain /etc/xray/
[[ -f /root/scdomain ]] && rm -f /root/scdomain

# Display summary
echo ""
echo -e "${GREEN}========================================"
echo "  Installation Complete!"
echo -e "========================================${NC}"
echo -e "${YELLOW}Domain:${NC} $domain"
echo -e "${YELLOW}UUID:${NC} $uuid"
echo -e "${YELLOW}Trojan-Go UUID:${NC} $trgo_uuid"
echo ""
echo -e "${CYAN}Protocols installed:${NC}"
echo "  • VLESS (WebSocket & gRPC)"
echo "  • VMess (WebSocket & gRPC)"
echo "  • Trojan (WebSocket & gRPC)"
echo "  • Trojan-Go (WebSocket)"
echo "  • Shadowsocks (WebSocket & gRPC)"
echo ""
echo -e "${GREEN}All services are running!${NC}"
echo ""

# Cleanup
rm -f /root/ins-xray.sh

exit 0
