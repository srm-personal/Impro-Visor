//
//  AppModel.swift
//  improvisor-app
//
//  The view model: holds the user's choices, drives ImprovisorEngine to generate
//  an accompaniment (+ optional grammar solo), applies swing, and plays it through
//  a swappable InstrumentBackend or exports a MIDI file.
//

import Foundation
import SwiftUI
import ImprovisorEngine

enum BackendKind: String, CaseIterable, Identifiable {
    case builtIn = "Built-in synth"
    case coreMIDI = "MIDI out (GarageBand / hardware)"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    // Inputs.
    @Published var chordText = "Dm7 | G7 | Cmaj7 | Cmaj7"
    @Published var styleName = "swing"
    @Published var tempo = 160.0
    @Published var seed = 1
    @Published var loops = 2
    @Published var soloGrammar = "None"
    @Published var backendKind: BackendKind = .builtIn
    @Published var midiDestinationHint = ""
    @Published var loadedLeadsheet: URL?

    // Outputs / status.
    @Published private(set) var chordSummary: [String] = []
    @Published private(set) var trackSummary = ""
    @Published private(set) var status = "Ready — pick a style and press Generate."
    @Published private(set) var isPlaying = false

    let library: DataLibrary
    private var tracks: [MIDITrack] = []
    private var player: SequencePlayer?
    private var backend: InstrumentBackend?

    init(library: DataLibrary) {
        self.library = library
        if library.styleNames.contains("swing") == false, let first = library.styleNames.first {
            styleName = first
        }
    }

    var styleNames: [String] { library.styleNames }
    var grammarNames: [String] { ["None"] + library.grammarNames }
    var leadsheetName: String { loadedLeadsheet?.deletingPathExtension().lastPathComponent ?? "" }

    // MARK: - Generate

    func generate() {
        let style = library.style(styleName)
        let voicing = library.voicingSettings(for: style)

        let score: Score
        if let url = loadedLeadsheet, let loaded = library.score(atLeadsheet: url) {
            score = loaded
        } else {
            score = library.score(chords: chordText, styleName: styleName, tempo: Int(tempo))
        }
        let chordPart = score.chordPart
        let head = score.melodyPart.map { melodyNotes($0, channel: 2) } ?? []

        guard chordPart.count > 0 || !head.isEmpty else {
            status = "Nothing to play — enter a chord progression or open a leadsheet."
            tracks = []
            chordSummary = []
            trackSummary = ""
            return
        }
        chordSummary = chordPart.entries.map { "\($0.symbol.name)" }

        let formLen = chordPart.count > 0 ? chordPart.size : (head.map { $0.startTick + $0.duration }.max() ?? 0)
        let grammar = soloGrammar == "None" ? nil : library.grammar(soloGrammar)

        var bass: [ScheduledNote] = [], comping: [ScheduledNote] = []
        var drums: [ScheduledNote] = [], solo: [ScheduledNote] = [], melody: [ScheduledNote] = []
        for chorus in 0..<max(1, loops) {
            let offset = chorus * formLen
            if chordPart.count > 0 {
                let acc = AccompanimentGenerator(style: style, voicingSettings: voicing)
                    .generate(chordPart: chordPart, seed: UInt64(seed) &+ UInt64(chorus))
                bass += offsetNotes(acc.bass, by: offset)
                comping += offsetNotes(acc.chords, by: offset)
                drums += offsetNotes(acc.drums, by: offset)
                if let grammar {
                    let line = SoloGenerator(grammar: grammar)
                        .generate(chords: chordPart, seed: UInt64(seed) &+ UInt64(chorus) &+ 1000)
                    solo += offsetNotes(soloNotes(line, channel: 3), by: offset)
                }
            }
            melody += offsetNotes(head, by: offset)
        }

        // Swing feel: accompaniment uses comp-swing, melody/solo the melody swing.
        bass = Groove.swung(bass, swing: style.compSwing)
        comping = Groove.swung(comping, swing: style.compSwing)
        drums = Groove.swung(drums, swing: style.compSwing)
        solo = Groove.swung(solo, swing: style.swing)
        melody = Groove.swung(melody, swing: style.swing)

        var built: [MIDITrack] = []
        func add(_ name: String, _ ch: UInt8, _ program: UInt8?, _ notes: [ScheduledNote]) {
            if !notes.isEmpty { built.append(MIDITrack(name: name, channel: ch, program: program, notes: notes)) }
        }
        add("Bass", AccompanimentGenerator.bassChannel, Constants.DEFAULT_BASS_PROGRAM, bass)
        add("Piano", AccompanimentGenerator.chordChannel, Constants.DEFAULT_PIANO_PROGRAM, comping)
        add("Drums", Constants.DRUM_CHANNEL, nil, drums)
        add("Melody", 2, 73, melody)   // 73 = flute
        add("Solo", 3, 66, solo)       // 66 = tenor sax
        tracks = built

        trackSummary = "bass \(bass.count) · comp \(comping.count) · drums \(drums.count)"
            + (solo.isEmpty ? "" : " · solo \(solo.count)")
            + (melody.isEmpty ? "" : " · melody \(melody.count)")
        status = "Generated \(chordPart.count) chords · \(loops)× chorus · \(Int(tempo)) bpm"
    }

