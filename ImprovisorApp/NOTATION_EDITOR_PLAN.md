# Notation Editor — Parity Plan (Swift port, Step "#2")

Goal: bring the SwiftUI app toward parity with the original Java Impro-Visor.

**Framing.** The engine is already near parity (Polya reader, model, `.ls`
parsing for chords + melody, style accompaniment, both voicing paths, grammar
solo, swing + push, playback via built-in synth / CoreMIDI, MIDI export, `.ls`
chord authoring + save). The remaining gap to "what the original app did" is
almost entirely the **interactive notation editor** plus a set of
**generative/analysis subsystems**.

**Magnitude (why this is tiered).** The Java originals are huge: `Notate.java`
~28,857 lines, `Stave.java` ~6,225, `StaveActionHandler.java` ~3,135,
`StepEntryKeyboard.java` ~3,245; subsystems roadmap (25 files), trading (26),
lickgen (29). Full feature-for-feature parity is a long program. Treat each tier
as an independently valuable milestone.

## Tier 1 — The notation leadsheet editor (the app's identity)

| # | Piece | Notes | Size |
|---|-------|-------|------|
| E1 | Melody round-trip | Serialize `MelodyPart` → `.ls` note tokens (reverse of `NoteSymbol.parse`); makes open→edit→save lossless. Pure engine, testable. | Small |
| E2 | Stave rendering | SwiftUI `Canvas`: staff/clef/key/meter, note heads/stems/beams/flags/dots/rests/ties/accidentals, chord symbols above, barlines, scrolling. Port of `Stave.java`. | Large — centerpiece |
| E3 | Cursor + selection | Playback cursor, click-to-position, select a region, play/loop selection. | Medium |
| E4 | Mouse note editing | Place/move/delete/drag pitch & duration. Port of `StaveActionHandler`. | Large |
| E5 | Chord entry UI | Type/edit chords per bar, chord palette (`ChordPane`). | Medium |
| E6 | MIDI step-entry + record | CoreMIDI **in** → notes with quantization; real-time record (`StepEntryKeyboard`). | Medium |
| E7 | Editor plumbing | Undo/redo, cut/copy/paste, transpose, key/meter edits, enharmonics, sections/parts. | Medium |

## Tier 2 — Surface the existing engine in the editor
- Generate solo over a selection using the existing `SoloGenerator` (grammar).
- Transport bound to the stave (count-in, loop, tempo) — reuses `SequencePlayer`.
- Voicing-keyboard view visualizing the voicings the engine picks (`VoicingKeyboard`).

## Tier 3 — Larger generative/analysis subsystems (each its own project)
- RoadMap (25 files) — harmonic "brick" analysis + roadmap editor.
- Trading (26 files) — trade fours with the program.
- Transforms / Advice — melody transforms, substitutions, note advice (`Advisor`).
- Lick generation (29 files) — lick gen, grammar *learning* from selections, lick library.
- ML long tail — LSTM, neural-net melody, clustering, theme weaver, fractal, guide-tone lines.

## Recommended sequence
E1 → E2 → (E3 + E4) → E5 → E6 → E7, then Tier 2, then pick Tier 3 by interest.
Rationale: a viewable, editable, playable stave is what makes it *Impro-Visor*;
Tier 3 generators are bonus depth.

**Start point:** E1 (melody round-trip) — small, pure-engine, immediately
valuable (Save stops dropping melodies). E2 (stave rendering) is the real
investment and deserves its own focused effort.

## Verification per phase
Engine/serialization pieces get golden round-trip tests (like the existing
`LeadsheetWriterTests`); rendering and interaction are verified on the Mac (the
agent can't see the canvas or drive the mouse).

## Already done (engine parity)
Steps 1–8: Polya → model → parsers → accompaniment → grammar solo → voicing
(algorithmic + vocabulary) → swing + chord push → audio backends + SwiftUI app →
`.ls` chord authoring/save. See the `swift-port-*` memory notes.
