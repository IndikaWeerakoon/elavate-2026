#!/usr/bin/env bash
# Usage: resolve-service.sh <lambda-function-name-or-log-group-basename>
# Prints the service catalog entry as JSON, or nothing if unknown.
set -euo pipefail

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="$1"
NAME="${NAME##*/}" # strip /aws/lambda/ prefix if passed a full log group name

jq -e --arg name "$NAME" '.services[$name] // empty' "${BASEDIR}/config/services.json"
