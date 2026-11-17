#!/bin/bash
# Regenerate EVERY golden from the Java original, reproducibly:
#   goldens/java-random-vectors.tsv   java.util.Random reference values
#   goldens/parse/*.tsv               element counts for every data file
#   goldens/cases.tsv, tunes.tsv      the case matrix (make_cases.py)
#   goldens/accompaniment/*.events.txt  one event dump per case
#   goldens/solo-cases.tsv, solo/*.solo.txt  seeded grammar solos (3 stages each)
# .mid files for listening go to Testing/.build/midi (not committed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TESTING="$(dirname "$HERE")"
REPO="$(cd "$TESTING/../.." && pwd)"
G="$TESTING/goldens"
B="$TESTING/.build"

"$HERE/build_java.sh"
mkdir -p "$G/parse" "$B"

"$HERE/run_java.sh" rng "$G/java-random-vectors.tsv" 2>/dev/null

(cd "$REPO" && find leadsheets -name '*.ls' | LC_ALL=C sort) > "$B/leadsheets.txt"
"$HERE/run_java.sh" counts "$B/leadsheets.txt" "$G/parse/leadsheet-counts.tsv" 2>/dev/null
"$HERE/run_java.sh" styles "$G/parse/style-counts.tsv" 2>/dev/null

python3 "$HERE/make_cases.py"

rm -rf "$B/render" && mkdir -p "$B/render"
"$HERE/run_java.sh" render "$G/cases.tsv" "$B/render" 2> "$B/render.log" || { tail -20 "$B/render.log"; exit 1; }
rm -rf "$G/accompaniment" "$B/midi" && mkdir -p "$G/accompaniment" "$B/midi"
mv "$B/render"/*.events.txt "$G/accompaniment/"
mv "$B/render"/*.mid "$B/midi/" 2>/dev/null || true
"$HERE/generate_solo_goldens.sh"
echo "solo goldens: $(ls "$G/solo" | wc -l | tr -d ' ') cases, $(grep -l '^# threw' "$G/solo"/*.txt | wc -l | tr -d ' ') where Java threw"

echo "goldens: $(ls "$G/accompaniment" | wc -l | tr -d ' ') accompaniment cases, $(du -sh "$G/accompaniment" | cut -f1)"
grep -l '^# threw' "$G/accompaniment"/*.txt | wc -l | xargs echo "cases where Java threw:"
