#!/usr/bin/env bash
# Seeds 20 all-failure records every 5 seconds for 1 hour
# (720 ticks x 20 = 14,400 records). Resumable: pass a start tick to
# continue after an interruption instead of restarting from 1.
set -euo pipefail
cd "$(dirname "$0")"

TOTAL_TICKS=720
INTERVAL_SECONDS=5
START_TICK="${1:-1}"

for tick in $(seq "$START_TICK" "$TOTAL_TICKS"); do
  node seed-failure-batch.js "$tick"
  if [ "$tick" -eq 1 ] || [ "$((tick % 60))" -eq 0 ]; then
    echo "=== tick ${tick}/${TOTAL_TICKS} at $(date -u +%FT%TZ) ==="
  fi
  if [ "$tick" -lt "$TOTAL_TICKS" ]; then
    sleep "$INTERVAL_SECONDS"
  fi
done

echo "All ${TOTAL_TICKS} ticks complete ($((TOTAL_TICKS * 20)) records seeded)."
