# SSH WebSocket Proxy - Ubuntu 24.04

WebSocket proxy untuk SSH/Dropbear dan Stunnel yang kompatibel dengan Ubuntu 24.04 LTS.

## Features

- ✅ WebSocket proxy untuk Dropbear SSH
- ✅ WebSocket proxy untuk Stunnel
- ✅ Auto-detect Python version (Python 3.x)
- ✅ Systemd service management
- ✅ Auto-restart on failure
- ✅ Logging via journald

## Requirements

- Ubuntu 24.04 LTS
- Python 3.x (auto-installed if not present)
- Root access

## Installation

```bash
cd /root
wget https://raw.githubusercontent.com/Mrian07/ubuntu24/main/sshws/insshws.sh
chmod +x insshws.sh
./insshws.sh
```

## Services Installed

### 1. ws-dropbear.service
WebSocket proxy untuk Dropbear SSH (Non-TLS)

**Default Port:** Sesuai konfigurasi di script ws-dropbear

**Service Commands:**
```bash
# Check status
systemctl status ws-dropbear

# View logs
journalctl -u ws-dropbear -f

# Restart
systemctl restart ws-dropbear

# Stop
systemctl stop ws-dropbear

# Start
systemctl start ws-dropbear
```

### 2. ws-stunnel.service
WebSocket proxy untuk Stunnel

**Default Port:** Sesuai konfigurasi di script ws-stunnel

**Service Commands:**
```bash
# Check status
systemctl status ws-stunnel

# View logs
journalctl -u ws-stunnel -f

# Restart
systemctl restart ws-stunnel
```

## Troubleshooting

### Service tidak start

1. Check logs:
```bash
journalctl -u ws-dropbear -n 50 --no-pager
```

2. Check Python version:
```bash
python3 --version
```

3. Check script permissions:
```bash
ls -la /usr/local/bin/ws-dropbear
ls -la /usr/local/bin/ws-stunnel
```

4. Test script manually:
```bash
python3 /usr/local/bin/ws-dropbear
```

### Port already in use

Check what's using the port:
```bash
netstat -tulpn | grep <port_number>
# or
ss -tulpn | grep <port_number>
```

### Python not found

Install Python 3:
```bash
apt-get update
apt-get install -y python3 python3-pip
```

## Configuration

Script locations:
- `/usr/local/bin/ws-dropbear` - Dropbear WebSocket proxy
- `/usr/local/bin/ws-stunnel` - Stunnel WebSocket proxy

Service files:
- `/etc/systemd/system/ws-dropbear.service`
- `/etc/systemd/system/ws-stunnel.service`

## Uninstallation

```bash
# Stop services
systemctl stop ws-dropbear ws-stunnel
systemctl disable ws-dropbear ws-stunnel

# Remove service files
rm -f /etc/systemd/system/ws-dropbear.service
rm -f /etc/systemd/system/ws-stunnel.service

# Remove scripts
rm -f /usr/local/bin/ws-dropbear
rm -f /usr/local/bin/ws-stunnel

# Reload systemd
systemctl daemon-reload
```

## Ubuntu 24.04 Compatibility Notes

- Uses Python 3.x (Ubuntu 24.04 default)
- Systemd service with proper capabilities
- Journal logging for better log management
- Auto-restart on failure with 5s delay
- Proper error handling and status checking

## Support

For issues and questions:
- GitHub: https://github.com/Mrian07/aingman-script
- Check logs: `journalctl -u ws-dropbear -f`
