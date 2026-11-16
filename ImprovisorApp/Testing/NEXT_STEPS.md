# Next steps

Written 2026-11-16. Priorities are by how much each item limits trust in the
port. IDs refer to `BUG_LOG.md`.

## P0 — make the accompaniment comparison fully green

| # | Item | Done when |
|---|------|-----------|
| P0-1 ✅ done (B-017) | **Passing-chord interpolation and chord substitution (O-03).** Port `Style.createInterpolatedChordPart` and what it calls (`Interpolate.willInterpolate`, `mapPC`, `getPC`, `choosePC`, `chooseMultiPC`, `substituteChords`, `setSubChords`), plus `PitchClass.transpose`'s spelling tables. | Done: 954/955 of the enlarged matrix. The one left is Java crashing on an NC chord (Q-04) — see P1-2. |

## P1 — things you need to decide or verify yourself

| # | Item | What is needed from you |
|---|------|-------------------------|
| P1-1 | **Run the UI suite once at your desk**: `ImprovisorApp/scripts/uitest.sh`. Only the open-tune test could be verified in the agent session (synthetic clicks did not register there). | Report which of `PracticeLoopTests` / `SmokeTests` fail, with the message. |
| P1-2 | **Java quirks now reproduced on purpose** — keep or override? Q-03 `no-style` sections (chords pile up; clearly a Java bug and sounds wrong), Q-02 melody swing on quarter notes in 6/8, 12/8, 2/2, Q-01 unknown chords silently dropped, Q-04 Java throws on an NC chord under a wildcard substitution (Swift plays on; this is the one failing golden case). | A keep/override decision per quirk. An override means a test marked "intentional divergence from Java" next to the golden. |
| P1-3 | **Solo goldens (O-06).** Java's `LickGen` cannot run without a `Notate` window. Options: (a) let the driver open a real off-screen Notate; (b) a harness copy of `LickGen`/`Grammar` with the ~20 `notate.…` calls replaced by constants. (b) is more work but stays headless and reproducible. | Pick (a) or (b). |
| P1-4 | **MIDI channel numbers (O-05).** Java: melody 0, chords 3, bass 6, drums 9. Swift: 2, 1, 0, 9. Matters only for exported MIDI and external synth setups. | Match Java, or keep. |
| P1-5 | **iOS.** The request mentioned iOS; there is no iOS target. | Whether an iOS target is in scope. |

## P2 — fidelity gaps the goldens do not cover yet

| # | Item | Approach |
|---|------|----------|
| P2-1 | **Solo generation port.** The Swift generator is not a port (no scorer / expectancy / note chooser). Needs `LickGen.java` (3,668 lines), `Grammar.java`, `NoteChooser.java`. | After P1-3: goldens for ~10 grammars × 5 tunes × 3 seeds, then port against them the way the accompaniment was done. Largest remaining item. |
| P2-2 | **Playback transposition (O-07)** is parsed but not applied. | Add `(playback-transpose …)` cases to the golden matrix (driver must pass `score.getTransposition()`), then apply in `ArrangementBuilder`. Small. |
| P2-3 | **Count-in.** Java renders a count-in chord part through the style; Swift plays its own click. | Add count-in cases to the driver; compare. |
| P2-4 | **Custom voicing (O-04)**: `voicing-type custom` → `VoicingGenerator`. No shipped style uses it. | Golden cases with a test style using each `.fv` file; move the generator onto `JavaRandom`. |
| P2-5 | **Uneven bars (O-01)**: Java aborts the chord part; Swift continues. | Decide (probably keep Swift), add a unit test documenting it. |
| P2-6 | **Grammar, vocabulary and voicing-file sweeps** against Java counts (Step 1 covered leadsheets and styles in depth; these only load without error). | Add `grammars` / `vocab` modes to the driver, like `styles`. Small. |
| P2-7 | **Parse diagnostics.** Java reports unknown chords and styles; Swift is silent. | Return warnings from `LeadsheetParser`; compare with Java's messages in the counts golden. |

## P3 — housekeeping

- Delete the superseded generators in `AccompanimentGenerator.swift`, `VocabularyVoicer.swift` and `Groove.swift` once P2-4 is settled, and move the demo CLI onto `ArrangementBuilder`.
- Wire `swift test` into whatever runs before a release (`scripts/test.sh`); the differential tests take about 45 s.
- `FEATURE_COVERAGE.md` lists what is missing from the app; it is an inventory, not a commitment.
