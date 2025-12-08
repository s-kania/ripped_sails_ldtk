#!/usr/bin/env bash
set -euo pipefail

echo "[run] Building main.debug.hxml..."
if ! haxe main.debug.hxml; then
	echo "[run] ERROR: haxe main.debug.hxml failed" >&2
	exit 1
fi

echo "[run] Building renderer.debug.hxml..."
if ! haxe renderer.debug.hxml; then
	echo "[run] ERROR: haxe renderer.debug.hxml failed" >&2
	exit 1
fi

echo "[run] Starting Electron..."
cd app
npm run start