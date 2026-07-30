//
//  SoloGeneratorTests.swift
//  ImprovisorEngineTests
//
//  Step 5 coverage: grammar expansion + note choosing.
//

import XCTest
@testable import ImprovisorEngine

final class SoloGeneratorTests: XCTestCase {

    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()
    var vocab: Vocabulary { SoloGeneratorTests.vocabulary }

    lazy var grammar: Grammar = {
        try! GrammarParser.parse(contentsOf: TestData.url("grammars/ArtFarmer.grammar"))
    }()

    /// So What's changes (16 Dm7 / 8 Ebm7 / 8 Dm7).
    private func soWhatChords() -> ChordPart {
        let ls = "(meter 4 4)(key 0)(style swing)\n(part (type chords))\n"
            + (Array(repeating: "Dm7 | / |", count: 8)
               + Array(repeating: "Ebm7 | / |", count: 4)
               + Array(repeating: "Dm7 | / |", count: 4)).joined(separator: " ")
        return LeadsheetParser.parse(ls, vocabulary: vocab).chordPart
    }

    func testGeneratesNotesInRange() {
        let params = SoloParameters(minPitch: 58, maxPitch: 82)
        let solo = SoloGenerator(grammar: grammar, parameters: params)
            .generate(chords: soWhatChords(), seed: 42)
        XCTAssertGreaterThan(solo.noteCount, 0)
        for note in solo.notes {
            XCTAssertGreaterThanOrEqual(note.pitch, 58)
            XCTAssertLessThanOrEqual(note.pitch, 82)
        }
    }

    func testFillsRoughlyTheForm() {
        let chords = soWhatChords()
        let solo = SoloGenerator(grammar: grammar).generate(chords: chords, seed: 1)
        // The abstract melody should span most of the form (bricks are 480+).
        XCTAssertGreaterThan(solo.size, chords.size - 480)
        XCTAssertLessThanOrEqual(solo.size, chords.size)
    }

    func testDeterministicWithSeed() {
        let gen = SoloGenerator(grammar: grammar)
        let a = gen.generate(chords: soWhatChords(), seed: 7)
        let b = gen.generate(chords: soWhatChords(), seed: 7)
        XCTAssertEqual(a, b)
    }

    func testVariesWithSeed() {
        let gen = SoloGenerator(grammar: grammar)
        let a = gen.generate(chords: soWhatChords(), seed: 7)
        let b = gen.generate(chords: soWhatChords(), seed: 500)
        XCTAssertNotEqual(a, b)
    }

    func testParametersFromGrammar() {
        let p = SoloParameters.from(grammar: grammar)
        XCTAssertEqual(p.minPitch, 58)
        XCTAssertEqual(p.maxPitch, 82)
        XCTAssertEqual(p.chordToneWeight, 0.7, accuracy: 0.001)
    }

    func testFirstChorusFavorsChordAndColorTones() {
        // Over Dm7 (D F A C chord, with color tones), most notes should be
        // inside the Dm7 chord/color palette — i.e. musically related.
        let chords = soWhatChords()
        let dm7 = ChordSymbol.parse("Dm7", vocabulary: vocab)!
        let usable = Set(dm7.chordTones.map(\.semitones) + dm7.colorTones.map(\.semitones))
        let solo = SoloGenerator(grammar: grammar).generate(chords: chords, seed: 3)

        // Look at the notes that fall in the first Dm7 section (first 8 bars).
        var slot = 0
        var inPalette = 0, total = 0
        for event in solo.events {
            if slot >= 8 * 480 { break }
            if case let .note(n) = event {
                total += 1
                if usable.contains(((n.pitch % 12) + 12) % 12) { inPalette += 1 }
            }
            slot += event.duration
        }
        XCTAssertGreaterThan(total, 0)
        // At least two-thirds should be chord/color tones (approach tones account
        // for the rest).
        XCTAssertGreaterThan(Double(inPalette) / Double(total), 0.6)
    }

    func testAllGrammarsExpandWithoutCrashing() {
        let chords = soWhatChords()
        let files = TestData.files(under: "grammars", ext: "grammar")
        var generated = 0
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let g = GrammarParser.parse(content)
            guard !g.rules.isEmpty else { continue }
            let solo = SoloGenerator(grammar: g).generate(chords: chords, seed: 11)
            _ = solo.noteCount // must not crash or hang
            generated += 1
        }
        XCTAssertGreaterThan(generated, 40)
    }
}
