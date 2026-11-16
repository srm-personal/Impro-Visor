# Bug log — Swift port vs. Java Impro-Visor 10.2

Status values: **fixed** · **open** · **Java quirk** (Java behaviour looks
wrong but is matched on purpose) · **needs decision**.
Java references are `src/…:line` in this repository.

## Harness decisions (not bugs)

| ID | Decision | Why |
|----|----------|-----|
| D-01 | `Testing/` lives in `ImprovisorApp/Testing`, not the repo root. | The repo root is the upstream Java tree; everything Swift lives under `ImprovisorApp/`. |
| D-02 | Java is built with Android Studio's bundled JDK 21 using `--release 8`. | No JDK/Ant/Homebrew on this Mac; `Notate.java:17117` only compiles against the Java 8 API. |
| D-03 | Randomness is made seedable by rewriting a scratch copy of `src/imp` (`Math.random()`, `new Random()`, `Collections.shuffle`) to one shared `java.util.Random`. | Keeps `src/` untouched and gives a single stream the Swift side can reproduce. |
| D-04 | `ErrorLog` and `ErrorLogWithResponse` are replaced by recording stubs in the harness build; "continue/abort" dialogs answer **continue**. | Both create Swing dialogs (`HeadlessException`). "Continue" is the dialog's default button. |
| D-05 | Event dumps are sorted by (tick, channel, pitch, velocity, duration). | Order of simultaneous events in a `javax.sound.midi.Track` is not engine behaviour. |
| D-06 | Only text event dumps are committed; `.mid` files are regenerated into `Testing/.build`. | `*.mid` is already git-ignored in `ImprovisorApp/`; the text dump is what the tests read. |

## Issues

| ID | Subsystem | Symptom | Root cause | Java reference | Swift fix | Status |
|----|-----------|---------|------------|----------------|-----------|--------|
| B-001 | Parsing / Polya | 7 CRLF leadsheets lose the first chord of every line (e.g. `AreYouReal.ls`: 30 chords instead of 39, form 480 slots short). | `Tokenizer` scanned Swift `Character`s; `"\r\n"` is a single grapheme that matched neither `\r` nor `\n`, so it glued onto the next word and the token was dropped. | `src/polya/Tokenizer.java:100` (whitespace = space, tab, `\n`, `\r`, `\f`, read per char) | `Polya/Tokenizer.swift` — scan Unicode scalars | fixed |
| B-002 | Parsing / chords | Slash chords whose bass is followed by extra text (`Fm7/Bb7`, `Eb7/B6`) became `NC` (3 files, e.g. `FirmRoots.ls`). | Swift required the text after `/` to be exactly a pitch name. Java reads only the letter and one optional accidental and ignores the rest. | `src/imp/data/ChordSymbol.java:214-232`, `src/imp/data/PitchClass.java:333-371` | `Model/ChordSymbol.swift` (`parse`) | fixed |
| B-003 / Q-01 | Parsing / chords | `IvoryForest.ls` (chords `Cm7b9`, `Dm7b9`… not in `My.voc`): Swift kept 16 chords with no chord form; Java ends up with one `F9sus4` chord. | Java warns "does not recognize this chord … using NC instead" but then **drops the token** — it never reaches the chord stream, so the bar is split among the remaining cells. Swift kept unknown types as form-less chords. Swift now drops them too. | `src/imp/data/Leadsheet.java:806-823` (no `cons` in the else branch) | `Parsing/LeadsheetParser.swift`, `ChordSymbol.isRecognized` | fixed — **Java quirk, needs decision**: the message promises NC; dropping silently shortens the tune. Matching Java for now. |
