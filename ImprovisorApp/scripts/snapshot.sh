#!/bin/zsh
# Render the notation snapshots (PNG) used to eyeball the renderer.
set -euo pipefail
cd "$(dirname "$0")/.."
export LEADSHEET_SNAPSHOT_DIR=${LEADSHEET_SNAPSHOT_DIR:-/tmp/leadsheet-snapshots}
swift test --filter 'SnapshotTests|testScriptedSessionSnapshot|PrintTests' 2>&1 | grep -E 'error:|Executed .* tests' | tail -1
ls -1 "$LEADSHEET_SNAPSHOT_DIR"
