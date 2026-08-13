#!/usr/bin/env bash
# Usage: search-repo.sh <pattern> <repo-path>
# Wraps ripgrep with line numbers, quiet on no-match instead of erroring.
set -uo pipefail

PATTERN="$1"
REPO_PATH="${2:-$HOME/repos/synthetic-sync-platform}"

rg -n --no-heading "$PATTERN" "$REPO_PATH" || true
