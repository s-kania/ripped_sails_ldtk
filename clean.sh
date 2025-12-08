#!/usr/bin/env bash
set -euo pipefail

# Usage: bash clean.sh
# - Deletes generated JS bundles (main.js, renderer.js)

# Resolve repo root (script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Removing generated JS bundles..."
rm -f "$SCRIPT_DIR/app/assets/main.js" "$SCRIPT_DIR/app/assets/js/renderer.js"

echo "Clean complete."
