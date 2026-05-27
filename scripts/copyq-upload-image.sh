#!/bin/bash
set -e

REMOTE_HOST="p-freyr-2"
REMOTE_DIR="/data/raghav/transfer"
FILENAME="img_$(date +%Y%m%d_%H%M%S%3N).png"
TMP="/tmp/$FILENAME"

cat > "$TMP"

scp "$TMP" "$REMOTE_HOST:$REMOTE_DIR/$FILENAME"
rm "$TMP"

printf '%s' "$REMOTE_DIR/$FILENAME"
