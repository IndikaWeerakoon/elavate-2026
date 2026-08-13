#!/usr/bin/env bash
# Usage: read-item.sh <table-name> <key-json>
# Example: read-item.sh incident-agent-poc-source '{"id":{"S":"record-100"}}'
set -euo pipefail

TABLE="$1"
KEY_JSON="$2"

aws dynamodb get-item --table-name "$TABLE" --key "$KEY_JSON" --output json
