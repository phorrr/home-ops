#!/bin/sh
set -e

echo "qBittorrent startup script starting..."

# Wait for VPN tunnel to be established
echo "Waiting for VPN tunnel to be established..."
for i in $(seq 1 60); do
  if ip addr show tun0 2>/dev/null | grep -q inet; then
    echo "VPN tunnel interface found!"
    VPN_IP=$(ip addr show tun0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    echo "VPN IP: $VPN_IP"
    break
  fi
  echo "Waiting for VPN tunnel... ($i/60)"
  sleep 1
done

# Check if we got a VPN connection
if ! ip addr show tun0 2>/dev/null | grep -q inet; then
  echo "ERROR: VPN tunnel not established after 60 seconds!"
  exit 1
fi

# Verify external IP is through VPN
echo "Verifying VPN connection..."
EXTERNAL_IP=$(curl -s --max-time 5 https://ifconfig.me)
if [ -n "$EXTERNAL_IP" ]; then
  echo "External IP via VPN: $EXTERNAL_IP"
else
  echo "Warning: Could not verify external IP"
fi

echo "Starting qBittorrent..."
exec /entrypoint.sh