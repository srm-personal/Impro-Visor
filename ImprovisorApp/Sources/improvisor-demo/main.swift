//
//  main.swift
//  improvisor-demo
//
//  A command-line harness for auditioning the engine before the in-app audio
//  (Step 7) and UI (Step 8) exist. It builds a tune from a leadsheet, an inline
//  chord/melody progression, or an editable text "tune file", generates bass +
//  comping + drums, optionally loops it for practice, and writes a Standard MIDI
//  File you can play in any player or DAW.
//
//  Tune-file format (--file): simple `key: value` lines, `#` for comments.
//    title:   So What
//    style:   swing
//    tempo:   138
//    loop:    4
//    seed:    7
//    chords:  Dm7 | / | Dm7 | / | ...      (| bars, / repeats previous chord)
//    melody:  c4 e4 g4 c+2                 (leadsheet note notation)
//  plus optional: bass/drums/comp/melody: no · melody-program: N · comp-program: N
//

import Foundation
import ImprovisorEngine

// MARK: - Argument parsing

var args = Array(CommandLine.arguments.dropFirst())

@MainActor func takeFlag(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

@MainActor func hasFlag(_ name: String) -> Bool {
    if let i = args.firstIndex(of: name) { args.remove(at: i); return true }
    return false
}

func expandTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }

// MARK: - Tune-file config

/// Strip a trailing inline comment. `#` only starts a comment when it's at the
/// start or preceded by whitespace, so sharp chords like `F#7` are preserved.
func stripInlineComment(_ s: String) -> String {
    var result = ""
    var prevWasSpace = true
    for ch in s {
        if ch == "#" && prevWasSpace { break }
        result.append(ch)
        prevWasSpace = (ch == " " || ch == "\t")
    }
    return result.trimmingCharacters(in: .whitespaces)
}

/// Parse a tune file's `key: value` lines (ignoring `#` comments) into a dict.
func parseTuneFile(_ text: String) -> [String: String] {
    var cfg: [String: String] = [:]
    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        guard let colon = line.firstIndex(of: ":") else { continue }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        let value = stripInlineComment(String(line[line.index(after: colon)...]))
        if !key.isEmpty { cfg[key] = value }
    }
    return cfg
}

let fileArg = takeFlag("--file")
var fileCfg: [String: String] = [:]
if let fileArg {
    if let text = try? String(contentsOfFile: expandTilde(fileArg), encoding: .utf8) {
        fileCfg = parseTuneFile(text)
    } else {
        FileHandle.standardError.write(Data("error: could not read tune file '\(fileArg)'.\n".utf8))
        exit(1)
    }
}

/// A setting resolved from (in priority) an explicit flag, then the tune file.
@MainActor func setting(_ flag: String, _ key: String) -> String? {
    takeFlag(flag) ?? fileCfg[key]
}
/// A boolean "off" toggle: `--no-x` flag or `x: no` in the tune file.
@MainActor func disabled(_ flag: String, _ key: String) -> Bool {
    let off = ["no", "off", "false", "0"]
    return hasFlag(flag) || off.contains((fileCfg[key] ?? "").lowercased())
}

let wantsHelp = hasFlag("--help") || hasFlag("-h")
let listStyles = hasFlag("--list-styles")
let listMIDI = hasFlag("--list-midi")
let playLive = hasFlag("--play")
let midiOut = setting("--midi-out", "midi-out")
let styleName = setting("--style", "style") ?? "swing"
let chordsArg = setting("--chords", "chords")
let melodyArg = setting("--melody", "melody")
let titleArg = setting("--title", "title")
let seed = UInt64(setting("--seed", "seed") ?? "0") ?? 0
let tempoArg = setting("--tempo", "tempo").flatMap(Double.init)
let loop = max(1, Int(setting("--loop", "loop") ?? setting("--choruses", "choruses") ?? "1") ?? 1)
let outArg = setting("--out", "out")
let dataArg = setting("--data", "data")
let melodyProgram = UInt8(setting("--melody-program", "melody-program") ?? "66") ?? 66
let compProgram = UInt8(setting("--comp-program", "comp-program") ?? "\(Constants.DEFAULT_PIANO_PROGRAM)") ?? 0
let noBass = disabled("--no-bass", "bass")
let noDrums = disabled("--no-drums", "drums")
let noComp = disabled("--no-comp", "comp")
let noMelody = disabled("--no-melody", "melody-track")
let tuneArg = args.first ?? fileCfg["tune"]

