#!/usr/bin/env bash
# Usage: scan-table.sh <table-name>
# Small POC tables only - full scan is fine at this scale.
set -euo pipefail

TABLE="$1"

aws dynamodb scan --table-name "$TABLE" --output json
