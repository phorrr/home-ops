#!/bin/sh
set -e

echo "NAT-PMP Port Manager starting..."

# Install required packages
echo "Installing required packages..."
apk add --no-cache curl iptables libnatpmp

# Wait for VPN tunnel to be established
echo "Waiting for VPN tunnel..."
while ! ip addr show tun0 2>/dev/null | grep -q inet; do
  echo "VPN tunnel not ready, waiting..."
  sleep 5
done
echo "VPN tunnel detected!"

# Wait for qBittorrent to be ready
echo "Waiting for qBittorrent API..."
while ! curl -s -f http://localhost:8080 > /dev/null; do
  echo "qBittorrent not ready, waiting..."
  sleep 5
done
echo "qBittorrent API is ready!"

# Track the last port to avoid unnecessary updates
LAST_PORT=""

# Main loop - refresh NAT-PMP every 45 minutes
while true; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Requesting NAT-PMP port forward..."
  
  # Use natpmpc to request port mapping for both TCP and UDP
  # NAT-PMP requires separate requests for TCP and UDP
  # -g: gateway, -a: add mapping (internal port, external port, protocol, lifetime)
  # Using port 1 internal, 0 external (auto-assign), 3600 seconds (1 hour) lifetime
  
  echo "Requesting TCP port mapping..."
  TCP_RESULT=$(natpmpc -g REDACTED_PRIVATE_IP -a 1 0 tcp 3600 2>&1 || echo "")
  echo "TCP mapping response:"
  echo "$TCP_RESULT" | grep -E "Public IP|Mapped public port|epoch"
  
  echo ""
  echo "Requesting UDP port mapping..."
  UDP_RESULT=$(natpmpc -g REDACTED_PRIVATE_IP -a 1 0 udp 3600 2>&1 || echo "")
  echo "UDP mapping response:"
  echo "$UDP_RESULT" | grep -E "Public IP|Mapped public port|epoch"
  
  # Extract the forwarded port from natpmpc output (should be same for both)
  # Output format: "Mapped public port 46493 protocol TCP to local port 0 lifetime 3600"
  TCP_PORT=$(echo "$TCP_RESULT" | grep "Mapped public port" | awk '{print $4}')
  UDP_PORT=$(echo "$UDP_RESULT" | grep "Mapped public port" | awk '{print $4}')
  
  # Use TCP port as primary (they should be the same)
  FORWARDED_PORT=$TCP_PORT
  
  if [ "$TCP_PORT" != "$UDP_PORT" ]; then
    echo "Warning: TCP port ($TCP_PORT) differs from UDP port ($UDP_PORT)"
  fi
  
  echo ""
  echo "Port mapping summary: TCP=$TCP_PORT UDP=$UDP_PORT (using $FORWARDED_PORT)"
  
  if [ -n "$FORWARDED_PORT" ] && [ "$FORWARDED_PORT" != "0" ]; then
    echo "NAT-PMP allocated port: $FORWARDED_PORT"
    
    # Update iptables rules if port changed
    if [ "$LAST_PORT" != "$FORWARDED_PORT" ]; then
      # Remove old port rules if they exist
      if [ -n "$LAST_PORT" ]; then
        echo "Removing old iptables rules for port $LAST_PORT"
        iptables -D INPUT -i tun0 -p tcp --dport $LAST_PORT -j ACCEPT 2>/dev/null || true
        iptables -D INPUT -i tun0 -p udp --dport $LAST_PORT -j ACCEPT 2>/dev/null || true
      fi
      
      # Add new port rules for VPN interface
      echo "Adding iptables rules for port $FORWARDED_PORT on tun0"
      iptables -A INPUT -i tun0 -p tcp --dport $FORWARDED_PORT -j ACCEPT
      iptables -A INPUT -i tun0 -p udp --dport $FORWARDED_PORT -j ACCEPT
      
      LAST_PORT=$FORWARDED_PORT
    fi
    
    # Update qBittorrent listening port
    echo ""
    echo "Updating qBittorrent configuration..."
    
    # Get session cookie (empty password for initial setup)
    LOGIN_RESULT=$(curl -s -c /tmp/cookies.txt \
      --data "username=admin&password=" \
      http://localhost:8080/api/v2/auth/login 2>&1)
    echo "qBittorrent login: $LOGIN_RESULT"
    
    # Get current listening port
    CURRENT_PORT=$(curl -s -b /tmp/cookies.txt \
      http://localhost:8080/api/v2/app/preferences 2>/dev/null | \
      grep -o '"listen_port":[0-9]*' | cut -d: -f2)
    
    echo "Current qBittorrent listening port: $CURRENT_PORT"
    
    # Update port if different
    if [ "$CURRENT_PORT" != "$FORWARDED_PORT" ]; then
      echo "Updating qBittorrent port from $CURRENT_PORT to $FORWARDED_PORT..."
      UPDATE_RESULT=$(curl -s -b /tmp/cookies.txt \
        --data "json={\"listen_port\":$FORWARDED_PORT}" \
        http://localhost:8080/api/v2/app/setPreferences 2>&1)
      
      if [ $? -eq 0 ]; then
        echo "qBittorrent port successfully updated to $FORWARDED_PORT"
        echo "Update response: $UPDATE_RESULT"
      else
        echo "Failed to update qBittorrent port"
        echo "Error: $UPDATE_RESULT"
      fi
    else
      echo "qBittorrent already using port $FORWARDED_PORT (no update needed)"
    fi
  else
    echo "NAT-PMP request failed or returned invalid port, will retry..."
  fi
  
  # Show current iptables rules for debugging
  echo "Current VPN interface (tun0) firewall rules:"
  iptables -L INPUT -n -v | grep tun0 | grep -E "ACCEPT.*dpt:" || echo "  No specific port rules found"
  
  # Sleep for 45 minutes before refreshing (renew before 1 hour expiry)
  echo "Sleeping for 45 minutes before next refresh..."
  sleep 2700
done