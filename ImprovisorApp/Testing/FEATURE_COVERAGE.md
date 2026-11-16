# Feature coverage — Java Impro-Visor 10.2 vs. the Swift port (Leadsheet Studio)

An inventory, not a plan: nothing here was implemented as part of the harness
work. Java features were taken from the menu bar, toolbar, dialogs and
preferences of `src/imp/gui/Notate.java` (menu tree extracted from the
generated `initComponents` code) and the frames it opens.

**Swift status** was judged by reading `Sources/LeadsheetKit` and
`Sources/ImprovisorEngine`, not by exercising every control in the running
app. *implemented* = a control exists and is wired; *partial* = a narrower
version exists; *missing* = nothing found.

**Test coverage**: *engine* = unit/differential tests in `swift test`;
*engine (Java)* = compared against Java output by the harness in `Testing/`;
*UI* = an XCUITest touches it; *none*.

Java locations are `src/imp/gui/Notate.java:<line of the action handler>`
unless another file is named.

## File

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| New leadsheet (new window) | `:20222` newMI | implemented | UI | Document-based app, ⌘N. |
| Open leadsheet | `:19534` openLeadsheetMI | implemented | engine (Java) | 3,280/3,280 shipped files parse to Java's counts. |
| Open recent (same / new window) | openRecentLeadsheetMenu, `RecentFiles.java` | partial | none | macOS "Open Recent" from the document system; no same-window variant. |
| File stepper (browse a folder of leadsheets) | `:23395` fileStepMI, fileStepDialog | partial | none | Library browser window (⌘⇧O) covers browsing; no step-through-and-play. |
| Revert to saved | revertToSavedMI | partial | none | Standard document revert, if enabled by the document system. |
| Save / Save As | `:14338`, `:19357` | implemented | engine | Round trip stable on 3,280/3,280 files; writer follows Java's layout. |
| Export leadsheet to MIDI | `:13305` exportAllToMidi, `com/ExportToMidiCommand.java` | implemented | engine (Java) | Notes match Java on 851/855 cases; channel numbers differ (BUG_LOG O-05). |
| Import MIDI tracks | `:23564` importMidiMI, `midi/MidiImport*.java` | missing | none | |
| Export chorus to MusicXML | `:22910`, `util/MusicXML*.java` | missing | none | |
| Load / save vocabulary | `:16825` loadAdvMI, `:14096` saveAdvice | missing | none | `My.voc` is read from the bundle; not user-loadable or editable. |
| Print current chorus / all choruses | `:18468`, `:23379` | implemented | engine | Print…, Print Current Chorus…, Export PDF…; layout is the port's own. |
| Clear command history | clearHistoryMI | missing | none | |
| Quit, About | quitMI, `:15032` | implemented | none | |

## Edit

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Undo / redo | `:18398` undoMI | implemented | engine | Value-snapshot undo per edit. |
| Select all | `:14729` | partial | none | Selection model exists; menu item not found. |
| Cut / copy / paste melody | `:18263`, `:18230`, `:18142` | implemented | engine | `Editor/Clipboard.swift`. |
| Cut / copy / paste chords, and both | `:14795` … | partial | none | Chords are edited per bar as text; no chord clipboard found. |
| Cut melodies in all choruses | delAllMI | missing | none | |
| Always overwrite when pasting | `:14491` pasteOverMI | missing | none | |
| Enter melody / chords / both from text | `:14286`, `:14237`, enterBothMI | partial | UI | Chords from text (⌘⇧K, chord row with autocomplete). No melody-from-text field. |
| Note entry by keyboard, mouse, on-screen piano | `Stave.java`, `StaveActionHandler.java` | implemented | engine, UI | Port's own editing model (duration palette, harmonic entry). |
| MIDI step entry | `midi/MidiStepEntryActionHandler.java` | partial | none | "MIDI in" toggle; behaviour not compared with Java. |
| Reverse / invert selected melody | `:13433`, `:13428` | missing | none | |
| Expand / contract melody by 2, 3 | `:13423` … | missing | none | |
| Copy melody / chords / selection to text window | `:13451` … | missing | none | |
| Save selection as lick, cell, idiom or quote | `:13469`, `gui/SaveLickFrame*` | missing | none | |
| Generate lick in selection | `:20613` | partial | none | Generate panel fills a chorus; see Improv. |
| Insert new chorus tab | `:23586` | implemented | none | "Add Chorus" / "New Chorus". |
| Insert a measure of rest / add rest | `:13246`, `:10383` | partial | engine | Rests can be entered; no insert-measure command found. |
| Resolve pitches | `:20618`, `com/RectifyPitchesCommand.java` | missing | none | |
| Merge consecutive same notes | `:24413` | missing | none | |
| Toggle enharmonic spelling | `Stave.java` | implemented | engine | |