func printUsage() {
    print("""
    improvisor-demo — audition the Impro-Visor engine

    USAGE:
      improvisor-demo [<tune>] [options]

    ARGUMENTS:
      <tune>              A leadsheet file path, or a name to search for under
                          leadsheets/ (default: SoWhat). Ignored if --chords/--melody
                          or a --file with chords/melody is given.

    OPTIONS:
      --file <path>       Read settings from an editable tune file (see below).
      --chords "<prog>"   Inline chord progression, e.g. "Dm7 | G7 | Cmaj7 | Cmaj7".
      --melody "<notes>"  Inline melody in leadsheet notation, e.g. "c4 e4 g4 c+2".
      --style <name>      Accompaniment style (default: swing; see --list-styles).
      --tempo <bpm>       Override the tempo.
      --loop <n>          Repeat the whole form n times (choruses) for practice.
      --seed <n>          Seed for the pattern choices (each chorus varies).
      --out <file.mid>    Output MIDI file (default: <title>.mid in the current dir).
      --melody-program N  GM program for melody (default 66 tenor sax; 0 = piano).
      --comp-program N    GM program for comping (default 0 = piano).
      --no-bass/--no-drums/--no-comp/--no-melody   Omit a track.
      --data <path>       Repo root holding vocab/, styles/, leadsheets/.
      --play              Play live via CoreMIDI (e.g. to a hardware keyboard)
                          instead of only writing a file.
      --midi-out <name>   Destination name (substring) for --play, e.g. "FP-90X".
                          Defaults to the first available destination.
      --list-styles       List available styles and exit.
      --list-midi         List CoreMIDI output destinations and exit.
      -h, --help          Show this help.

    TUNE FILE (--file) — `key: value` lines, `#` comments:
      title: My Tune       style: swing        tempo: 138
      loop: 4              seed: 7             melody-program: 0
      chords: Dm7 | / | Ebm7 | / |
      melody: c4 e4 g4 c+2
      # turn a track off with e.g.  bass: no
    """)
}

if wantsHelp { printUsage(); exit(0) }

if listMIDI {
    let dests = LiveMIDIPlayer.destinations()
    if dests.isEmpty {
        print("No CoreMIDI output destinations found. Connect your keyboard via USB and try again.")
    } else {
        print("\(dests.count) MIDI output destination(s):")
        for d in dests { print("  [\(d.index)] \(d.name)") }
        print("\nPlay to one with:  --play --midi-out \"<name substring>\"")
    }
    exit(0)
}

// MARK: - Locate the Impro-Visor data directories

func findDataRoot(start: String) -> String? {
    var url = URL(fileURLWithPath: start).standardizedFileURL
    for _ in 0..<8 {
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("vocab/My.voc").path) {
            return url.path
        }
        url.deleteLastPathComponent()
    }
    return nil
}

guard let dataRoot = dataArg.map(expandTilde) ?? findDataRoot(start: FileManager.default.currentDirectoryPath) else {
    FileHandle.standardError.write(Data("""
    error: could not find the Impro-Visor data directories (vocab/, styles/, leadsheets/).
    Run from inside the repo, or pass --data <path-to-repo-root>.

    """.utf8))
    exit(1)
}
let root = URL(fileURLWithPath: dataRoot)
func dataURL(_ rel: String) -> URL { root.appendingPathComponent(rel) }

// MARK: - Load vocabulary and style

let vocabulary = Vocabulary(source: (try? String(contentsOf: dataURL("vocab/My.voc"), encoding: .utf8)) ?? "")

