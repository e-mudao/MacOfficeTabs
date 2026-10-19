#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-icon.sh
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/build/MacOfficeTabs.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MacOfficeTabs" "$app_dir/Contents/MacOS/MacOfficeTabs"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp build/MacOfficeTabs.icns "$app_dir/Contents/Resources/MacOfficeTabs.icns"
signing_dir="$PWD/.dev-signing"
if [ -s "$signing_dir/identity-sha1" ] && [ -f "$signing_dir/development.keychain-db" ]; then
    IFS= read -r signing_identity < "$signing_dir/identity-sha1"
    IFS= read -r signing_password < "$signing_dir/password"
    /usr/bin/security unlock-keychain -p "$signing_password" "$signing_dir/development.keychain-db"
    /usr/bin/codesign --force --sign "$signing_identity" --keychain "$signing_dir/development.keychain-db" \
        --identifier local.MacOfficeTabs --timestamp=none \
        --requirements "=designated => identifier \"local.MacOfficeTabs\" and certificate leaf = H\"$signing_identity\"" "$app_dir"
else
    /usr/bin/codesign --force --sign - --identifier local.MacOfficeTabs "$app_dir"
fi
/usr/bin/codesign --verify --strict "$app_dir"
echo "Built: $app_dir"
