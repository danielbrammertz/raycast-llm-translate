#!/bin/bash
# Compile the native overlay helpers (result pill + input prompt) and install them where the
# extension looks for them.
set -euo pipefail
cd "$(dirname "$0")"
BIN_DIR="$HOME/.config/raycast-llm-translate/bin"
mkdir -p "$BIN_DIR"
swiftc -O -swift-version 5 -o "$BIN_DIR/llm-pill" pill.swift
echo "installed $BIN_DIR/llm-pill"
swiftc -O -swift-version 5 -o "$BIN_DIR/llm-input" input-box.swift
echo "installed $BIN_DIR/llm-input"
