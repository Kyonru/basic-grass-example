#!/usr/bin/env bash
set -euo pipefail

# Config comes from .env next to this script (overridable via the environment):
#   RASPBERRY_PI_HOST / RASPBERRY_PI_USER / RASPBERRY_PI_DIR / LOVE_FILE
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

# Derive the SSH target and remote path, allowing an explicit override.
TARGET="${TARGET:-${RASPBERRY_PI_USER:?set RASPBERRY_PI_USER in .env}@${RASPBERRY_PI_HOST:?set RASPBERRY_PI_HOST in .env}}"
REMOTE_FILE="${REMOTE_FILE:-${RASPBERRY_PI_DIR:?set RASPBERRY_PI_DIR in .env}/${LOVE_FILE:?set LOVE_FILE in .env}}"

# --detach:     start it and walk away (old behaviour, with a startup check).
# --no-upload:  skip the build/upload and just (re)start what's already on the Pi.
# default:      build + upload the current code, then stream the log live.
DETACH=false
UPLOAD=true
for arg in "$@"; do
  case "$arg" in
    --detach) DETACH=true ;;
    --no-upload) UPLOAD=false ;;
  esac
done

echo "Running on Raspberry Pi..."

# Build the .love from source and push it, so the Pi never runs stale code.
# Skipping this is the #1 way to "fix" a bug locally yet keep seeing it on the Pi.
if [[ "$UPLOAD" == true ]]; then
  echo "Building ${LOVE_FILE} from ${LOVE_SOURCE_DIR}/ ..."
  ( cd "$SCRIPT_DIR" && bash zip.bash )
  echo "Uploading to ${TARGET}:${REMOTE_FILE} ..."
  ssh "$TARGET" "mkdir -p '${RASPBERRY_PI_DIR}'"
  scp "$SCRIPT_DIR/$LOVE_FILE" "$TARGET:$REMOTE_FILE"
fi

if [[ "$DETACH" == true ]]; then
  ssh "$TARGET" "bash -s" <<EOF
set -e

if [ -f /tmp/love.pid ]; then
  kill \$(cat /tmp/love.pid) 2>/dev/null || true
  rm -f /tmp/love.pid
fi
rm -f /tmp/love.log

DISPLAY=:0 nohup love "$REMOTE_FILE" > /tmp/love.log 2>&1 < /dev/null &
echo \$! > /tmp/love.pid

sleep 2

if kill -0 \$(cat /tmp/love.pid) 2>/dev/null; then
  echo "LOVE started (pid \$(cat /tmp/love.pid)), detached."
  echo "NOTE: a live process does NOT mean no error — LOVE keeps running on its"
  echo "      error screen. Re-run without --detach to see the traceback."
else
  echo "LOVE exited or crashed during startup:"
  echo "---- LOVE LOG ----"
  cat /tmp/love.log 2>/dev/null || echo "No log file created."
  echo "------------------"
  exit 1
fi
EOF
  exit 0
fi

# Default: launch, then stream the log until LOVE dies (or you Ctrl+C).
# Streaming is what surfaces the traceback: an instancing/Lua error throws LOVE
# onto its error screen WITHOUT exiting, so a one-shot tail or a PID check would
# miss it. The trap kills LOVE on the Pi when you disconnect, so it doesn't leak.
ssh "$TARGET" "bash -s" <<EOF
set -e
trap 'kill \$LOVE_PID 2>/dev/null || true' EXIT

if [ -f /tmp/love.pid ]; then
  kill \$(cat /tmp/love.pid) 2>/dev/null || true
  rm -f /tmp/love.pid
fi
rm -f /tmp/love.log
: > /tmp/love.log

DISPLAY=:0 nohup love "$REMOTE_FILE" > /tmp/love.log 2>&1 < /dev/null &
LOVE_PID=\$!
echo \$LOVE_PID > /tmp/love.pid

echo "LOVE started (pid \$LOVE_PID). Streaming output — Ctrl+C to stop."
echo "----------------------------------------"

# Follow from the top of the (freshly truncated) log so startup output isn't
# lost, and stop automatically if the process actually exits.
tail -n +1 -f --pid=\$LOVE_PID /tmp/love.log || true

echo "----------------------------------------"
if wait \$LOVE_PID; then
  echo "LOVE exited cleanly."
else
  status=\$?
  echo "LOVE exited with status \$status — traceback (if any) is above."
  exit \$status
fi
EOF
