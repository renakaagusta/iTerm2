#!/bin/bash
# Manual smoke tests for the iterm CLI tool.
# Requires iTerm2 to be running and the iterm2 Python package installed.
#
# Usage:
#   chmod +x tests/test_iterm_cli.sh
#   ./tests/test_iterm_cli.sh

set -e

if ! command -v iterm &>/dev/null; then
    echo "ERROR: 'iterm' command not found. Install with:"
    echo "  pip install -e api/library/python/iterm2"
    exit 1
fi

echo "=== iterm CLI smoke tests ==="
echo ""

echo "[1/5] Testing: iterm new-window"
iterm new-window
sleep 1

echo "[2/5] Testing: iterm open /tmp"
iterm open /tmp
sleep 1

echo "[3/5] Testing: iterm split-h"
iterm split-h
sleep 1

echo "[4/5] Testing: iterm split-v"
iterm split-v
sleep 1

echo "[5/5] Testing: iterm close"
iterm close
sleep 1

echo ""
echo "=== All smoke tests passed. ==="
