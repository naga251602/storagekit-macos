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

# Native Apple Silicon bundle. macOS 13 deployment target; build with Apple clang/Swift.
clang++ -std=c++20 -O2 -Wall -Wextra -arch arm64 -mmacosx-version-min=13.0 \
  engine/Scanner.cpp -framework CoreFoundation \
  -o "$APP/Contents/Resources/storagekit-scanner"

swiftc -O -parse-as-library -target arm64-apple-macosx13.0 \
  app/Models/Models.swift \
  app/Services/HistoryStore.swift \
  app/Services/ManualSelectionService.swift \
  app/Services/SettingsStore.swift \
  app/Services/TrashService.swift \
  app/ViewModels/CleanerModel.swift \
  app/Views/Components.swift \
  app/Views/MainViews.swift \
  app/Views/AdditionalViews.swift \
  -o "$APP/Contents/MacOS/StorageKit" \
  -framework SwiftUI -framework AppKit

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

codesign --force --sign - "$APP/Contents/Resources/storagekit-scanner"
codesign --force --sign - "$APP"
printf 'Built: %s\nRun: open "build/StorageKit.app"\n' "$APP"
