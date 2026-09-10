//
//  ArrangementBuilder.swift
//  ImprovisorEngine
//
//  Turns a Score into playable MIDI tracks: for every chorus, walks the tune's
//  sections, runs the AccompanimentGenerator with each section's style (the
//  tune's own style plus its inline overrides by default), applies the swing
//  feel per section, and lays the melody chorus(es) on top. This is the single
//  place the app and CLI build an arrangement from, so section styles, volumes
//  and instruments saved in the leadsheet are honored everywhere.
//

import Foundation

/// Source of styles by name (the app's data library, or a fixed set in tests).
public protocol StyleProvider {
    func style(named name: String) -> Style?
    func voicingSettings(for style: Style) -> VoicingSettings
}

/// A fixed set of styles, for tests and the CLI.
public struct StyleCatalog: StyleProvider, Sendable {
    public var styles: [String: Style]
    public var voicings: [String: VoicingSettings]

    public init(styles: [Style], voicings: [String: VoicingSettings] = [:]) {
        self.styles = Dictionary(uniqueKeysWithValues: styles.map { ($0.name, $0) })
        self.voicings = voicings
    }

    public func style(named name: String) -> Style? { styles[name] }
    public func voicingSettings(for style: Style) -> VoicingSettings {
        voicings[style.voicingFileName] ?? VoicingSettings()
    }
}

public struct ArrangementOptions: Equatable, Sendable {
    /// How many times the form is played.
    public var choruses: Int = 1
    public var seed: UInt64 = 0
    public var includeBass = true
    public var includeChords = true
    public var includeDrums = true
    public var includeMelody = true
    /// Apply the style's swing feel (off = straight eighths).
    public var applySwing = true
    public var melodyChannel: UInt8 = 2

    public init() {}
}

/// The result: tracks plus the mixer/loop facts the transport needs.
public struct Arrangement: Equatable, Sendable {
    public var tracks: [MIDITrack]
    /// Slots in one chorus of the form.
    public var formSlots: Int
    /// Master volume 0–127 from the score.
    public var masterVolume: Int
    public var choruses: Int

    /// Total length in slots (all choruses).
    public var totalSlots: Int { formSlots * choruses }
}

public enum ArrangementBuilder {
    public static let bassTrackName = "Bass"
    public static let chordTrackName = "Chords"
    public static let drumTrackName = "Drums"
    public static let melodyTrackName = "Melody"

