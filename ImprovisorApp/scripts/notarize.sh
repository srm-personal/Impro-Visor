#!/bin/zsh
# Notarize and staple the DMG. One-time setup (your Apple ID + an app-specific
# password from appleid.apple.com):
#   xcrun notarytool store-credentials LeadsheetStudio --apple-id <you@example.com> --team-id 65KL68N9K8
set -euo pipefail
cd "$(dirname "$0")/.."
DMG=${DMG:-$(ls -t build/Leadsheet-Studio-*.dmg | head -1)}
PROFILE=${PROFILE:-LeadsheetStudio}
echo "Submitting $DMG for notarization…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
# Prove Gatekeeper accepts the app inside the image.
MOUNT=$(hdiutil attach -nobrowse -readonly "$DMG" | tail -1 | awk -F'\t' '{print $NF}')
spctl -a -vv -t exec "$MOUNT/Leadsheet Studio.app" || true
hdiutil detach "$MOUNT" -quiet
echo "Notarized and stapled: $DMG"
