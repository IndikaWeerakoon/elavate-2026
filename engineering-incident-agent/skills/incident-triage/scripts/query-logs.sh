#!/usr/bin/env bash
# Usage: query-logs.sh <log-group> <filter-substring> [start-time-ms] [end-time-ms]
# Prints matching CloudWatch log events as JSON lines: {timestamp, message}
set -euo pipefail

LOG_GROUP="$1"
FILTER="$2"
START="${3:-}"
END="${4:-}"

ARGS=(--log-group-name "$LOG_GROUP" --filter-pattern "\"$FILTER\"")
[[ -n "$START" ]] && ARGS+=(--start-time "$START")
[[ -n "$END" ]] && ARGS+=(--end-time "$END")

aws logs filter-log-events "${ARGS[@]}" \
  --query 'events[].{timestamp:timestamp,message:message}' \
  --output json
