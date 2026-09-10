#!/bin/zsh
# Archive a Release build of Leadsheet Studio (Developer ID signing is applied at export).
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/gen.sh
ARCHIVE=${ARCHIVE:-build/LeadsheetStudio.xcarchive}
rm -rf "$ARCHIVE"
xcodebuild -project App/LeadsheetStudio.xcodeproj -scheme LeadsheetStudio -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates archive | tail -3
echo "Archive: $ARCHIVE"
