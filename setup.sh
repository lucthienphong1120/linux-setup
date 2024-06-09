#!/bin/bash

# Note:
# fix find os ver and exit

# =====================================================

# Print banner
echo "Initialize setup script..."

# Check root running
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root or with sudo."
    exit 1
else
    echo "Check root privilege is OK"
fi

# Check OS compatition
echo "This script is only available with Ubuntu 22.04"

sleep 1

# =====================================================

# Find current hostname
echo "Find current hostname..."
DEFAULT_HOSTNAME=$(hostname)

# Set hostname
read -p "Enter new hostname (default: $DEFAULT_HOSTNAME): " HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

echo "Set hostname to $HOSTNAME"

hostnamectl set-hostname $HOSTNAME
sed -i "s/127.0.1.1 $DEFAULT_HOSTNAME/127.0.1.1 $HOSTNAME/g" /etc/hosts
exec bash

sleep 1

# =====================================================

# Find network config file
echo "Find network config file..."
NETWORK_FILE=$(find /etc/netplan -type f -name '*.yaml' | head -n1)

if [ -z "$NETWORK_FILE" ]; then
    echo "Error: No network config file found in /etc/netplan"
    exit 1
fi

echo "Found network config at $NETWORK_FILE"

# With /etc/netplan/00-installer-config.yaml template as follow:
# ```
# network:
#   ethernets:
#     ens33:
#       addresses:
#         - 192.168.24.120/24
#       gateway4: 192.168.24.2
#       nameservers:
#         addresses: [8.8.8.8, 8.8.4.4]
#         search: []
#   version: 2
# ```

# Configure static IP
DEFAULT_IP=$(awk '/addresses:/{getline; print $2}' $NETWORK_FILE | head -n 1 | cut -d'/' -f1)
DEFAULT_NETMASK=$(awk '/addresses:/{getline; print $2}' $NETWORK_FILE | head -n 1 | cut -d'/' -f2)
DEFAULT_GATEWAY=$(awk '/gateway4:/{print $2}' $NETWORK_FILE)
DEFAULT_NAMESERVERS=$(awk '/nameservers:/ {getline; print $2,$3}' /etc/netplan/00-installer-config.yaml | tr -d '[]')

if [ -z "$DEFAULT_IP" ] || [ -z "$DEFAULT_NETMASK" ] || [ -z "$DEFAULT_GATEWAY" ] || [ -z "$DEFAULT_NAMESERVERS" ]; then
    echo "Failed to get network configuration from NETWORK_FILE"
    exit 1
fi

read -p "Enter new IP address (default: $DEFAULT_IP): " IP
IP=${IP:-$DEFAULT_IP}
read -p "Enter new netmask (default: $DEFAULT_NETMASK): " NETMASK
NETMASK=${NETMASK:-$DEFAULT_NETMASK}
read -p "Enter new gateway (default: $DEFAULT_GATEWAY): " GATEWAY
GATEWAY=${GATEWAY:-$DEFAULT_GATEWAY}
read -p "Enter new gateway (default: $DEFAULT_NAMESERVERS): " NAMESERVERS
NAMESERVERS=${NAMESERVERS:-$DEFAULT_NAMESERVERS}

echo "Configure static IP to $IP/$NETMASK $GATEWAY"

cat <<EOF > $NETWORK_FILE
network:
  ethernets:
    ens33:
      addresses:
        - $IP_ADDRESS/$NETMASK
      gateway4: $GATEWAY
      nameservers:
        addresses: [$NAMESERVERS]
        search: []
  version: 2
EOF

netplan apply

sleep 1

# =====================================================

# Check GPT PMBR size mismatch
echo "Check GPT PMBR size..."

GPT_CHECK=$(fdisk -l 2>&1 | grep "GPT PMBR size mismatch")

if [ -n "$GPT_CHECK" ]; then
    echo "$GPT_CHECK"
else
    echo "GPT PMBR is OK"
fi

# Resizing disk and LVM
if [ -n "$GPT_CHECK" ]; then
    echo "Resizing disk and LVM..."
    growpart /dev/sda 3
    lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
fi

sleep 1

# =====================================================

# Update package lists
echo "Update package lists and upgrade packages..."
DEFAULT_UPDATE="n"
DEFAULT_UPGRADE="n"

read -p "Update package lists [y/n] (default: $DEFAULT_UPDATE): " UPDATE
UPDATE=${UPDATE:-$DEFAULT_UPDATE}
if [[ "$UPDATE" =~ ^[Yy]$ ]]; then
  apt-get update
fi

read -p "Update package lists [y/n] (default: $DEFAULT_UPGRADE): " UPGRADE
UPGRADE=${UPGRADE:-$DEFAULT_UPGRADE}
if [[ "$UPGRADE" =~ ^[Yy]$ ]]; then
  apt-get upgrade -y
fi

sleep 1

# =====================================================

echo "Setup complete!"
