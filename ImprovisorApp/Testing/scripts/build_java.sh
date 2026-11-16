#!/bin/bash
# Build the original Java Impro-Visor engine plus the golden driver, headless.
#
# Nothing under <repo>/src is modified. The source is copied to a scratch
# directory (Testing/.build/javasrc) where three mechanical rewrites make all
# randomness come from one seedable stream (imp.harness.Rng), and where
# imp/util/ErrorLog.java is replaced by a headless stub. See HARNESS_PLAN.md.
#
# Needs a JDK 9+ (for `--release 8`). Uses $JAVA_HOME, else Android Studio's
# bundled JBR, else whatever `javac` is on PATH.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TESTING="$(dirname "$HERE")"
REPO="$(cd "$TESTING/../.." && pwd)"
BUILD="$TESTING/.build"

if [ -z "${JAVA_HOME:-}" ]; then
  AS="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  if [ -x "$AS/bin/javac" ]; then export JAVA_HOME="$AS"; fi
fi
JAVAC="${JAVA_HOME:+$JAVA_HOME/bin/}javac"

# Third-party jars the Ant/Ivy build declares (ivy.xml) plus their transitive
# compile-time needs. Same destination Ivy uses: <repo>/lib (git-ignored).
mkdir -p "$REPO/lib"
fetch() {
  local f="$REPO/lib/$(basename "$1")"
  [ -f "$f" ] || curl -sfSL -o "$f" "https://repo1.maven.org/maven2/$1"
}
fetch net/mikera/mathz/0.3.0/mathz-0.3.0.jar
fetch us/bpsm/edn-java/0.4.4/edn-java-0.4.4.jar
fetch org/apache/commons/commons-configuration2/2.0/commons-configuration2-2.0.jar
fetch org/apache/commons/commons-lang3/3.3.2/commons-lang3-3.3.2.jar
fetch commons-logging/commons-logging/1.2/commons-logging-1.2.jar

rm -rf "$BUILD/javasrc" "$BUILD/classes"
mkdir -p "$BUILD/javasrc" "$BUILD/classes"
rsync -a --include='*/' --include='*.java' --exclude='*' "$REPO/src/" "$BUILD/javasrc/"

# 1. Seedable randomness (mechanical; engine logic untouched).
find "$BUILD/javasrc/imp" -name "*.java" -print0 | xargs -0 perl -pi -e '
  s/\bjava\.lang\.Math\.random\(\)/imp.harness.Rng.random()/g;
  s/(?<![\w.])Math\.random\(\)/imp.harness.Rng.random()/g;
  s/\bnew\s+(java\.util\.)?Random\(\s*\)/imp.harness.Rng.get()/g;
  s/\bCollections\.shuffle\(\s*(\w+)\s*\)/Collections.shuffle($1, imp.harness.Rng.get())/g;
'
# 2. Headless overrides and the driver itself.
rsync -a "$TESTING/java-driver/overrides/" "$BUILD/javasrc/"
rsync -a "$TESTING/java-driver/imp/" "$BUILD/javasrc/imp/"

# Record what the rewrite touched, for the log.
grep -rl "imp.harness.Rng" "$BUILD/javasrc" | sed "s|$BUILD/javasrc/||" | sort > "$BUILD/rng-rewritten-files.txt"

find "$BUILD/javasrc" -name '*.java' ! -name package-info.java > "$BUILD/sources.txt"
"$JAVAC" -nowarn --release 8 -encoding ISO-8859-1 -d "$BUILD/classes" \
  -cp "$REPO/lib/*" @"$BUILD/sources.txt" 2>&1 | grep -v -E '^(Note:|warning:|[0-9]+ warning)' || true

[ -f "$BUILD/classes/imp/harness/GoldenDriver.class" ] || { echo "Java build FAILED" >&2; exit 1; }
echo "Java engine + driver built in $BUILD/classes ($(wc -l < "$BUILD/rng-rewritten-files.txt" | tr -d ' ') files use the seeded stream)"