    /// Build the arrangement for `score`. Unknown style names fall back to the
    /// score's style, then to `fallback`.
    public static func build(score: Score, styles: StyleProvider,
                             options: ArrangementOptions = ArrangementOptions(),
                             fallback: Style = Style(name: "swing")) -> Arrangement {
        let chordPart = score.chordPart
        let slotsPerBar = score.meter.slotsPerMeasure
        let formSlots = max(chordPart.size, score.melodyParts.map(\.size).max() ?? 0)
        let choruses = max(1, options.choruses)

        // Resolve the tune's default style (with inline overrides) once.
        let baseStyle = (styles.style(named: score.styleName) ?? fallback).applying(override: score.styleOverride)
        func resolve(_ name: String) -> Style {
            if name.isEmpty || name == score.styleName { return baseStyle }
            guard let s = styles.style(named: name) else { return baseStyle }
            // The header overrides target the header style only (Java mutates
            // that style object), but a section naming the same style shares it.
            return s
        }

        // Section spans in slots, in order.
        var spans: [(range: Range<Int>, style: Style)] = []
        if chordPart.size > 0 {
            let records = score.sections.records.isEmpty
                ? [SectionRecord(measure: 0, styleName: score.styleName)]
                : score.sections.records
            var current = score.styleName
            for (i, record) in records.enumerated() {
                if !record.styleName.isEmpty { current = record.styleName }
                let start = min(record.measure * slotsPerBar, chordPart.size)
                let end = i + 1 < records.count
                    ? min(records[i + 1].measure * slotsPerBar, chordPart.size)
                    : chordPart.size
                if end > start { spans.append((start..<end, resolve(current))) }
            }
            if spans.isEmpty { spans.append((0..<chordPart.size, baseStyle)) }
            if let first = spans.first, first.range.lowerBound > 0 {
                spans.insert((0..<first.range.lowerBound, baseStyle), at: 0)
            }
        }

        var bass: [ScheduledNote] = [], comping: [ScheduledNote] = []
        var drums: [ScheduledNote] = [], melody: [ScheduledNote] = []

        for chorus in 0..<choruses {
            let chorusOffset = chorus * formSlots
            for (index, span) in spans.enumerated() {
                let style = span.style
                let generator = AccompanimentGenerator(style: style,
                                                       voicingSettings: styles.voicingSettings(for: style))
                let seed = options.seed &+ UInt64(chorus) &* 1_000_003 &+ UInt64(index) &* 7919
                let acc = generator.generate(chordPart: chordPart.slice(span.range), seed: seed)
                let swing = options.applySwing ? style.compSwing : 0.5
                let offset = chorusOffset + span.range.lowerBound
                if options.includeBass { bass += shift(Groove.swung(acc.bass, swing: swing), by: offset) }
                if options.includeChords { comping += shift(Groove.swung(acc.chords, swing: swing), by: offset) }
                if options.includeDrums { drums += shift(Groove.swung(acc.drums, swing: swing), by: offset) }
            }

            if options.includeMelody, !score.melodyParts.isEmpty {
                let part = score.melodyParts[chorus % score.melodyParts.count]
                var notes = scheduled(part, channel: options.melodyChannel)
                if options.applySwing {
                    notes = swingBySection(notes, spans: spans, defaultSwing: baseStyle.swing)
                }
                melody += shift(notes, by: chorusOffset)
            }
        }

        var tracks: [MIDITrack] = []
        if !bass.isEmpty {
            tracks.append(MIDITrack(name: bassTrackName, channel: AccompanimentGenerator.bassChannel,
                                    program: UInt8(clamping: score.bassInstrument), notes: bass,
                                    volume: score.bassVolume))
        }
        if !comping.isEmpty {
            tracks.append(MIDITrack(name: chordTrackName, channel: AccompanimentGenerator.chordChannel,
                                    program: UInt8(clamping: chordPart.info.instrument), notes: comping,
                                    volume: score.chordVolume))
        }
        if !drums.isEmpty {
            tracks.append(MIDITrack(name: drumTrackName, channel: Constants.DRUM_CHANNEL,
                                    program: nil, notes: drums, volume: score.drumVolume))
        }
        if !melody.isEmpty {
            let info = score.melodyParts.first?.info ?? .defaultMelody
            tracks.append(MIDITrack(name: melodyTrackName, channel: options.melodyChannel,
                                    program: UInt8(clamping: info.instrument), notes: melody,
                                    volume: min(score.melodyVolume, info.volume)))
        }
        return Arrangement(tracks: tracks, formSlots: formSlots, masterVolume: score.volume,
                           choruses: choruses)
    }

    // MARK: Helpers

    /// A melody part as scheduled notes from slot 0, using each note's own volume.
    public static func scheduled(_ part: MelodyPart, channel: UInt8) -> [ScheduledNote] {
        var notes: [ScheduledNote] = []
        var t = 0
        for event in part.events {
            if case let .note(n) = event {
                notes.append(ScheduledNote(pitch: n.pitch, velocity: max(1, min(127, n.volume)),
                                           startTick: t, duration: n.duration, channel: channel))
            }
            t += event.duration
        }
        return notes
    }

    static func shift(_ notes: [ScheduledNote], by delta: Int) -> [ScheduledNote] {
        delta == 0 ? notes : notes.map { var n = $0; n.startTick += delta; return n }
    }

    /// Swing melody notes with the swing ratio of the section each note starts in.
    static func swingBySection(_ notes: [ScheduledNote], spans: [(range: Range<Int>, style: Style)],
                               defaultSwing: Double) -> [ScheduledNote] {
        guard !spans.isEmpty else { return Groove.swung(notes, swing: defaultSwing) }
        var out: [ScheduledNote] = []
        var covered = 0
        for span in spans {
            let inSpan = notes.filter { span.range.contains($0.startTick) }
            out += Groove.swung(inSpan, swing: span.style.swing)
            covered = max(covered, span.range.upperBound)
        }
        let tail = notes.filter { $0.startTick >= covered }
        out += Groove.swung(tail, swing: defaultSwing)
        return out.sorted { $0.startTick < $1.startTick }
    }
}
