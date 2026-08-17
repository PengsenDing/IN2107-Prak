#!/usr/bin/env bash
set -euo pipefail

echo "[demo] setup users would run here"
echo "Args: $*"
# Example:
# id appuser >/dev/null 2>&1 || useradd --create-home --shell /bin/bash appuser
