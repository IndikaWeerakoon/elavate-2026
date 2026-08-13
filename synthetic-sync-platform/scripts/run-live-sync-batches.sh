#!/usr/bin/env bash
# Seeds 10 records every 5 minutes for 1 hour 10 minutes (14 ticks x 10 = 140
# records), mixing success and varied error scenarios per tick. See
# seed-sync-batch.js for the category mix.
set -euo pipefail
cd "$(dirname "$0")"

TOTAL_TICKS=14
INTERVAL_SECONDS=300

for tick in $(seq 1 "$TOTAL_TICKS"); do
  echo "=== Tick ${tick}/${TOTAL_TICKS} at $(date -u +%FT%TZ) ==="
  node seed-sync-batch.js "$tick"
  if [ "$tick" -lt "$TOTAL_TICKS" ]; then
    sleep "$INTERVAL_SECONDS"
  fi
done

echo "All ${TOTAL_TICKS} ticks complete ($(($TOTAL_TICKS * 10)) records seeded)."
