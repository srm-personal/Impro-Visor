#!/bin/zsh
# Run the XCUITest smoke test against a fresh build.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/gen.sh
xcodebuild -project App/LeadsheetStudio.xcodeproj -scheme LeadsheetStudio -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -only-testing:LeadsheetStudioUITests test 2>&1 | grep -E 'error|failed|Executed .* tests|TEST' | tail -6
