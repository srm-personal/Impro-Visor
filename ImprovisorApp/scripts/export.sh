#!/bin/zsh
# Export the archive as a Developer ID–signed app (needs a "Developer ID Application"
# certificate for team 65KL68N9K8 in the keychain; create it once in Xcode ▸ Settings ▸
# Accounts ▸ Manage Certificates).
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHIVE=${ARCHIVE:-build/LeadsheetStudio.xcarchive}
EXPORT=${EXPORT:-build/export}
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates | tail -3
APP="$EXPORT/LeadsheetStudio.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Authority=Developer ID|TeamIdentifier|flags'
echo "Exported: $APP"
