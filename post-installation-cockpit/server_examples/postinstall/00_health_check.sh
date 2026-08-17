#!/usr/bin/env bash
set -euo pipefail

echo "Hostname: $(hostname)"
echo "User: $(id)"
echo "Uptime: $(uptime -p || uptime)"
echo "Date: $(date --iso-8601=seconds 2>/dev/null || date)"
