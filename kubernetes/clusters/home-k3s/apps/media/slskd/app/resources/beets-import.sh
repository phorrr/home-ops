#!/bin/bash
set -e

REDIS_HOST="${REDIS_HOST:-REDACTED_REDIS_HOST}"
REDIS_PORT="${REDIS_PORT:-6379}"
QUEUE_NAME="${QUEUE_NAME:-beets-import-queue}"

echo "Popping message from Redis queue: $QUEUE_NAME"

# Use Python for reliable Redis RPOP (beets image has python)
MESSAGE=$(python3 << PYTHON
import socket
import sys

host = "${REDIS_HOST}"
port = ${REDIS_PORT}
queue = "${QUEUE_NAME}"

# Build RESP command: RPOP queue
cmd = f"*2\r\n\$4\r\nRPOP\r\n\${len(queue)}\r\n{queue}\r\n"

try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect((host, port))
    s.sendall(cmd.encode())

    # Read response
    response = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        response += chunk
        if b"\r\n" in response[1:]:  # Got complete response
            break
    s.close()

    resp = response.decode().strip()

    # Parse RESP bulk string: \$len\r\nmessage
    if resp.startswith("\$-1"):
        print("")  # Empty = no message
    elif resp.startswith("\$"):
        # Extract message after first \r\n
        parts = resp.split("\r\n", 1)
        if len(parts) > 1:
            print(parts[1])
        else:
            print("")
    else:
        print("")
except Exception as e:
    print("", file=sys.stderr)
    sys.exit(0)
PYTHON
)

if [ -z "$MESSAGE" ]; then
  echo "ERROR: No message in queue or failed to connect"
  exit 1
fi

echo "Message: $MESSAGE"

# Extract the import path from the JSON message
IMPORT_PATH=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('localDirectoryName') or d.get('importPath') or '')" "$MESSAGE" 2>/dev/null || echo "")

if [ -z "$IMPORT_PATH" ]; then
  echo "No specific path in message, using default"
  IMPORT_PATH="/music-incoming/complete"
fi

echo "Starting beets import for: $IMPORT_PATH"

if [ ! -d "$IMPORT_PATH" ]; then
  echo "ERROR: Directory does not exist: $IMPORT_PATH"
  exit 1
fi

beet import -q "$IMPORT_PATH"
echo "Beets import completed"
