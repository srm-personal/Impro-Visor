#!/bin/bash
# Regenerate goldens/solo/*.solo.txt from goldens/solo-cases.tsv.
#
# One JVM per case, with a time limit: for some grammar/tune combinations
# Java's grammar expansion never terminates (BUG_LOG Q-05). Those cases get a
# golden that says "# timeout" instead of hanging the whole run.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TESTING="$(dirname "$HERE")"
G="$TESTING/goldens"
B="$TESTING/.build"
LIMIT="${SOLO_TIME_LIMIT:-30}"

rm -rf "$G/solo" "$B/solo-cases" && mkdir -p "$G/solo" "$B/solo-cases"
grep -v '^#' "$G/solo-cases.tsv" | while IFS= read -r line; do
  id="${line%%$'\t'*}"
  printf '%s\n' "$line" > "$B/solo-cases/$id.tsv"
  perl -e 'alarm shift; exec @ARGV' "$LIMIT" "$HERE/run_java.sh" solo "$B/solo-cases/$id.tsv" "$G/solo" 2>> "$B/solo.log"
  status=$?
  if [ $status -ne 0 ]; then
    pkill -f "imp.harness.GoldenDriver solo $B/solo-cases/$id.tsv" 2>/dev/null
    { printf '# id %s\n' "$id"; printf '# timeout Java did not finish within %s s (exit %s)\n' "$LIMIT" "$status"; } > "$G/solo/$id.solo.txt"
  fi
done
echo "solo: $(ls "$G/solo" | wc -l | tr -d ' ') cases, $(grep -l '^# timeout' "$G/solo"/*.txt 2>/dev/null | wc -l | tr -d ' ') timed out, $(grep -l '^# threw' "$G/solo"/*.txt 2>/dev/null | wc -l | tr -d ' ') threw"
