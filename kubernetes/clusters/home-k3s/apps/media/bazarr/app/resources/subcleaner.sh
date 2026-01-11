#!/usr/bin/env bash

printf "Cleaning subtitles for '%s' ...\n" "$1"
python3 /subcleaner/subcleaner/subcleaner.py "$1" -s

if [[ -n "$JELLYFIN_API_KEY" ]]; then
    printf "Refreshing Jellyfin library for '%s' ...\n" "$(dirname "$1")"
    /usr/bin/curl -X POST \
        -H "X-MediaBrowser-Token: ${JELLYFIN_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"Updates\": [{\"Path\": \"$(dirname "$1")\", \"UpdateType\": \"Modified\"}]}" \
        --no-progress-meter \
        "http://jellyfin.media.svc.cluster.local:8096/Library/Media/Updated"
fi
