#!/usr/bin/env bash
# Builds "Smoother Scroll.app" into build/. Needs Xcode 26 or later, for the icon.
#
#   scripts/build-app.sh [--open]
#
# VERSION, if set, is the version the app says it is; otherwise scripts/release-version.sh's.
# The app is signed ad hoc: it isn't notarized, so a downloaded copy needs its quarantine removed.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Smoother Scroll.app"
BUNDLE_ID="com.yekta.SmootherScroll"
VERSION="${VERSION:-$(scripts/release-version.sh 2>/dev/null || echo "$(tr -d '[:space:]' < VERSION).0")}"

echo "▸ Building the app…"
# SwiftPM stamps the binary as built with the SDK of its deployment target, and macOS then draws
# it in the old style. Stamping the real SDK gives it the current controls and Liquid Glass.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
BUILD=(swift build -c release --arch arm64 --arch x86_64
    -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
"${BUILD[@]}"
BINARY="$("${BUILD[@]}" --show-bin-path)/SmootherScroll"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/SmootherScroll"

# The Icon Composer icon becomes Assets.car for macOS 26, and AppIcon.icns for the ones before.
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$APP/Contents/Resources" \
    --platform macosx --target-device mac --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist "$(mktemp)" >/dev/null
test -f "$APP/Contents/Resources/Assets.car" && test -f "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Smoother Scroll</string>
    <key>CFBundleDisplayName</key><string>Smoother Scroll</string>
    <key>CFBundleExecutable</key><string>SmootherScroll</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "✓ Built $APP ($VERSION)"
if [ "${1:-}" = "--open" ]; then open "$APP"; fi
