#!/bin/zsh
# Full release: bump version, archive, export, DMG, notarize, then publish a
# GitHub Release on the fork. The publish step is gated behind PUBLISH=1 so the
# outward-facing action is always a deliberate choice.
#
#   VERSION=1.0.0 ./scripts/release.sh            # build + notarize only
#   VERSION=1.0.0 PUBLISH=1 ./scripts/release.sh  # …and create the GitHub release
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${VERSION:?set VERSION=x.y.z}
export PATH="$HOME/bin/gh/bin:$PATH"

# 1. Version bump in the project spec (CURRENT_PROJECT_VERSION = build number).
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" App/project.yml
BUILD=$(( $(grep -o 'CURRENT_PROJECT_VERSION: "[0-9]*"' App/project.yml | grep -o '[0-9]*') + 1 ))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" App/project.yml

# 2. Tests, archive, export, DMG, notarize.
swift test 2>&1 | grep -E 'Executed .* tests' | tail -1
./scripts/archive.sh
./scripts/export.sh
VERSION="$VERSION" ./scripts/make_dmg.sh
DMG="build/Leadsheet-Studio-$VERSION.dmg" ./scripts/notarize.sh

# 3. Commit the version bump and tag.
git add App/project.yml App/LeadsheetStudio.xcodeproj
git commit -q -m "Leadsheet Studio $VERSION" || true
git tag -f "v$VERSION"

if [[ "${PUBLISH:-0}" != "1" ]]; then
  echo "Built build/Leadsheet-Studio-$VERSION.dmg. Re-run with PUBLISH=1 to push the tag and create the GitHub release."
  exit 0
fi

# 4. Publish (outward-facing).
git push fork swift-port
git push -f fork "v$VERSION"
NOTES=$(awk "/^## $VERSION/{flag=1;next}/^## /{flag=0}flag" CHANGELOG.md)
gh release create "v$VERSION" "build/Leadsheet-Studio-$VERSION.dmg" "build/Leadsheet-Studio-$VERSION.dmg.sha256" \
  --repo srm-personal/Impro-Visor --title "Leadsheet Studio $VERSION" --notes "$NOTES"
echo "Published https://github.com/srm-personal/Impro-Visor/releases/tag/v$VERSION"
