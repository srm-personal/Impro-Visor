# Differential test harness — plan

Reference = the original Java Impro-Visor 10.2. For any input, correct
behaviour is whatever Java does. This file records what was found on
orientation (2026-11-16) and how the harness is laid out.

## What is actually here

- **The Java original is this same repository.** `src/` (1,061 files),
  `build.xml`, and the data directories at the repo root are upstream
  Impro-Visor; the Swift port lives entirely in `ImprovisorApp/`. Nothing had
  to be cloned. `src/` and the data directories are treated as read-only.
- **Swift port**: SwiftPM package `ImprovisorApp/` — `ImprovisorEngine`
  (pure engine, ~7,300 lines: Polya, Model, Parsing, Style, SoloGen, Voicing,
  Audio, Export), `LeadsheetKit` (SwiftUI document/editor layer),
  `improvisor-demo` (CLI). The app target is an XcodeGen project in
  `ImprovisorApp/App` (`LeadsheetStudio`, **macOS only** — there is no iOS
  target, see BUG_LOG "decisions").
- **Data** is not copied into the package; tests read the corpus from the repo
  root (`TestData`), the app bundles the folders as resources.
  3,280 `.ls`, 145 `.sty`, 85 `.grammar`, 6 `.fv`, `vocab/My.voc`.
- **Java build**: no JDK, Ant or Homebrew on this Mac. Android Studio's bundled
  JBR (OpenJDK 21) compiles the whole tree with `javac --release 8` once the
  five jars the Ant/Ivy build would fetch are in `lib/` (git-ignored, same
  place Ivy puts them). `--release 8` is required: `Notate.java:17117` does
  not compile against the Java 9+ Swing API. All 2,700 classes build.
- **Headless**: the engine can render without `Notate`. Two things stood in
  the way, both non-engine: `ErrorLog` / `ErrorLogWithResponse` create Swing
  dialogs (replaced at build time by recording stubs), and
  `LoadAdviceCommand` opens a splash dialog (the driver loads `My.voc` into
  the `Advisor` itself and sets `ImproVisor.advisor` by reflection).

## Size of the gap (important)

The Swift engine is a compact re-implementation, not a line-by-line port:
`Style.java` + `BassPattern` + `ChordPattern` + `DrumPattern` are ~5,600 lines
of Java against ~900 of Swift, the RNG is SplitMix64, and several behaviours
were knowingly approximated (see the port's own notes: bass placement, solo
note choice, swing applied afterwards). Event-exact agreement therefore needs
those subsystems re-ported from the Java source rather than patched.

## Layout

```
Testing/
  HARNESS_PLAN.md  BUG_LOG.md  FEATURE_COVERAGE.md
  java-driver/imp/harness/   GoldenDriver.java, Rng.java   (the only new Java)
  java-driver/overrides/     headless stubs compiled instead of the originals
  scripts/build_java.sh      copy src → scratch, seed-rewrite, compile
  scripts/run_java.sh        run the driver with a scratch user.home
  scripts/generate_goldens.sh  ONE script that regenerates everything below
  goldens/java-random-vectors.tsv   java.util.Random reference values
  goldens/parse/*.tsv               per-file element counts from Java
  goldens/cases.tsv                 the tune × style × seed matrix
  goldens/accompaniment/*.events.txt  event dumps (channel tick pitch vel dur)
  .build/                    scratch (git-ignored): classes, reports, .mid
```

Swift tests live in `Tests/ImprovisorEngineTests/`:
`CorpusSweepTests` (Step 1), `JavaRandomTests`, `GoldenComparisonTests`
(Step 2). They read goldens from `Testing/goldens` and write grouped failure
reports to `Testing/.build/reports`.

## Determinism

- Every `Math.random()`, `new Random()` and `Collections.shuffle(x)` under
  `src/imp` is rewritten **in the scratch copy** to draw from one seeded
  `java.util.Random` (`imp.harness.Rng`). One stream, consumed in program
  order; the Swift engine threads one `JavaRandom` through the same call
  sites. `.build/rng-rewritten-files.txt` lists the 38 files touched.
