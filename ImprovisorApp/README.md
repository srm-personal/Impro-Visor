# Leadsheet Studio

A native macOS leadsheet editor and jazz play-along engine — a Swift port of
[Impro-Visor](https://www.cs.hmc.edu/~keller/jazz/improvisor/) (Robert Keller,
Harvey Mudd College).

Write the changes, enter or generate a melody on a real staff, and play along
with a rhythm section in any of 145 accompaniment styles. Ships with the whole
Impro-Visor library: 3,280 leadsheets, styles, solo grammars and the chord
vocabulary.

## Install

Download `Leadsheet-Studio-<version>.dmg` from the
[Releases](https://github.com/srm-personal/Impro-Visor/releases) page, open it
and drag **Leadsheet Studio** to Applications. The app is signed with a
Developer ID and notarized by Apple, so it opens without warnings.
Requires macOS 14 or later.

## What it does

- **Notation editor.** Click the staff to place notes (with harmonic snapping
  to the current chord), or type them: `A`–`G` enter pitches, `1 2 4 8 6` set
  the value, `.` dot, `3` triplet, `-` tie, `R` rest, arrows move, `⌘Z` undo.
  An on-screen piano and a MIDI keyboard also enter notes.
- **Chords.** Click above any bar and type `Dm7 G7` with autocomplete.
  Sections change the style mid-form. Transpose melody, chords or both.
- **Play-along.** Bass, piano comping and drums generated from the style,
  with count-in, looping, live tempo, a mixer, and swing feel. Output through
  the built-in synth or any MIDI destination (GarageBand, hardware).
- **Solos.** Generate a solo over the selection or as a new chorus from any of
  the bundled grammars, then edit it like any melody.
- **Files.** Opens and saves Impro-Visor `.ls` files losslessly; exports MIDI
  and PDF; prints.

## Build from source

Requirements: Xcode 26 (Swift 6), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd ImprovisorApp
swift test                 # engine + kit tests (SwiftPM)
./scripts/build.sh         # xcodegen + xcodebuild → build/DerivedData/…/LeadsheetStudio.app
./scripts/test.sh          # SwiftPM tests + app-hosted tests
./scripts/uitest.sh        # XCUITest smoke test
./scripts/snapshot.sh      # render notation PNGs to /tmp/leadsheet-snapshots
```

Layout:

| Path | What |
|---|---|
| `Sources/ImprovisorEngine` | Pure engine: Polya S-expression reader, model, `.ls`/`.sty`/`.grammar` parsers, accompaniment, voicing, solo grammar, swing, transport, MIDI. |
| `Sources/LeadsheetKit` | SwiftUI document, notation layout + renderer, editor, chords, transport UI, library, inspector, print. |
| `App/` | XcodeGen spec (`project.yml`) and the app target. Regenerate with `scripts/gen.sh`; never hand-edit the `.xcodeproj`. |
| `Sources/improvisor-demo` | Command-line demo/exporter. |

Releases: see [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).

## Credits and license

Leadsheet Studio is based on Impro-Visor, copyright Robert Keller and Harvey
Mudd College. The styles, grammars, vocabulary and leadsheets ship unchanged
from Impro-Visor and remain the work of their contributors.

Leadsheet Studio is free software under the
[GNU General Public License v2 or later](../LICENSE.txt). It is an independent
port and is not endorsed by the Impro-Visor authors.
