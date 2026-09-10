#!/bin/zsh
# Build a compressed DMG containing the exported app, an Applications shortcut,
# the GPL licence and the credits file.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${APP:-build/export/LeadsheetStudio.app}
VERSION=${VERSION:-$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)}
DMG=${DMG:-build/Leadsheet-Studio-$VERSION.dmg}
STAGE=build/dmg-stage
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Leadsheet Studio.app"
ln -s /Applications "$STAGE/Applications"
cp ../LICENSE.txt "$STAGE/LICENSE.txt"
cp scripts/README-CREDITS.txt "$STAGE/README-CREDITS.txt"
hdiutil create -volname "Leadsheet Studio $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" | tail -1
rm -rf "$STAGE"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "DMG: $DMG"
