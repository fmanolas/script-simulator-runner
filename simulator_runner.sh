#!/bin/bash

# Default config
LOG_DIR="$HOME/simulator-logs"
SCRIPT_NAME="./lunchtime-simulator"
TIMEOUT_HOURS=5
CORES_PER_RUN=8
CHECK_INTERVAL=300  # seconds to wait before retrying download

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-dir)
      LOG_DIR="$2"
      shift 2
      ;;
    --binary-path)
      SCRIPT_NAME="$2"
      shift 2
      ;;
    --timeout-hours)
      TIMEOUT_HOURS="$2"
      shift 2
      ;;
    *)
      echo "❌ Unknown argument: $1"
      echo "Usage: $0 [--log-dir PATH] [--binary-path PATH] [--timeout-hours N]"
      exit 1
      ;;
  esac
done

RUNTIME_LIMIT="${TIMEOUT_HOURS}h"

# Timestamp helper
timestamp() {
  date +"[%Y-%m-%d %H:%M:%S]"
}

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Determine architecture and OS
ARCH=$(uname -m)
OS=$(uname | tr '[:upper:]' '[:lower:]')

case "$OS-$ARCH" in
  linux-x86_64)
    SIMULATOR_URL="https://releases.quilibrium.com/lunchtime-simulator-linux-amd64"
    ;;
  linux-aarch64 | linux-arm64)
    SIMULATOR_URL="https://releases.quilibrium.com/lunchtime-simulator-linux-arm64"
    ;;
  darwin-arm64)
    SIMULATOR_URL="https://releases.quilibrium.com/lunchtime-simulator-darwin-arm64"
    ;;
  *)
    echo "$(timestamp) ❌ Unsupported OS/Arch: $OS-$ARCH"
    exit 1
    ;;
esac

echo "$(timestamp) 🧬 Auto-detected system: $OS-$ARCH"
echo "$(timestamp) 🌐 Will download simulator from: $SIMULATOR_URL"

# Auto-download binary if missing
if [ ! -f "$SCRIPT_NAME" ]; then
  echo "$(timestamp) ⚠️ Simulator binary not found at '$SCRIPT_NAME'."
  echo "$(timestamp) ⬇️ Attempting to download from: $SIMULATOR_URL"

  while true; do
    HTTP_STATUS=$(curl -s -L -o "$SCRIPT_NAME" -w "%{http_code}" "$SIMULATOR_URL")
    if [ "$HTTP_STATUS" -eq 200 ]; then
      chmod +x "$SCRIPT_NAME"
      echo "$(timestamp) ✅ Downloaded and made executable: $SCRIPT_NAME"
      break
    else
      echo "$(timestamp) ❌ Download failed (HTTP $HTTP_STATUS). Retrying in $((CHECK_INTERVAL/60)) minutes..."
      sleep $CHECK_INTERVAL
    fi
  done
fi

# CPU setup
TOTAL_CORES=$(nproc)
MAX_PARALLEL_RUNS=$((TOTAL_CORES / CORES_PER_RUN))

if [ "$MAX_PARALLEL_RUNS" -lt 1 ]; then
  echo "$(timestamp) ❌ Not enough CPU cores. Require at least $CORES_PER_RUN cores."
  exit 1
fi

echo "$(timestamp) 🧠 Detected $TOTAL_CORES cores. Running $MAX_PARALLEL_RUNS simulator slots."
echo "$(timestamp) 📁 Logs: $LOG_DIR"
echo "$(timestamp) 🔧 Simulator binary: $SCRIPT_NAME"
echo "$(timestamp) ⏳ Timeout per run: $RUNTIME_LIMIT"

# Run one slot (loop forever)
run_slot() {
  local slot_id=$1
  while true; do
    local ts=$(date +"%Y%m%d_%H%M%S")_run${slot_id}
    local log="$LOG_DIR/simulator_${ts}.log"

    echo "$(timestamp) ▶️ Slot $slot_id starting new run (log: $log)"
    timeout $RUNTIME_LIMIT "$SCRIPT_NAME" > "$log" 2>&1
    local status=$?
    local duration=$(date +%s)
    duration=$((duration - $(stat -c %Y "$log")))

    echo "Exit status: $status" >> "$log"

    if [ $status -eq 0 ]; then
      echo "$(timestamp) ✅ Slot $slot_id: Run succeeded in ${duration}s."
    elif [ $status -eq 124 ]; then
      echo "$(timestamp) ⏱️ Slot $slot_id: Run timed out after $RUNTIME_LIMIT."
    else
      echo "$(timestamp) ❌ Slot $slot_id: Run failed (exit $status). See log: $log"
    fi

    echo "$(timestamp) 🔁 Slot $slot_id restarting next run..."
  done
}

# Launch N slots
for ((i=1; i<=MAX_PARALLEL_RUNS; i++)); do
  run_slot "$i" &
done

wait
