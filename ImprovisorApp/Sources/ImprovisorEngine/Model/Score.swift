//
//  Score.swift
//  ImprovisorEngine
//
//  The top-level lead sheet: metadata plus the chord and melody parts and the
//  section structure. Ports the data-carrying role of imp/data/Score. It is
//  populated by LeadsheetParser (Step 3).
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
        numerator * (Constants.WHOLE / denominator)
    }

    public static let fourFour = Meter(4, 4)
}

public struct Score: Equatable {
    public var title: String
    public var composer: String
    public var comments: String
    public var meter: Meter
    public var key: Key
    public var tempo: Double
    public var volume: Int
    public var styleName: String
    public var chordPart: ChordPart
    public var melodyParts: [MelodyPart]
    public var sections: SectionInfo

    public init(
        title: String = "",
        composer: String = "",
        comments: String = "",
        meter: Meter = .fourFour,
        key: Key = .cMajor,
        tempo: Double = 120,
        volume: Int = 127,
        styleName: String = "swing",
        chordPart: ChordPart = ChordPart(),
        melodyParts: [MelodyPart] = [],
        sections: SectionInfo = SectionInfo()
    ) {
        self.title = title
        self.composer = composer
        self.comments = comments
        self.meter = meter
        self.key = key
        self.tempo = tempo
        self.volume = volume
        self.styleName = styleName
        self.chordPart = chordPart
        self.melodyParts = melodyParts
        self.sections = sections
    }

    /// The primary melody part, if any.
    public var melodyPart: MelodyPart? { melodyParts.first }

    /// Number of measures spanned by the chord part.
    public var measureCount: Int {
        guard meter.slotsPerMeasure > 0 else { return 0 }
        return Int(ceil(Double(chordPart.size) / Double(meter.slotsPerMeasure)))
    }
}
