#!/bin/zsh
# Regenerate App/LeadsheetStudio.xcodeproj from App/project.yml.
set -euo pipefail
cd "$(dirname "$0")/../App"
XCODEGEN=${XCODEGEN:-/usr/local/bin/xcodegen}
"$XCODEGEN" generate --quiet
