#!/bin/sh
set -e

echo "NAT-PMP Port Manager for slskd starting..."

# Install required packages
echo "Installing required packages..."
apk add --no-cache curl iptables libnatpmp jq yq

# Wait for VPN tunnel to be established
echo "Waiting for VPN tunnel..."
while ! ip addr show tun0 2>/dev/null | grep -q inet; do
  echo "VPN tunnel not ready, waiting..."
  sleep 5
done
echo "VPN tunnel detected!"

# Wait for slskd to be ready
echo "Waiting for slskd API..."
while ! curl -s -f http://localhost:5030/health > /dev/null 2>&1; do
  echo "slskd not ready, waiting..."
  sleep 5
done
echo "slskd API is ready!"

# Track the last port to avoid unnecessary updates
LAST_PORT=""

# Main loop - refresh NAT-PMP every 45 minutes
while true; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Requesting NAT-PMP port forward..."

  # Request port mapping for both TCP and UDP
  echo "Requesting TCP port mapping..."
  TCP_RESULT=$(natpmpc -g REDACTED_PRIVATE_IP -a 1 0 tcp 3600 2>&1 || echo "")
  echo "TCP mapping response:"
  echo "$TCP_RESULT" | grep -E "Public IP|Mapped public port|epoch" || true

  echo ""
  echo "Requesting UDP port mapping..."
  UDP_RESULT=$(natpmpc -g REDACTED_PRIVATE_IP -a 1 0 udp 3600 2>&1 || echo "")
  echo "UDP mapping response:"
  echo "$UDP_RESULT" | grep -E "Public IP|Mapped public port|epoch" || true

  # Extract the forwarded port
  TCP_PORT=$(echo "$TCP_RESULT" | grep "Mapped public port" | awk '{print $4}')
  UDP_PORT=$(echo "$UDP_RESULT" | grep "Mapped public port" | awk '{print $4}')

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

    # Update slskd listening port via YAML API
    echo ""
    echo "Updating slskd configuration..."

    # Get API key from environment or use default auth
    SLSKD_API_URL="http://localhost:5030/api/v0"

    # Get current YAML config
    CURRENT_YAML=$(curl -s "${SLSKD_API_URL}/options/yaml" 2>/dev/null || echo "")

    if [ -z "$CURRENT_YAML" ]; then
      echo "Failed to get current slskd config, will retry..."
    else
      # Extract current listen port
      CURRENT_PORT=$(echo "$CURRENT_YAML" | yq '.soulseek.listen_port // 50300')
      echo "Current slskd listen port: $CURRENT_PORT"

      # Update port if different
      if [ "$CURRENT_PORT" != "$FORWARDED_PORT" ]; then
        echo "Updating slskd port from $CURRENT_PORT to $FORWARDED_PORT..."

        # Update the YAML with new port
        UPDATED_YAML=$(echo "$CURRENT_YAML" | yq ".soulseek.listen_port = $FORWARDED_PORT")

        # POST updated config back
        UPDATE_RESULT=$(curl -s -X POST "${SLSKD_API_URL}/options/yaml" \
          -H "Content-Type: text/plain" \
          -d "$UPDATED_YAML" 2>&1)

        if [ $? -eq 0 ]; then
          echo "slskd port successfully updated to $FORWARDED_PORT"
        else
          echo "Failed to update slskd port"
          echo "Error: $UPDATE_RESULT"
        fi
      else
        echo "slskd already using port $FORWARDED_PORT (no update needed)"
      fi
    fi
  else
    echo "NAT-PMP request failed or returned invalid port, will retry..."
  fi

  # Show current iptables rules for debugging
  echo "Current VPN interface (tun0) firewall rules:"
  iptables -L INPUT -n -v | grep tun0 | grep -E "ACCEPT.*dpt:" || echo "  No specific port rules found"

  # Sleep for 45 minutes before refreshing
  echo "Sleeping for 45 minutes before next refresh..."
  sleep 2700
done
