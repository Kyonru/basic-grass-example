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

# --detach: start it and walk away (old behaviour, with a startup check).
# default: stream the log live so a crash/traceback is visible immediately.
DETACH=false
for arg in "$@"; do
  [[ "$arg" == "--detach" ]] && DETACH=true
done

echo "Running on Raspberry Pi..."

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
