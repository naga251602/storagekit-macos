#!/usr/bin/env bash
# Validates a locally built StorageKit.app (does not launch or modify anything).
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/StorageKit.app}"
EXPECTED_VERSION="${STORAGEKIT_VERSION:-5.4.1}"
INFO="$APP/Contents/Info.plist"

for executable in "$APP/Contents/MacOS/StorageKit" "$APP/Contents/Resources/storagekit-scanner"; do
  test -x "$executable" || { echo "Missing executable: $executable" >&2; exit 1; }
  lipo -archs "$executable" | tr ' ' '\n' | grep -qx arm64 || {
    echo "Missing arm64 architecture: $executable" >&2
    exit 1
  }
done

test -s "$APP/Contents/Resources/StorageKit.icns"
plutil -lint "$INFO"
name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO")
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")
[[ "$name" == StorageKit && "$identifier" == dev.storagekit.macos && "$version" == "$EXPECTED_VERSION" ]] || {
  printf 'Unexpected bundle metadata: %s / %s / %s\n' "$name" "$identifier" "$version" >&2
  exit 1
}
codesign --verify --strict --verbose=2 "$APP/Contents/Resources/storagekit-scanner"
codesign --verify --strict --verbose=2 "$APP"
printf 'Bundle verified: %s (arm64, version %s)\n' "$APP" "$version"
