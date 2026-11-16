#!/bin/bash
# Run the golden driver: run_java.sh <mode> <args...>   (see GoldenDriver.java)
#
# The engine insists on a per-user data directory under $HOME and writes
# preferences/error logs there, so user.home is pointed at a scratch directory
# whose "impro-visor-version-10.2-files" holds a COPY of vocab/ and symlinks to
# the repo's read-only data directories. Nothing in the real home or in the
# repo's data directories is written.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TESTING="$(dirname "$HERE")"
REPO="$(cd "$TESTING/../.." && pwd)"
BUILD="$TESTING/.build"

if [ -z "${JAVA_HOME:-}" ]; then
  AS="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  if [ -x "$AS/bin/java" ]; then export JAVA_HOME="$AS"; fi
fi
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"

[ -f "$BUILD/classes/imp/harness/GoldenDriver.class" ] || "$HERE/build_java.sh"

HOME_DIR="$BUILD/home"
FILES="$HOME_DIR/impro-visor-version-10.2-files"
if [ ! -d "$FILES" ]; then
  mkdir -p "$FILES"
  cp -R "$REPO/vocab" "$FILES/vocab"
  for d in leadsheets grammars transforms fractals counts styles styleExtract midi voicings connectomes; do
    ln -s "$REPO/$d" "$FILES/$d"
  done
fi

cd "$REPO"
exec "$JAVA" -Djava.awt.headless=true -Duser.home="$HOME_DIR" -Xss16m \
  -cp "$BUILD/classes:$REPO/lib/*" imp.harness.GoldenDriver "$@"
