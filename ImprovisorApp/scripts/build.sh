#!/bin/zsh
# Build the Leadsheet Studio app (Debug by default: CONFIG=Release ./scripts/build.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/gen.sh
CONFIG=${CONFIG:-Debug}
xcodebuild -project App/LeadsheetStudio.xcodeproj -scheme LeadsheetStudio -configuration "$CONFIG" \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build "$@" | tail -3
APP="build/DerivedData/Build/Products/$CONFIG/LeadsheetStudio.app"
echo "Built: $APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier|TeamIdentifier|flags' || true
