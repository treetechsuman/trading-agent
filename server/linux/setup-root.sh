#!/usr/bin/env bash
# Run ONCE as root on a fresh Vultr Ubuntu 24.04 server (step 4 of LINUX_SERVER.md).
# Creates user 'trader', copies root's SSH key to it, firewall, auto updates,
# swap, desktop + VNC packages. Does NOT turn off root login yet - that is a
# separate step, after you've proved 'trader' can log in and use sudo.
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

# --- user ---
id trader >/dev/null 2>&1 || adduser --disabled-password --gecos "" trader
usermod -aG sudo trader
install -d -m 700 -o trader -g trader /home/trader/.ssh
install -m 600 -o trader -g trader /root/.ssh/authorized_keys /home/trader/.ssh/authorized_keys

# --- firewall: SSH only (the remote desktop goes through SSH) ---
apt-get -y install ufw fail2ban
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw --force enable
systemctl enable --now fail2ban

# --- automatic security updates (no automatic reboot; see weekend timer) ---
apt-get -y install unattended-upgrades
echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

# --- 2 GB swap (2 GB RAM is tight with MT5 + desktop + Claude Code) ---
# (Vultr's Ubuntu image already ships a swap partition; only add one if none.)
if [ -z "$(swapon --show --noheadings)" ] && [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf && sysctl -p /etc/sysctl.d/99-swappiness.conf
fi

# --- light desktop + VNC + tools ---
DEBIAN_FRONTEND=noninteractive apt-get -y install xfce4 xfce4-terminal dbus-x11 \
  tigervnc-standalone-server tigervnc-tools git python3-venv python3-pip curl wget

timedatectl set-timezone UTC
echo "setup-root.sh done"
