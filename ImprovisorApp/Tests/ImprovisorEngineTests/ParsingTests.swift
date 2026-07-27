//
//  ParsingTests.swift
//  ImprovisorEngineTests
//
//  Step 3 coverage: leadsheet, style, grammar, and voicing parsers, validated
//  against the real data corpus.
//

import XCTest
@testable import ImprovisorEngine

final class ParsingTests: XCTestCase {

    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()
    var vocab: Vocabulary { ParsingTests.vocabulary }

    // MARK: Leadsheet

    func testLoadSoWhat() throws {
        let score = try LeadsheetParser.parse(
            contentsOf: TestData.url("leadsheets/imaginary-book/SoWhat.ls"),
            vocabulary: vocab
        )
        XCTAssertEqual(score.title, "So What?")
        XCTAssertEqual(score.composer, "Miles Davis")
        XCTAssertEqual(score.meter.numerator, 4)
        XCTAssertEqual(score.meter.denominator, 4)
        XCTAssertEqual(score.tempo, 160.0, accuracy: 0.01)
        XCTAssertEqual(score.styleName, "swing")
        XCTAssertEqual(score.key.index, 0)

        // So What is 32 bars: 16 Dm7, 8 Ebm7, 8 Dm7.
        XCTAssertEqual(score.chordPart.chord(at: 0)?.name, "Dm7")
        // Bar 17 (0-based measure 16) starts the Ebm7 section.
        let ebmSlot = 16 * score.meter.slotsPerMeasure
        XCTAssertEqual(score.chordPart.chord(at: ebmSlot)?.name, "Ebm7")
        // Total length should be 32 measures.
        XCTAssertEqual(score.measureCount, 32)

        // The melody part loaded.
        XCTAssertNotNil(score.melodyPart)
        XCTAssertGreaterThan(score.melodyPart?.count ?? 0, 0)
    }

    func testChordShorthandMultiplePerBar() throws {
        // A ii-V-I with two chords in the first bar.
        let ls = """
        (title Test)(meter 4 4)(key 0)(tempo 120.0)(style swing)
        (part (type chords))
        Dm7 G7 | Cmaj7 | Cmaj7 |
        """
        let score = LeadsheetParser.parse(ls, vocabulary: vocab)
        let m = score.meter.slotsPerMeasure // 480
        // Dm7 and G7 split bar 1: 240 slots each.
        XCTAssertEqual(score.chordPart.chord(at: 0)?.name, "Dm7")
        XCTAssertEqual(score.chordPart.chord(at: 240)?.name, "G7")
        XCTAssertEqual(score.chordPart.chord(at: m)?.name, "Cmaj7")
        // Cmaj7 spans bars 2 and 3 (960 slots total ending at 3*480).
        XCTAssertEqual(score.chordPart.chord(at: 3 * m - 1)?.name, "Cmaj7")
        XCTAssertEqual(score.chordPart.size, 3 * m)
    }

    func testSlashRepeatHoldsChord() throws {
        let ls = """
        (meter 4 4)(key 0)(style swing)
        (part (type chords))
        Dm7 | / | / | G7 |
        """
        let score = LeadsheetParser.parse(ls, vocabulary: vocab)
        let m = score.meter.slotsPerMeasure
        // Dm7 held for three bars via '/'.
        XCTAssertEqual(score.chordPart.chord(at: 0)?.name, "Dm7")
        XCTAssertEqual(score.chordPart.chord(at: 2 * m)?.name, "Dm7")
        XCTAssertEqual(score.chordPart.chord(at: 3 * m)?.name, "G7")
        XCTAssertEqual(score.chordPart.size, 4 * m)
    }

    func testParseAllLeadsheets() {
        let files = TestData.files(under: "leadsheets", ext: "ls")
        XCTAssertGreaterThan(files.count, 3000)
        var withChords = 0
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let score = LeadsheetParser.parse(content, vocabulary: vocab)
            if score.chordPart.count > 0 { withChords += 1 }
        }
        // The overwhelming majority of leadsheets have a chord progression.
        XCTAssertGreaterThan(withChords, 2500)
    }

    // MARK: Style

    func testLoadSwingStyle() throws {
        let style = try StyleParser.parse(contentsOf: TestData.url("styles/swing.sty"))
        XCTAssertEqual(style.name, "swing")
        XCTAssertEqual(style.swing, 0.67, accuracy: 0.01)
        XCTAssertEqual(style.compSwing, 0.67, accuracy: 0.01)
        XCTAssertEqual(style.voicingType, "open")
        XCTAssertGreaterThan(style.bassPatterns.count, 0)
        XCTAssertGreaterThan(style.chordPatterns.count, 0)
        XCTAssertGreaterThan(style.drumPatterns.count, 0)

        // First bass pattern is (rules B4 S4 C4 V90 A4)(weight 10.0).
        XCTAssertEqual(style.bassPatterns.first?.rules, ["B4", "S4", "C4", "V90", "A4"])
        XCTAssertEqual(style.bassPatterns.first?.weight, 10.0)

        // Drum patterns reference named instruments.
        let firstDrums = style.drumPatterns.first?.voices.map(\.name) ?? []
        XCTAssertTrue(firstDrums.contains("Ride_Cymbal_1"))
    }

    func testParseAllStyles() {
        let files = TestData.files(under: "styles", ext: "sty")
        XCTAssertGreaterThan(files.count, 100)
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            XCTAssertNoThrow(try StyleParser.parse(content),
                             "failed: \(file.lastPathComponent)")
        }
    }

    // MARK: Grammar

    func testLoadGrammar() throws {
        let grammar = try GrammarParser.parse(contentsOf: TestData.url("grammars/ArtFarmer.grammar"))
        XCTAssertEqual(grammar.number("chord-tone-weight"), 0.7)
        XCTAssertEqual(grammar.number("color-tone-weight"), 0.2)
        XCTAssertEqual(grammar.int("min-pitch"), 58)
        XCTAssertEqual(grammar.int("max-pitch"), 82)
        XCTAssertEqual(grammar.bool("avoid-repeats"), true)
        XCTAssertEqual(grammar.startSymbol, "P")
        XCTAssertGreaterThan(grammar.rules.count, 0)

        // A P-rule expands to a BRICK and a recursive P.
        let pRules = grammar.rules(for: "P")
        XCTAssertGreaterThan(pRules.count, 0)
        XCTAssertEqual(pRules.first?.weight, 1.0)
    }

    func testParseAllGrammars() {
        let files = TestData.files(under: "grammars", ext: "grammar")
        XCTAssertGreaterThan(files.count, 50)
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            _ = GrammarParser.parse(content) // must not crash
        }
    }

    // MARK: Voicing

    func testLoadVoicing() throws {
        let v = try VoicingParser.parse(contentsOf: TestData.url("voicings/Closed-High.fv"))
        XCTAssertEqual(v["LH-lower-limit"], 50)
        XCTAssertEqual(v.rhUpperLimit, 69)
    }
}
