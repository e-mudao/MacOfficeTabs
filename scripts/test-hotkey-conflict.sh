#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/hotkey-probe
cp scripts/hotkey-conflict-main.swift build/hotkey-probe/main.swift
swiftc Sources/MacOfficeTabs/ShortcutController.swift build/hotkey-probe/main.swift \
    -framework AppKit -framework Carbon -o build/hotkey-probe/HotkeyConflictProbe
swiftc scripts/hotkey-occupier.swift -framework AppKit -framework Carbon -o build/hotkey-probe/HotkeyOccupier
build/hotkey-probe/HotkeyConflictProbe "$PWD/build/hotkey-probe/HotkeyOccupier"
