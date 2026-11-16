#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP='build/StorageKit.app'
# Override these for a release build, e.g. STORAGEKIT_VERSION=5.4.2.
VERSION="${STORAGEKIT_VERSION:-5.4.1}"
BUILD_NUMBER="${STORAGEKIT_BUILD_NUMBER:-541}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo 'Invalid STORAGEKIT_VERSION or STORAGEKIT_BUILD_NUMBER' >&2
  exit 2
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Sparkle is an opt-in, signed-release feature; normal developer builds stay
# dependency-free. Supply an actual Sparkle.framework and its public EdDSA key
# to enable. Never distribute an update-enabled build with ad-hoc signing.
SWIFT_SPARKLE_FLAGS=()
SPARKLE_ON=0
if [[ -n "${STORAGEKIT_SPARKLE_FRAMEWORK:-}" ]]; then
  [[ -d "$STORAGEKIT_SPARKLE_FRAMEWORK" ]] || { echo 'Missing Sparkle.framework' >&2; exit 2; }
  [[ -n "${STORAGEKIT_SPARKLE_PUBLIC_KEY:-}" && -n "${STORAGEKIT_SPARKLE_FEED_URL:-}" ]] || {
    echo 'Set STORAGEKIT_SPARKLE_PUBLIC_KEY and STORAGEKIT_SPARKLE_FEED_URL' >&2; exit 2;
  }
  [[ "$STORAGEKIT_SPARKLE_FEED_URL" == https://* ]] || { echo 'Sparkle feed must use HTTPS' >&2; exit 2; }
  [[ -n "${STORAGEKIT_CODESIGN_IDENTITY:-}" && "$STORAGEKIT_CODESIGN_IDENTITY" != '-' ]] || {
    echo 'Sparkle distribution requires a real Apple signing identity (STORAGEKIT_CODESIGN_IDENTITY).' >&2; exit 2;
  }
  mkdir -p "$APP/Contents/Frameworks"
  ditto "$STORAGEKIT_SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
  SWIFT_SPARKLE_FLAGS=(-F "$APP/Contents/Frameworks" -framework Sparkle \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks')
  SPARKLE_ON=1
fi

# Native Apple Silicon bundle. macOS 13 deployment target; build with Apple clang/Swift.
clang++ -std=c++20 -O2 -Wall -Wextra -arch arm64 -mmacosx-version-min=13.0 \
  engine/Scanner.cpp -framework CoreFoundation \
  -o "$APP/Contents/Resources/storagekit-scanner"

swiftc -O -parse-as-library -target arm64-apple-macosx13.0 \
  app/Models/Models.swift \
  app/Services/HistoryStore.swift \
  app/Services/ManualSelectionService.swift \
  app/Services/SettingsStore.swift \
  app/Services/StorageKitLinks.swift \
  app/Services/UpdateService.swift \
  app/Services/TrashService.swift \
  app/ViewModels/CleanerModel.swift \
  app/Views/Components.swift \
  app/Views/MainViews.swift \
  app/Views/AdditionalViews.swift \
  -o "$APP/Contents/MacOS/StorageKit" \
  -framework SwiftUI -framework AppKit "${SWIFT_SPARKLE_FLAGS[@]}"

if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns assets/StorageKit.iconset -o "$APP/Contents/Resources/StorageKit.icns"
else
  cp assets/StorageKit.icns "$APP/Contents/Resources/StorageKit.icns"
fi
cp README.md "$APP/Contents/Resources/README.md"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StorageKit</string>
<key>CFBundleIdentifier</key><string>dev.storagekit.macos</string>
<key>CFBundleName</key><string>StorageKit</string>
<key>CFBundleDisplayName</key><string>StorageKit</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
<key>CFBundleIconFile</key><string>StorageKit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSDesktopFolderUsageDescription</key><string>StorageKit inspects files you choose for cleanup review.</string>
<key>NSDocumentsFolderUsageDescription</key><string>StorageKit inspects files you choose for cleanup review.</string>
<key>NSDownloadsFolderUsageDescription</key><string>StorageKit inspects files you choose for cleanup review.</string>
</dict></plist>
PLIST

if [[ "$SPARKLE_ON" -eq 1 ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $STORAGEKIT_SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $STORAGEKIT_SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool true' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUAutomaticallyUpdate bool true' "$APP/Contents/Info.plist"
fi
SIGN_IDENTITY="${STORAGEKIT_CODESIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/storagekit-scanner"
if [[ "$SIGN_IDENTITY" == '-' ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP"
fi
printf 'Built: %s\nRun: open "build/StorageKit.app"\n' "$APP"
