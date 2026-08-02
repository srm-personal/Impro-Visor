//
//  LeadsheetWriterTests.swift
//  ImprovisorEngineTests
//
//  Coverage for the leadsheet serializer (#1: authoring / save-as-.ls).
//

import XCTest
@testable import ImprovisorEngine

final class LeadsheetWriterTests: XCTestCase {

    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()
    var vocab: Vocabulary { LeadsheetWriterTests.vocabulary }

    private func chordNames(_ part: ChordPart) -> [String] {
        part.entries.map { $0.symbol.name }
    }

    func testAuthoredLeadsheetRoundTrips() {
        let text = LeadsheetWriter.leadsheet(
            title: "Test Tune", composer: "Me", meter: Meter(4, 4), key: 2,
            tempo: 140, style: "swing", chords: "Dm7 | G7 | Cmaj7 | Cmaj7")
        let score = LeadsheetParser.parse(text, vocabulary: vocab)

        XCTAssertEqual(score.title, "Test Tune")
        XCTAssertEqual(score.composer, "Me")
        XCTAssertEqual(score.meter.numerator, 4)
        XCTAssertEqual(score.key.index, 2)
        XCTAssertEqual(score.tempo, 140, accuracy: 0.001)
        XCTAssertEqual(chordNames(score.chordPart), ["Dm7", "G7", "Cmaj7", "Cmaj7"])
    }

    func testProgressionTextReconstructsBars() {
        // Two bars of Dm7, one of G7.
        var part = ChordPart()
        let m = Meter.fourFour.slotsPerMeasure
        part.append(ChordSymbol.parse("Dm7", vocabulary: vocab)!, duration: 2 * m)
        part.append(ChordSymbol.parse("G7", vocabulary: vocab)!, duration: m)

        let text = LeadsheetWriter.progressionText(part, meter: .fourFour)
        // Bar 1 = Dm7, bar 2 = held (/), bar 3 = G7.
        XCTAssertEqual(text, "Dm7 | / | G7 |")

        // And it parses back to the same chord-per-slot content.
        let reparsed = LeadsheetParser.parse(
            LeadsheetWriter.leadsheet(title: "", composer: "", meter: .fourFour, key: 0,
                                      tempo: 120, style: "swing", chords: text),
            vocabulary: vocab)
        XCTAssertEqual(reparsed.chordPart.chord(at: 0)?.name, "Dm7")
        XCTAssertEqual(reparsed.chordPart.chord(at: 2 * m)?.name, "G7")
    }

    func testRealLeadsheetChordsSurviveReserialization() throws {
        let original = try LeadsheetParser.parse(
            contentsOf: TestData.url("leadsheets/imaginary-book/SoWhat.ls"), vocabulary: vocab)
        let text = LeadsheetWriter.leadsheet(
            title: original.title, composer: original.composer, meter: original.meter,
            key: original.key.index, tempo: original.tempo, style: original.styleName,
            chords: LeadsheetWriter.progressionText(original.chordPart, meter: original.meter))
        let round = LeadsheetParser.parse(text, vocabulary: vocab)

        // So What is 32 bars: 16 Dm7, 8 Ebm7, 8 Dm7 — check a few sample slots.
        let m = original.meter.slotsPerMeasure
        XCTAssertEqual(round.chordPart.chord(at: 0)?.name, "Dm7")
        XCTAssertEqual(round.chordPart.chord(at: 16 * m)?.name, "Ebm7")
        XCTAssertEqual(round.chordPart.chord(at: 24 * m)?.name, "Dm7")
    }
}
