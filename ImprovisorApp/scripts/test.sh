#!/bin/zsh
# Run every test: SwiftPM (engine + kit) then the Xcode app tests.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test 2>&1 | grep -E 'error:|Executed .* tests' | tail -1
./scripts/gen.sh
xcodebuild -project App/LeadsheetStudio.xcodeproj -scheme LeadsheetStudio -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test "$@" 2>&1 | grep -E 'error:|failed|Executed .* tests|TEST' | tail -5
