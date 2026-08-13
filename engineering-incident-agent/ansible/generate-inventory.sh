#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../infrastructure"
IP=$(terraform output -raw public_ip)
KEY_NAME=$(terraform output -raw ssh_command | grep -oE '[^/]+\.pem')

cd - > /dev/null

cat > inventory.ini <<EOF
[openclaw]
${IP} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/elavate-2026/${KEY_NAME}
EOF

echo "Wrote inventory.ini for ${IP}"
