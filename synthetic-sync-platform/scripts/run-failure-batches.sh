#!/usr/bin/env bash
# Seeds 20 all-failure records per tick. Defaults to every 5 minutes for
# 1 hour (12 ticks x 20 = 240 records). Override via env vars; resumable
# via a start-tick argument instead of restarting from 1.
#
# Usage: ./run-failure-batches.sh [start_tick]
#   TOTAL_TICKS=12 INTERVAL_SECONDS=300 ./run-failure-batches.sh [start_tick]
set -euo pipefail
cd "$(dirname "$0")"

TOTAL_TICKS="${TOTAL_TICKS:-12}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-300}"
START_TICK="${1:-1}"

for tick in $(seq "$START_TICK" "$TOTAL_TICKS"); do
  node seed-failure-batch.js "$tick"
  echo "=== tick ${tick}/${TOTAL_TICKS} at $(date -u +%FT%TZ) ==="
  if [ "$tick" -lt "$TOTAL_TICKS" ]; then
    sleep "$INTERVAL_SECONDS"
  fi
done

echo "All ${TOTAL_TICKS} ticks complete ($((TOTAL_TICKS * 20)) records seeded)."
