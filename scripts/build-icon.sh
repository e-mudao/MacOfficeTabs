#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_icon="$PWD/Resources/IconDesign/MacOfficeTabs-icon-v1.png"
iconset="$PWD/build/MacOfficeTabs.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$source_icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    /usr/bin/sips -z "$doubled" "$doubled" "$source_icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$PWD/build/MacOfficeTabs.icns"
