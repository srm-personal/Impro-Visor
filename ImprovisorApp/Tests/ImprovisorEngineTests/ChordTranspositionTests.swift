//
//  ChordTranspositionTests.swift
//  ImprovisorEngineTests
//
//  Phase 7: chord transposition/spelling, chord types, chord guessing, MIDI parsing.
//

import XCTest
@testable import ImprovisorEngine

final class ChordTranspositionTests: XCTestCase {

    static let vocabulary = Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    var vocab: Vocabulary { ChordTranspositionTests.vocabulary }

    func testTransposeRespellsForTheKey() {
        let dm7 = ChordSymbol.parse("Dm7", vocabulary: vocab)!
        XCTAssertEqual(dm7.transposed(by: 1, key: .cMajor, vocabulary: vocab).name, "Ebm7")
        XCTAssertEqual(dm7.transposed(by: 1, key: Key(index: 2), vocabulary: vocab).name, "D#m7")
        XCTAssertEqual(dm7.transposed(by: -2, key: .cMajor, vocabulary: vocab).name, "Cm7")
        let slash = ChordSymbol.parse("Am7/G", vocabulary: vocab)!
        XCTAssertEqual(slash.transposed(by: 3, key: .cMajor, vocabulary: vocab).name, "Cm7/Bb")
        XCTAssertEqual(ChordSymbol.noChord.transposed(by: 5, key: .cMajor, vocabulary: vocab).name, "NC")
        XCTAssertNotNil(dm7.transposed(by: 7, key: .cMajor, vocabulary: vocab).form)
    }

    func testEveryCorpusChordNameTransposes() throws {
        var names = Set<String>()
        for url in TestData.files(under: "leadsheets", ext: "ls").prefix(1200) {
            let score = try LeadsheetParser.parse(contentsOf: url, vocabulary: vocab)
            for e in score.chordPart.entries { names.insert(e.symbol.name) }
        }
        XCTAssertGreaterThan(names.count, 200)
        var unresolved: [String] = []
        for name in names {
            guard let symbol = ChordSymbol.parse(name, vocabulary: vocab), symbol.form != nil else { continue }
            for shift in 1...11 {
                let t = symbol.transposed(by: shift, key: .cMajor, vocabulary: vocab)
                if t.form == nil { unresolved.append("\(name)+\(shift)→\(t.name)") }
                XCTAssertEqual(t.root.semitones, (symbol.root.semitones + shift) % 12)
                XCTAssertEqual(t.type, symbol.type)
            }
        }
        XCTAssertTrue(unresolved.isEmpty, unresolved.prefix(10).joined(separator: ", "))
    }

    func testChordPartTransposition() {
        var part = ChordPart()
        part.append(ChordSymbol.parse("C", vocabulary: vocab)!, duration: 480)
        part.append(ChordSymbol.parse("F7", vocabulary: vocab)!, duration: 480)
        let up = part.transposed(by: 2, key: Key(index: 2), vocabulary: vocab)
        XCTAssertEqual(up.entries.map(\.symbol.name), ["D", "G7"])
        let partial = part.transposed(range: 480..<960, by: 2, key: .cMajor, vocabulary: vocab)
        XCTAssertEqual(partial.entries.map(\.symbol.name), ["C", "G7"])
        XCTAssertEqual(partial.size, 960)
    }

    func testChordTypesList() {
        let types = vocab.chordTypes
        XCTAssertTrue(types.contains("m7") && types.contains("7") && types.contains("maj7") && types.contains(""))
        XCTAssertGreaterThan(types.count, 100)
        XCTAssertEqual(types.first, "")
    }

    func testChordGuesser() {
        XCTAssertEqual(ChordGuesser.name(forPitches: [60, 64, 67, 70], vocabulary: vocab), "C7")
        XCTAssertEqual(ChordGuesser.name(forPitches: [62, 65, 69, 72], vocabulary: vocab), "Dm7")
        XCTAssertEqual(ChordGuesser.name(forPitches: [55, 59, 62], vocabulary: vocab), "G")
        XCTAssertEqual(ChordGuesser.name(forPitches: [58, 62, 65, 69], vocabulary: vocab), "BbM7")
        XCTAssertNil(ChordGuesser.name(forPitches: [60], vocabulary: vocab))
    }

    func testMIDIParsing() {
        XCTAssertEqual(MIDIInputSource.parse(bytes: [0x90, 60, 100, 0x80, 60, 0, 0x91, 62, 0]),
                       [.noteOn(pitch: 60, velocity: 100, channel: 0), .noteOff(pitch: 60, channel: 0), .noteOff(pitch: 62, channel: 1)])
        XCTAssertEqual(MIDIInputSource.parse(bytes: [0xC0, 5, 0x90, 64, 1]), [.other, .noteOn(pitch: 64, velocity: 1, channel: 0)])
        // UMP MIDI 1.0 channel voice word: type 2, group 0, status 0x90, note 60, velocity 100.
        let word: UInt32 = (2 << 28) | (0x90 << 16) | (60 << 8) | 100
        XCTAssertEqual(MIDIInputSource.parse(words: [word]), [.noteOn(pitch: 60, velocity: 100, channel: 0)])
        XCTAssertEqual(MIDIInputSource.parse(words: [0x1000_0000]), [])

        let source = MIDIInputSource()
        final class Box: @unchecked Sendable { var on: [(UInt8, UInt8)] = []; var off: [UInt8] = [] }
        let box = Box()
        source.onNoteOn = { p, v in box.on.append((p, v)) }
        source.onNoteOff = { p in box.off.append(p) }
        source.deliver(bytes: [0x90, 67, 90, 0x80, 67, 0])
        XCTAssertEqual(box.on.map(\.0), [67]); XCTAssertEqual(box.off, [67])
    }
}