if listStyles {
    let styleFiles = (try? FileManager.default.contentsOfDirectory(at: dataURL("styles"), includingPropertiesForKeys: nil)) ?? []
    let names = styleFiles.filter { $0.pathExtension == "sty" }
        .map { $0.deletingPathExtension().lastPathComponent }.sorted()
    print("\(names.count) styles:\n" + names.joined(separator: "  "))
    exit(0)
}

func loadStyle(_ name: String) -> Style {
    guard let style = try? StyleParser.parse(contentsOf: dataURL("styles/\(name).sty")) else {
        FileHandle.standardError.write(Data("warning: style '\(name)' not found; using an empty style.\n".utf8))
        return Style(name: name)
    }
    return style
}
let style = loadStyle(styleName)

// MARK: - Build the score

func findLeadsheet(_ query: String) -> URL? {
    let expanded = expandTilde(query)
    if FileManager.default.fileExists(atPath: expanded) { return URL(fileURLWithPath: expanded) }
    let base = dataURL("leadsheets")
    guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return nil }
    let needle = query.lowercased().replacingOccurrences(of: " ", with: "")
    var match: URL?
    for case let url as URL in e where url.pathExtension == "ls" {
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        if stem == needle { return url }
        if match == nil && stem.contains(needle) { match = url }
    }
    return match
}

func melodyNotes(_ part: MelodyPart, channel: UInt8, velocity: Int = 90) -> [ScheduledNote] {
    var notes: [ScheduledNote] = []
    var t = 0
    for event in part.events {
        if case let .note(n) = event {
            notes.append(ScheduledNote(pitch: n.pitch, velocity: velocity, startTick: t,
                                       duration: n.duration, channel: channel))
        }
        t += event.duration
    }
    return notes
}

let score: Score
if chordsArg != nil || melodyArg != nil {
    let tempo = tempoArg ?? 140
    var s = Score(title: titleArg ?? "Custom", meter: .fourFour, key: .cMajor, tempo: tempo, styleName: styleName)
    if let chords = chordsArg, !chords.isEmpty {
        let leadsheet = "(meter 4 4)(key 0)(tempo \(tempo))(style \(styleName))\n(part (type chords))\n\(chords)"
        s.chordPart = LeadsheetParser.parse(leadsheet, vocabulary: vocabulary).chordPart
    }
    if let melody = melodyArg, !melody.isEmpty {
        s.melodyParts = [MelodyPart(events: NoteSymbol.parseMelody(melody))]
    }
    score = s
} else {
    let query = tuneArg ?? "SoWhat"
    guard let url = findLeadsheet(query) else {
        FileHandle.standardError.write(Data("error: no leadsheet matching '\(query)' under leadsheets/.\n".utf8))
        exit(1)
    }
    var loaded = (try? LeadsheetParser.parse(contentsOf: url, vocabulary: vocabulary)) ?? Score()
    if let tempo = tempoArg { loaded.tempo = tempo }
    if let titleArg { loaded.title = titleArg }
    score = loaded
}

let baseHead = score.melodyPart.map { melodyNotes($0, channel: 2) } ?? []

guard score.chordPart.count > 0 || !baseHead.isEmpty else {
    FileHandle.standardError.write(Data("error: nothing to play — give --chords, --melody, or a tune.\n".utf8))
    exit(1)
}

// MARK: - Generate accompaniment, looped for `loop` choruses

func endTick(_ notes: [ScheduledNote]) -> Int { notes.map { $0.startTick + $0.duration }.max() ?? 0 }
func offsetNotes(_ notes: [ScheduledNote], by delta: Int) -> [ScheduledNote] {
    notes.map { var n = $0; n.startTick += delta; return n }
}

let formLen = score.chordPart.count > 0 ? score.chordPart.size : endTick(baseHead)

var bass: [ScheduledNote] = [], comping: [ScheduledNote] = [], drums: [ScheduledNote] = [], melody: [ScheduledNote] = []
for chorus in 0..<loop {
    let offset = chorus * formLen
    if score.chordPart.count > 0 {
        // Re-generate each chorus with a varied seed so loops aren't identical.
        let acc = AccompanimentGenerator(style: style).generate(chordPart: score.chordPart, seed: seed &+ UInt64(chorus))
        bass += offsetNotes(acc.bass, by: offset)
        comping += offsetNotes(acc.chords, by: offset)
        drums += offsetNotes(acc.drums, by: offset)
    }
    melody += offsetNotes(baseHead, by: offset)
}

