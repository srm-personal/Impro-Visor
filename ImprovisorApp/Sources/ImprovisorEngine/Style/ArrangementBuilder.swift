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
    /// Seed for the Java-compatible random stream (`JavaRandom`). When set it
    /// takes precedence over `seed`; the differential tests use it to
    /// reproduce the Java engine's output exactly.
    public var javaSeed: Int64?
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

        // Sections as Java's SectionInfo sees them: (start slot, style or nil
        // for "use the previous style").
        var records: [(index: Int, styleName: String?)] = score.sections.records.map {
            ($0.measure * slotsPerBar, $0.usesPreviousStyle ? nil : $0.styleName)
        }
        if records.isEmpty { records = [(0, score.styleName)] }

        var compiled: [String: CompiledStyle] = [:]
        func compile(_ style: Style, key: String) -> CompiledStyle {
            if let c = compiled[key] { return c }
            let c = CompiledStyle(style)
            compiled[key] = c
            return c
        }
        // Java starts SectionInfo.render with `new Style()`: a style with no
        // patterns, which is what a leading "use previous style" section gets.
        let emptyStyle = Style(name: "", voicingType: "closed")

        var bass: [ScheduledNote] = [], comping: [ScheduledNote] = []
        var drums: [ScheduledNote] = [], melody: [ScheduledNote] = []

        // ONE random stream for the whole render, consumed in Java's order.
        var rng = JavaRandom(seed: options.javaSeed ?? Int64(bitPattern: options.seed))
        var time = 0

        // Port of Score.render: each chorus renders a melody part and, in
        // parallel, the whole chord progression section by section.
        for chorus in 0..<choruses {
            let chorusStart = time
            var melodyEnd = chorusStart
            if !score.melodyParts.isEmpty {
                let part = score.melodyParts[chorus % score.melodyParts.count]
                melodyEnd = chorusStart + part.size
                if options.includeMelody {
                    melody += melodyNotes(part, score: score, records: records, resolve: resolve,
                                          applySwing: options.applySwing, from: chorusStart,
                                          channel: options.melodyChannel)
                }
            }

            var chordTime = chorusStart
            var mostRecent = (style: emptyStyle, key: "\u{0}empty")
            for (i, record) in records.enumerated() {
                if let name = record.styleName { mostRecent = (resolve(name), name) }
                let endIndex = i + 1 < records.count ? records[i + 1].index : chordPart.size
                var renderer = StyleRenderer(compile(mostRecent.style, key: mostRecent.key),
                                             bassChannel: AccompanimentGenerator.bassChannel,
                                             chordChannel: AccompanimentGenerator.chordChannel,
                                             applySwing: options.applySwing)
                var out = SectionRender()
                chordTime = renderer.render(chordPart: chordPart, startIndex: record.index, endIndex: endIndex,
                                            time: chordTime, rng: &rng, into: &out)
                if options.includeBass { bass += out.bass }
                if options.includeChords { comping += out.chords }
                if options.includeDrums { drums += out.drums }
            }
            time = max(melodyEnd, chordTime)
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

    /// A melody chorus as scheduled notes, swung the way Java's
    /// `Score.makeSwing` → `Part.makeSwing(SectionInfo)` does it: beat by beat,
    /// with the swing of the style in force at that beat.
    static func melodyNotes(_ part: MelodyPart, score: Score,
                            records: [(index: Int, styleName: String?)],
                            resolve: (String) -> Style, applySwing: Bool,
                            from start: Int, channel: UInt8) -> [ScheduledNote] {
        var slots = SlotPart()
        for event in part.events {
            switch event {
            case let .note(n): slots.add(pitch: n.pitch, duration: n.duration, volume: max(0, min(127, n.volume)))
            case let .rest(r): slots.add(pitch: nil, duration: r.duration)
            }
        }
        if applySwing {
            // Java: `previousStyle` starts as the style named "swing".
            var previous = resolve("swing").swing
            // Java swings a COPY of the score, and MelodyPart.copy does not
            // carry the metre over, so the beat is always a quarter note here
            // — also in 6/8, 12/8 and 2/2 (Java quirk Q-02).
            slots.makeSwing(beatValue: Constants.BEAT) { slot in
                // SectionInfo.getSectionRecordBySlot: the last record at or before the slot.
                let record = records.last { $0.index <= slot } ?? records[0]
                if let name = record.styleName { previous = resolve(name).swing }
                return previous
            }
        }
        return slots.render(from: start, channel: channel).notes
    }
}
