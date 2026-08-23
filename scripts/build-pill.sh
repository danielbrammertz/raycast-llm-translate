#!/bin/bash
# Compile the pill overlay helper and install it where the extension looks for it.
set -euo pipefail
cd "$(dirname "$0")"
BIN_DIR="$HOME/.config/raycast-llm-translate/bin"
mkdir -p "$BIN_DIR"
swiftc -O -swift-version 5 -o "$BIN_DIR/llm-pill" pill.swift
echo "installed $BIN_DIR/llm-pill"