## Transpose

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Melody / chords / both up or down a semitone | `:14267`, `:14250` … | implemented | engine | "Transpose" menu. |
| Melody up / down an octave | `:14225` | implemented | engine | |
| Melody up / down harmonically | `:20425` | missing | none | |
| Transposition wizard (transposing instruments) | `:24703`, `gui/TranspositionWizardDialog.java` | missing | none | |
| Playback transposition (bass, chords, melody) | Leadsheet prefs, `data/Transposition.java` | partial | engine | Parsed and saved; **not applied** by `ArrangementBuilder`. |

## View

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Stave layout: freeze / single adjust / continuous auto-adjust | `:24417`, oneAutoMI, `:17969` | partial | engine | Automatic layout only; `(layout …)` is preserved in the file but not edited. |
| Early scroll, parallax / tracker delay | earlyScrollCheckBoxMI, `:24421` | missing | none | |
| Show title, empty title placeholders | `:18597`, showEmptyTitlesMI | partial | none | Title shown; no toggles. |
| Show bar numbers, phrase marks | `:18580`, `:23450` | partial | engine | Drawn; no toggles found. |
| Brackets on current / all measures, construction lines | `:18448`, `:23509` | missing | none | |
| Show note names above cursor | `:23974` | missing | none | |
| Use beams | `:23460` | partial | engine | Beaming is always on (`BeamGrouper`). |
| ϕ for m7b5, Δ for M7 | `:23709`, replaceWithDelta | missing | none | |
| Note colouring by chord / colour / foreign tone | Global prefs, `data/Coloration.java` | partial | engine | `Coloration` model exists; preference UI not found. |
| Stave type per chorus (treble / bass / grand / auto) | Chorus prefs | implemented | engine | Inspector "Stave". |

## Play

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Play all / stop / pause | `:18759`, `:18616`, pausePlayMI | implemented | engine, UI | Transport bar; ⌘⇧P, ⌘. |
| Play selection, play selection to end | `:23438`, `:23444` | partial | none | "Play Selection (Loop)" only. |
| Loop | toolbar loopButton / loopSet | implemented | engine | "Loop Form", selection loop. |
| Tempo (slider, field, live) | toolbar tempoSlider / tempoSet | implemented | engine | 20–400, live. |
| Count-in | Leadsheet prefs, `Score.setCountIn` | implemented | engine | Port's own click; Java renders a count-in chord part with the style. Not compared. |
| Mixer: master, melody, chords, bass, drums, entry; mutes | mixerDialog | implemented | engine | Mixer view; "entry" volume not found. |
| Accompaniment: bass, chords, drums from a style | `style/Style.java` | implemented | engine (Java) | 851/855 golden cases identical to Java. |
| Styles per section, phrases | Style prefs, `style/SectionInfo.java` | implemented | engine (Java) | Section editor; own-style goldens match. |
| Passing-chord interpolation and substitutions | `style/Interpolate.java`, `Style.java:1602-2130` | missing | engine (Java) | 4 golden cases fail (BUG_LOG O-03). |
| Swing (melody and accompaniment) | `data/Part.java:1347, 1436` | implemented | engine (Java) | Includes Java's quarter-note swing in 6/8 (Q-02). |
| Record from MIDI | `:23606`, `midi/MidiRecorder.java` | missing | none | |
| Quantization on input / requantize chorus | `:24430`, `:24449`, `gui/QuantizationDialog.java` | missing | none | |
| Audio input (pitch tracking) | `imp/audio/*` | missing | none | |
| MIDI output device, latency | MIDI prefs, `midi/MidiManager.java` | partial | none | Built-in synth or CoreMIDI output; no latency settings. |
| Step through chord voicings | toolbar chordStep buttons | missing | none | |

## Roadmap

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Roadmap analysis (bricks, key map), editing, play from roadmap | `roadmap/RoadMapFrame.java` and package | missing | none | `(roadmap-layout)` and roadmap blocks are preserved in files only. |
| Generate roadmap on open / save roadmap with leadsheet | createRoadMapCheckBox, saveRoadMapCheckBox | missing | none | |

