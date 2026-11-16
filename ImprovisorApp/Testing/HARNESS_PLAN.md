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
