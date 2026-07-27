//
//  AccompanimentTests.swift
//  ImprovisorEngineTests
//
//  Step 4 coverage: bass/chord/drum generation from a Style + chord progression.
//

import XCTest
@testable import ImprovisorEngine

final class AccompanimentTests: XCTestCase {

    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()
    var vocab: Vocabulary { AccompanimentTests.vocabulary }

    lazy var swing: Style = {
        try! StyleParser.parse(contentsOf: TestData.url("styles/swing.sty"))
    }()

    /// A ii-V-I: Dm7 | G7 | Cmaj7 | Cmaj7.
    private func iiVI() -> ChordPart {
        var part = ChordPart()
        let m = Meter.fourFour.slotsPerMeasure
        for name in ["Dm7", "G7", "Cmaj7", "Cmaj7"] {
            part.append(ChordSymbol.parse(name, vocabulary: vocab)!, duration: m)
        }
        return part
    }

    func testBassInRegister() {
        let gen = AccompanimentGenerator(style: swing)
        let acc = gen.generate(chordPart: iiVI(), seed: 42)
        XCTAssertGreaterThan(acc.bass.count, 0)

        // swing.sty: bass-low g-- (43), bass-high c (60). Allow the placement
        // helper's clamping slack of an octave.
        for note in acc.bass {
            XCTAssertGreaterThanOrEqual(note.pitch, 31)
            XCTAssertLessThanOrEqual(note.pitch, 60)
        }
        // The first bass note should be the root of Dm7 (D, pitch class 2).
        XCTAssertEqual(acc.bass.first.map { $0.pitch % 12 }, 2)
    }

    func testDrumsHaveRideCymbal() {
        let gen = AccompanimentGenerator(style: swing)
        let acc = gen.generate(chordPart: iiVI(), seed: 1)
        XCTAssertGreaterThan(acc.drums.count, 0)
        // Ride Cymbal 1 == MIDI 51; every swing drum pattern uses it.
        XCTAssertTrue(acc.drums.contains { $0.pitch == 51 }, "expected ride cymbal hits")
        // Drums are on the percussion channel.
        XCTAssertTrue(acc.drums.allSatisfy { $0.channel == Constants.DRUM_CHANNEL })
    }

    func testChordsInRegister() {
        let gen = AccompanimentGenerator(style: swing)
        let acc = gen.generate(chordPart: iiVI(), seed: 7)
        XCTAssertGreaterThan(acc.chords.count, 0)
        // swing.sty chord register: chord-low d- (49), chord-high a (69).
        for note in acc.chords {
            XCTAssertGreaterThanOrEqual(note.pitch, 37)
            XCTAssertLessThanOrEqual(note.pitch, 81)
        }
    }

    func testDeterministicWithSeed() {
        let gen = AccompanimentGenerator(style: swing)
        let a = gen.generate(chordPart: iiVI(), seed: 123)
        let b = gen.generate(chordPart: iiVI(), seed: 123)
        XCTAssertEqual(a, b)
    }

    func testVariesWithDifferentSeeds() {
        let gen = AccompanimentGenerator(style: swing)
        let a = gen.generate(chordPart: iiVI(), seed: 1)
        let b = gen.generate(chordPart: iiVI(), seed: 999)
        XCTAssertNotEqual(a.bass, b.bass)
    }

    func testEventsHaveValidMidiValues() {
        let gen = AccompanimentGenerator(style: swing)
        let acc = gen.generate(chordPart: iiVI(), seed: 5)
        for event in acc.allEvents {
            XCTAssertLessThanOrEqual(event.pitch, 127)
            XCTAssertLessThanOrEqual(event.velocity, 127)
            XCTAssertGreaterThanOrEqual(event.tick, 0)
        }
    }

    func testSoWhatFullAccompaniment() throws {
        let score = try LeadsheetParser.parse(
            contentsOf: TestData.url("leadsheets/imaginary-book/SoWhat.ls"),
            vocabulary: vocab
        )
        let gen = AccompanimentGenerator(style: swing)
        let acc = gen.generate(chordPart: score.chordPart, seed: 2024)
        XCTAssertGreaterThan(acc.bass.count, 0)
        XCTAssertGreaterThan(acc.chords.count, 0)
        XCTAssertGreaterThan(acc.drums.count, 0)
        // Bass should cover roughly the whole 32-bar form (last note near the end).
        let lastBassEnd = acc.bass.map { $0.startTick + $0.duration }.max() ?? 0
        XCTAssertGreaterThan(lastBassEnd, score.chordPart.size - score.meter.slotsPerMeasure)
    }
}