## Utilities

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Advice tree (scales, cells, idioms, licks, quotes for the selection) | `:14175`, `data/advice/*` | missing | none | |
| Advising (step) keyboard | `:24464`, `gui/StepEntryKeyboard.java` | missing | none | |
| Voicing keyboard | `:22141`, `gui/VoicingKeyboard.java` | partial | none | On-screen piano for note entry only. |
| Voicing editor (edit vocabulary voicings) | `:11243`, voicingTestDialog | missing | none | |
| Fluid voicing editor (`.fv` settings) | `:24391`, `voicing/*` | partial | engine | `.fv` files parse and a generator exists, but no editor, and the engine does not use it (BUG_LOG O-04). |
| Leadsheet textual editor | `:13383`, `gui/SourceEditorDialog.java` | missing | none | |
| Style editor and extractor | `:10064`, `style/StyleEditor.java`, `stylePatterns/*Extractor.java` | missing | none | Styles are read-only. |
| Style mixer | `style/StyleMixer.java` | missing | none | |
| Chord guessing from melody | `data/ChordGuesser` (port) | partial | engine | Model code exists in the port; no Java counterpart checked. |

## Improv

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Generate solo from a grammar | `:13366` lickGeneratorMI, `lickgen/LickGen.java`, `Grammar.java` | partial | engine | Swift expands the grammar but picks notes with a simpler rule (no scorer / expectancy). **Not compared with Java**: `LickGen` cannot run without a `Notate` window (see BUG_LOG O-06). |
| Grammar chooser | `:24475` | implemented | none | "Grammar" picker; 85 grammars load. |
| Grammar control (pitch range, intervals, leap probability, rectify, use head …) | `lickgen/LickgenFrame.java` | missing | none | |
| Grammar editor, grammar learning from a corpus | `:24756`, `lickgen/GrammarEditorDialog.java`, `LickgenFrame.java` | missing | none | |
| Trading (active and passive), trade options | `:24356`, `trading/*` | missing | none | |
| Record improvisation | saveImprovCheckBoxMenuItem | missing | none | |
| Transform (grammar & transform), transform editor | transformRadio, `lickgen/transformations/*` | missing | none | |
| Divide / fractal improvisation | fractalMI, `fractal/*` | missing | none | |
| Guide tone line (and with transform / divide) | guideToneLine, `guidetone/*` | missing | none | |
| Interval learning | intervalLearningMI, `data/IntervalLearner.java` | missing | none | |
| Theme weaver (and custom) | `:23979`, `themeWeaver/*` | missing | none | |
| Deep learning (LSTM) generation | `:24439`, `lstm/*` | missing | none | |
| Critic / lick grading | `neuralnet/*`, `LickgenFrame.java` | missing | none | |

## Preferences

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Global: default instruments, volumes, tempo, style, note colouring, cache, language | `:10244`, `util/Preferences.java` | missing | none | Defaults are compiled in. Java's defaults are what the goldens were made with. |
| Leadsheet: title, composer, comments, key, metre, tempo, length, layout, transposition | `:10237` | partial | engine | Inspector edits title/composer/instruments; key/metre/length editing not confirmed. |
| Chorus: title, instrument, stave, key | `:10054` | implemented | engine | Inspector "Chorus". |
| Style: per-section style, swing, register, new/delete sections | `:10231` | partial | engine | Section editor chooses styles; inline swing/register overrides are read from the file but have no editor. |
| MIDI: in/out devices, channels, echo, latency, bank select | `:10224`, `midi/MidiManager.java` | partial | none | Output backend and MIDI-in toggle only. |
| Contour drawing tones, "always use" buttons | Global prefs | missing | none | |

## Window / Help

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| Close window, cascade windows | `:11355` | partial | none | Standard macOS window management. |
| Help, first-launch message | `:10218`, firstTimePrefsMI | implemented | none | Help command and onboarding window. |
| Error log dialog | `util/ErrorLog.java` | missing | none | Parse problems are silent in Swift; Java reports them (e.g. unknown chords, unknown styles). |

## Platform

| Feature | Java location | Swift status | Test coverage | Notes |
|---|---|---|---|---|
| macOS app | — | implemented | UI | `App/LeadsheetStudio`. |
| iOS app | — | missing | none | The package and the Xcode project are macOS-only (`platforms: [.macOS(.v14)]`). |
