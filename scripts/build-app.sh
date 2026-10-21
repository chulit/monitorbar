#!/bin/bash
# Builds MonitorBar.app into dist/ (ad-hoc signed, for personal use).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="dist/MonitorBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MonitorBar "$APP/Contents/MacOS/MonitorBar"
cp packaging/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "Built: $PWD/$APP"
echo "Run it with: open \"$APP\""
