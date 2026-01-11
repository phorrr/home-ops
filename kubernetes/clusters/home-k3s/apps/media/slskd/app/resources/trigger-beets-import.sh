#!/bin/bash
set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [beets-trigger] $1"
}

# REDIS_HOST and REDIS_PORT are set via environment variables
# Resolve via kube-dns (10.31.0.10) since VPN DNS can't resolve cluster services
REDIS_HOST="${REDIS_HOST:-$(dig @10.31.0.10 REDACTED_REDIS_HOST +short)}"
REDIS_PORT="${REDIS_PORT:-6379}"
QUEUE_NAME="beets-import-queue"

log "=== Beets Import Trigger Started ==="
log "Redis host: $REDIS_HOST:$REDIS_PORT"
log "Event data: $SLSKD_SCRIPT_DATA"

# Extract directory from slskd event data
IMPORT_PATH=$(echo "$SLSKD_SCRIPT_DATA" | jq -r '.localDirectoryName // empty')

if [ -z "$IMPORT_PATH" ]; then
  log "No directory path in event data, using default"
  IMPORT_PATH="/music-incoming/complete"
else
  log "Import path from event: $IMPORT_PATH"
fi

# Create message payload
TIMESTAMP=$(date +%s)
MESSAGE=$(echo "$SLSKD_SCRIPT_DATA" | jq -c ". + {timestamp: $TIMESTAMP, importPath: \"$IMPORT_PATH\"}")

log "Pushing to queue: $QUEUE_NAME"
log "Message: $MESSAGE"

# Build Redis RESP command: LPUSH queue message
# Format: *3\r\n$5\r\nLPUSH\r\n$len\r\nqueue\r\n$len\r\nmessage\r\n
QUEUE_LEN=${#QUEUE_NAME}
MSG_LEN=${#MESSAGE}

REDIS_CMD=$(printf "*3\r\n\$5\r\nLPUSH\r\n\$%d\r\n%s\r\n\$%d\r\n%s\r\n" "$QUEUE_LEN" "$QUEUE_NAME" "$MSG_LEN" "$MESSAGE")

# Send to Redis using bash /dev/tcp and capture response
exec 3<>/dev/tcp/"$REDIS_HOST"/"$REDIS_PORT"
echo -ne "$REDIS_CMD" >&3
RESPONSE=$(timeout 5 cat <&3 || true)
exec 3>&-

if echo "$RESPONSE" | grep -q "^:"; then
  # Response starts with : which means integer (success)
  QUEUE_LENGTH=$(echo "$RESPONSE" | tr -d ':\r\n')
  log "SUCCESS: Message pushed to queue (queue length: $QUEUE_LENGTH)"
  log "KEDA will pick up the job shortly"
  log "=== Beets Import Trigger Completed ==="
else
  log "ERROR: Failed to push to Redis"
  log "Response: $RESPONSE"
  log "=== Beets Import Trigger Failed ==="
  exit 1
fi