    // MARK: - Transport

    func play() {
        if tracks.isEmpty { generate() }
        guard !tracks.isEmpty else { return }
        guard let backend = makeBackend() else {
            status = backendKind == .coreMIDI ? "No MIDI destination found." : "Could not start the audio engine."
            return
        }
        self.backend = backend
        let player = SequencePlayer(backend: backend)
        player.onFinished = { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                self?.status = "Finished."
            }
        }
        self.player = player
        isPlaying = true
        status = "Playing…"
        player.play(tracks: tracks, tempoBPM: tempo)
    }

    func stop() {
        player?.stop()
        backend?.stop()
        isPlaying = false
        status = "Stopped."
    }

    func export(to url: URL) {
        if tracks.isEmpty { generate() }
        guard !tracks.isEmpty else { status = "Nothing to export."; return }
        do {
            try MIDIFileWriter.write(tracks: tracks, tempoBPM: tempo, to: url)
            status = "Exported \(url.lastPathComponent)"
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    func openLeadsheet(_ url: URL) {
        loadedLeadsheet = url
        tracks = []
        // Reflect the tune's own tempo in the slider (still adjustable).
        if let loaded = library.score(atLeadsheet: url), loaded.tempo > 0 {
            tempo = min(300, max(60, loaded.tempo))
        }
        status = "Loaded \(url.lastPathComponent) — press Generate."
    }

    func clearLeadsheet() {
        loadedLeadsheet = nil
        tracks = []
        status = "Using the inline chord progression."
    }

    private func makeBackend() -> InstrumentBackend? {
        switch backendKind {
        case .builtIn:
            #if canImport(AVFoundation)
            return AVAudioEngineSynth()
            #else
            return nil
            #endif
        case .coreMIDI:
            #if canImport(CoreMIDI)
            return CoreMIDIBackend(destinationHint: midiDestinationHint.isEmpty ? nil : midiDestinationHint)
            #else
            return nil
            #endif
        }
    }

    // MARK: - Note helpers (shared shape with the CLI)

    private func offsetNotes(_ notes: [ScheduledNote], by delta: Int) -> [ScheduledNote] {
        delta == 0 ? notes : notes.map { var n = $0; n.startTick += delta; return n }
    }

    private func melodyNotes(_ part: MelodyPart, channel: UInt8, velocity: Int = 90) -> [ScheduledNote] {
        partNotes(part, channel: channel, velocity: velocity)
    }

    private func soloNotes(_ part: MelodyPart, channel: UInt8, velocity: Int = 95) -> [ScheduledNote] {
        partNotes(part, channel: channel, velocity: velocity)
    }

    private func partNotes(_ part: MelodyPart, channel: UInt8, velocity: Int) -> [ScheduledNote] {
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
}
