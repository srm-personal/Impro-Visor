//
//  Score.swift
//  ImprovisorEngine
//
//  The top-level lead sheet: metadata plus the chord and melody parts and the
//  section structure. Ports the data-carrying role of imp/data/Score, holding
//  every header field the Java `Leadsheet.saveLeadSheet` writes so that a `.ls`
//  file survives a read → write round trip. Populated by LeadsheetParser.
//

import Foundation

/// A time signature, e.g. 4/4.
public struct Meter: Equatable, Sendable {
    public var numerator: Int
    public var denominator: Int

    public init(_ numerator: Int, _ denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    /// Slots in one measure of this meter (WHOLE = a 4/4 measure of 4 beats).
    public var slotsPerMeasure: Int {
        denominator > 0 ? numerator * (Constants.WHOLE / denominator) : 0
    }

    /// Slots in one beat of this meter.
    public var slotsPerBeat: Int {
        denominator > 0 ? Constants.WHOLE / denominator : Constants.BEAT
    }

    public static let fourFour = Meter(4, 4)
}

/// Playback transposition in semitones for each accompaniment track
/// (`(playback-transpose bass chords melody)`).
public struct Transposition: Equatable, Sendable {
    public var bass: Int
    public var chords: Int
    public var melody: Int

    public init(bass: Int = 0, chords: Int = 0, melody: Int = 0) {
        self.bass = bass
        self.chords = chords
        self.melody = melody
    }

    public static let none = Transposition()
}

public struct Score: Equatable, Sendable {
    // Identification.
    public var title: String
    public var composer: String
    public var showTitle: String
    public var year: String
    public var comments: String

    // Musical parameters.
    public var meter: Meter
    public var key: Key
    public var tempo: Double
    /// Master volume 0–127.
    public var volume: Int
    public var playbackTranspose: Transposition

    // Playback / display settings saved with the tune.
    public var chordFontSize: Int
    /// General MIDI program for the bass track.
    public var bassInstrument: Int
    public var bassVolume: Int
    public var drumVolume: Int
    public var chordVolume: Int
    public var melodyVolume: Int
    /// Pitch at which a grand staff splits between treble and bass (F#3 = 54).
    public var breakpoint: Int
    /// Bars per line; empty = automatic. `(layout 4)` → `[4]`.
    public var layout: [Int]
    public var roadmapLayout: Int

    // Style.
    public var styleName: String
    /// Inline style parameter overrides from the `(style name (swing 0.55) …)`
    /// header form, kept verbatim (the list of parameter forms after the name).
    public var styleOverride: Polylist?

    // Content.
    public var chordPart: ChordPart
    public var melodyParts: [MelodyPart]
    public var sections: SectionInfo

    /// Top-level forms this reader does not model (e.g. `(roadmap …)`); they are
    /// written back unchanged so unknown data is never destroyed.
    public var unknownForms: [Polylist]

    public init(
        title: String = "",
        composer: String = "",
        showTitle: String = "",
        year: String = "",
        comments: String = "",
        meter: Meter = .fourFour,
        key: Key = .cMajor,
        tempo: Double = 160,
        volume: Int = 127,
        playbackTranspose: Transposition = .none,
        chordFontSize: Int = 16,
        bassInstrument: Int = Int(Constants.DEFAULT_BASS_PROGRAM),
        bassVolume: Int = 60,
        drumVolume: Int = 60,
        chordVolume: Int = 60,
        melodyVolume: Int = 127,
        breakpoint: Int = 54,
        layout: [Int] = [],
        roadmapLayout: Int = 8,
        styleName: String = "swing",
        styleOverride: Polylist? = nil,
        chordPart: ChordPart = ChordPart(),
        melodyParts: [MelodyPart] = [],
        sections: SectionInfo = SectionInfo(),
        unknownForms: [Polylist] = []
    ) {
        self.title = title
        self.composer = composer
        self.showTitle = showTitle
        self.year = year
        self.comments = comments
        self.meter = meter
        self.key = key
        self.tempo = tempo
        self.volume = volume
        self.playbackTranspose = playbackTranspose
        self.chordFontSize = chordFontSize
        self.bassInstrument = bassInstrument
        self.bassVolume = bassVolume
        self.drumVolume = drumVolume
        self.chordVolume = chordVolume
        self.melodyVolume = melodyVolume
        self.breakpoint = breakpoint
        self.layout = layout
        self.roadmapLayout = roadmapLayout
        self.styleName = styleName
        self.styleOverride = styleOverride
        self.chordPart = chordPart
        self.melodyParts = melodyParts
        self.sections = sections
        self.unknownForms = unknownForms
    }

    /// The primary melody part, if any.
    public var melodyPart: MelodyPart? { melodyParts.first }

    /// A new, empty tune: `measures` bars of "no chord" and one melody chorus of
    /// rests, with a single section in `styleName`.
    public static func blank(measures: Int = 32, meter: Meter = .fourFour,
                             styleName: String = "swing", tempo: Double = 160) -> Score {
        let bars = max(1, measures)
        var chords = ChordPart()
        chords.append(.noChord, duration: bars * meter.slotsPerMeasure)
        let rests = (0..<bars).map { _ in MusicEvent.rest(Rest(duration: meter.slotsPerMeasure)) }
        return Score(meter: meter, tempo: tempo, styleName: styleName,
                     chordPart: chords,
                     melodyParts: [MelodyPart(events: rests)],
                     sections: SectionInfo(records: [SectionRecord(measure: 0, styleName: styleName)]))
    }

    /// Number of measures spanned by the chord part.
    public var measureCount: Int {
        guard meter.slotsPerMeasure > 0 else { return 0 }
        return Int(ceil(Double(chordPart.size) / Double(meter.slotsPerMeasure)))
    }
}