- Styles are re-read before every case, because a leadsheet's
  `(style name (param …))` header mutates the shared `Style` object.
- The dump is sorted by (tick, channel, pitch, velocity, duration): the order
  of simultaneous events inside a `javax.sound.midi.Track` is an
  implementation detail, not engine behaviour.

## Order of work

1. Corpus sweep of the parsers (Swift vs Java counts; Swift round trip).
2. `JavaRandom` port + vectors; golden matrix; event-by-event comparison.
3. Fix the Swift engine, one root cause per commit, logged in BUG_LOG.md.
4. `FEATURE_COVERAGE.md` inventory.
5. XCUITest smoke suite for the practice loop.

## State (2026-11-16)

| Check | Before | Now |
|---|---|---|
| Leadsheets matching Java's parse (3,280) | 3,241 | 3,280 |
| Leadsheet load → save → reload stable | 3,280 | 3,280 |
| Styles matching Java's patterns (145) | 50 | 145 |
| Golden accompaniment cases identical (955; was 855) | 0 | 954 |
| — bass / chords / drums / melody tracks | 0 / 1 / 2 / 420 | 949/950 · 954/955 · 943/944 · 502/503 |

Run everything: `cd ImprovisorApp && swift test` (≈45 s). The one failing
test is `GoldenComparisonTests`: 1 case, where Java itself throws (BUG_LOG Q-04).
`IMPRO_ONLY=<case id> swift test --filter GoldenComparisonTests` renders one case. Reports land in
`Testing/.build/reports/` (`golden-diff.txt`, `swift-events/<case>.events.txt`
to diff against `goldens/accompaniment/<case>.events.txt`).

Open: Q-04 (decision), O-06 solo goldens (blocked
on `Notate`), O-04 custom voicing, O-05 channel numbers, O-07 playback
transposition. UI tests: `scripts/uitest.sh` — only the open-tune test was
verified in the agent session.

## How the engine port is organised

`Style/StyleRenderer.swift` is the port of `Style.render` and the pattern
classes; `ArrangementBuilder` is `Score.render` + `SectionInfo.render`;
`Style/ChordInterpolation.swift` is `createInterpolatedChordPart` (passing
chords, substitutions); `Util/JavaRandom.swift` is the stream. What to do next
is in `NEXT_STEPS.md`. Facts worth knowing before touching it:

- One RNG stream. Per section, in order: drum patterns for the whole section;
  then per chord: chord pattern choice (`nextInt((int)sum)`, `random <=
  weights`), one `nextInt(n)` per strike for the voicing pick (even when
  n = 1), then bass pattern choice (`random < weights`) and bass rule draws
  (`nextInt` for C/S/A; one `nextDouble` per octave step in `placePitchNear`;
  one in `pressure` when outside the soft margin).
- `findRise(root)` is negative for F, Bb, Eb, Ab, Db, Gb (flat preference), so
  spellings and voicings are transposed DOWN for those roots.
- Vocabulary voicings are tried in file order. A chosen voicing is voicing +
  extension, unsorted; placement keys on its first note. The leap measure is
  one-directional (the symmetric half is commented out in Java).
- A rest in a chord pattern resets the "previous voicing" to empty.
- Bass: notes start two octaves down, then `placePitchNear` (±11 of the last
  note) and `pressure`. Volume is a running value across the whole section.
  `N` drops its own note and adds its duration to the next segment's first
  note. If no pattern fits, the shortest longer one is used whole (overrun).
- `makeSwing` works on units including rests, beat = 120 slots from the start
  of each pattern (chords, drums) or section (bass), then every unit's length
  becomes the gap to the next unit.
- Chord patterns longer than the chord are split; the remainder carries over.

**Reading the Java:** several live-looking blocks are inside `/* … */`
(`chooseVoicings`, `placePitchNear`). Read the raw file; do not trust a
comment-stripping grep.

**Debugging a divergence:** copy `.build/classes` to a scratch dir, add a
`System.err.println` to the scratch copy under `.build/javasrc`, recompile
that one file into the copy, run one case with `GoldenDriver render`, then
restore the source. Never regenerate goldens from a patched build.
