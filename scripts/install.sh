#!/bin/sh
# Installs or updates Smoother Scroll in /Applications from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/yekta/smoother-scroll/main/scripts/install.sh | sh
#
# The app isn't notarized. A download from a browser is quarantined and Gatekeeper blocks it; a
# download with curl isn't, so the app opens as is.
set -eu

APP="/Applications/Smoother Scroll.app"
ZIP_URL="https://github.com/yekta/smoother-scroll/releases/latest/download/SmootherScroll.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Smoother Scroll…"
curl -fsSL "$ZIP_URL" -o "$TMP/SmootherScroll.zip"
ditto -x -k "$TMP/SmootherScroll.zip" "$TMP"

killall SmootherScroll 2>/dev/null || true
rm -rf "$APP"
mv "$TMP/Smoother Scroll.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "Installed in /Applications. Opening it…"
open "$APP"