// MARK: - Summary

let pcNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
func noteName(_ midi: Int) -> String { "\(pcNames[((midi % 12) + 12) % 12])\(midi / 12 - 1)" }

print("""
────────────────────────────────────────────────────────
  \(score.title.isEmpty ? "(untitled)" : score.title)\(score.composer.isEmpty ? "" : " — \(score.composer)")
────────────────────────────────────────────────────────
  meter \(score.meter.numerator)/\(score.meter.denominator)   tempo \(Int(score.tempo)) bpm   style \(style.name)   seed \(seed)   loop \(loop)×
  measures \(score.measureCount) per chorus   chords \(score.chordPart.count)
""")
if score.chordPart.count > 0 {
    let progression = score.chordPart.entries.prefix(16).map { "\($0.symbol.name)(\($0.duration / Constants.BEAT))" }.joined(separator: " ")
    print("  progression: \(progression)\(score.chordPart.count > 16 ? " …" : "")")
}
print("""
  ── generated (\(loop)× chorus) ──
  bass \(bass.count)   comping \(comping.count)   drums \(drums.count)   melody \(melody.count)
""")

// MARK: - Write the MIDI file

var tracks: [MIDITrack] = []
if !noBass, !bass.isEmpty {
    tracks.append(MIDITrack(name: "Bass", channel: AccompanimentGenerator.bassChannel,
                            program: Constants.DEFAULT_BASS_PROGRAM, notes: bass))
}
if !noComp, !comping.isEmpty {
    tracks.append(MIDITrack(name: "Piano", channel: AccompanimentGenerator.chordChannel,
                            program: compProgram, notes: comping))
}
if !noDrums, !drums.isEmpty {
    tracks.append(MIDITrack(name: "Drums", channel: Constants.DRUM_CHANNEL, program: nil, notes: drums))
}
if !noMelody, !melody.isEmpty {
    tracks.append(MIDITrack(name: "Melody", channel: 2, program: melodyProgram, notes: melody))
}

guard !tracks.isEmpty else {
    FileHandle.standardError.write(Data("error: all tracks were disabled — nothing to write.\n".utf8))
    exit(1)
}

// Live playback to a hardware keyboard (uses the instrument's own sounds).
if playLive {
    guard let player = LiveMIDIPlayer(destinationHint: midiOut) else {
        let dests = LiveMIDIPlayer.destinations()
        if dests.isEmpty {
            FileHandle.standardError.write(Data("error: no CoreMIDI destinations — connect your keyboard via USB.\n".utf8))
        } else {
            let names = dests.map { "\"\($0.name)\"" }.joined(separator: ", ")
            FileHandle.standardError.write(Data("error: no MIDI destination matching \(midiOut.map { "'\($0)'" } ?? "(any)"). Available: \(names)\n".utf8))
        }
        exit(1)
    }
    print("""
      ── playing live ──
      → \(player.destinationName)   (Ctrl-C to stop)
    ────────────────────────────────────────────────────────
    """)
    player.play(tracks: tracks, tempoBPM: score.tempo)
    exit(0)
}

func slugify(_ s: String) -> String {
    let cleaned = s.filter { $0.isLetter || $0.isNumber || $0 == " " }
        .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
    return cleaned.isEmpty ? "improvisor-out" : cleaned
}
let outURL = URL(fileURLWithPath: expandTilde(outArg ?? "\(slugify(score.title)).mid"))

do {
    try MIDIFileWriter.write(tracks: tracks, tempoBPM: score.tempo, to: outURL)
    print("""
      ── output ──
      wrote \(outURL.path)
      play it:  open "\(outURL.path)"
    ────────────────────────────────────────────────────────
    """)
} catch {
    FileHandle.standardError.write(Data("error writing MIDI: \(error)\n".utf8))
    exit(1)
}
