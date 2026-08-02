//
//  PushTests.swift
//  ImprovisorEngineTests
//
//  Coverage for chord push/anticipation (port of Style.makeChords' `time -=
//  deltaT`). Push is chord-only in Impro-Visor; bass has none.
//

import XCTest
@testable import ImprovisorEngine

final class PushTests: XCTestCase {

    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()
    var vocab: Vocabulary { PushTests.vocabulary }

    /// Two whole-note C chords back to back.
    private func twoChords() -> ChordPart {
        var part = ChordPart()
        let c = ChordSymbol.parse("C", vocabulary: vocab)!
        part.append(c, duration: Constants.WHOLE)   // 0..480
        part.append(c, duration: Constants.WHOLE)   // 480..960
        return part
    }

    private func style(push: String?) -> Style {
        var s = Style(name: "push-test")
        s.chordPatterns = [Pattern(rules: ["X4"], weight: 1, push: push)]
        return s
    }

    func testChordPushAnticipatesLaterChord() {
        let push = Duration.slots("8")   // 60 slots
        let acc = AccompanimentGenerator(style: style(push: "8")).generate(chordPart: twoChords(), seed: 1)
        let onsets = Set(acc.chords.map(\.startTick))

        // First chord can't be pushed before tick 0.
        XCTAssertTrue(onsets.contains(0), "first chord should start on the beat")
        // Second chord's first strike is pulled earlier by the push amount…
        XCTAssertTrue(onsets.contains(Constants.WHOLE - push), "second chord should be anticipated")
        // …so nothing strikes on its nominal downbeat.
        XCTAssertFalse(onsets.contains(Constants.WHOLE), "the downbeat strike should have moved earlier")
        // No negative onsets.
        XCTAssertTrue(onsets.allSatisfy { $0 >= 0 })
    }

    func testWithoutPushChordsAreOnTheGrid() {
        let acc = AccompanimentGenerator(style: style(push: nil)).generate(chordPart: twoChords(), seed: 1)
        let onsets = Set(acc.chords.map(\.startTick))
        XCTAssertTrue(onsets.contains(0))
        XCTAssertTrue(onsets.contains(Constants.WHOLE), "second chord starts on its downbeat when unpushed")
        XCTAssertFalse(onsets.contains(Constants.WHOLE - Duration.slots("8")))
    }

    func testSwingStyleParsesChordPush() throws {
        let style = try StyleParser.parse(contentsOf: TestData.url("styles/swing.sty"))
        XCTAssertTrue(style.chordPatterns.contains { $0.push == "8/3" },
                      "swing.sty has a chord pattern with (push 8/3)")
    }
}
