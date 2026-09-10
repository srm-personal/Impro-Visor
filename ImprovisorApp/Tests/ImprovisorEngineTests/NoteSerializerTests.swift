//
//  NoteSerializerTests.swift
//  ImprovisorEngineTests
//
//  Melody token serialization (Phase 1): durations, spellings, octaves.
//

import XCTest
@testable import ImprovisorEngine

final class NoteSerializerTests: XCTestCase {

    func testDurationStrings() {
        let cases: [(Int, String)] = [
            (480, "1"), (240, "2"), (120, "4"), (60, "8"), (30, "16"), (15, "32"),
            (160, "2/3"), (80, "4/3"), (40, "8/3"), (20, "16/3"), (10, "32/3"),
            (96, "4/5"), (48, "8/5"), (24, "16/5"), (12, "32/5"),
            (180, "4+8"), (360, "2+4"), (600, "1+4"), (140, "4+32+120+480"), // Java picks the shorter text
            (960, "1+1"), (1, "480"), (7, "120+240+480"), (0, "")
        ]
        for (slots, expected) in cases {
            XCTAssertEqual(NoteSerializer.durationString(slots), expected, "slots \(slots)")
        }
    }

    func testEveryDurationRoundTripsThroughTheParser() {
        for slots in 1...2000 {
            let text = NoteSerializer.durationString(slots)
            XCTAssertEqual(Duration.slots(text), slots, "duration \(slots) -> \(text)")
        }
    }

    func testPitchTokens() {
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 61, duration: 60, spelling: .sharp))), "c#8")
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 61, duration: 60, spelling: .flat))), "db8")
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 61, duration: 60))), "db8")
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 66, duration: 60))), "f#8")
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 72, duration: 120))), "c+4")
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 48, duration: 480))), "c-1")
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 36, duration: 60))), "c--8")
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 64, duration: 30, spelling: .flat))), "fb16")
        XCTAssertEqual(NoteSerializer.token(.note(Note(pitch: 60, duration: 60, spelling: .sharp))), "b#8")
        XCTAssertEqual(NoteSerializer.token(.rest(Rest(duration: 60))), "r8")
        XCTAssertEqual(NoteSerializer.token(.rest(Rest(duration: 480 * 3))), "r1+1+1")
    }

    func testTokensRoundTripThroughNoteSymbol() {
        let tokens = ["c#8", "db8", "e+4+8", "r8/3", "a-16", "fb2", "b#4", "g--1", "f#+32/3", "c4/5"]
        for token in tokens {
            let event = NoteSymbol.parse(token)!
            let written = NoteSerializer.token(event)
            XCTAssertEqual(written, token)
            XCTAssertEqual(NoteSymbol.parse(written), event)
        }
    }

    func testMelodyTextBreaksAtMeasures() {
        let part = MelodyPart(events: [
            .note(Note(pitch: 60, duration: 240)), .note(Note(pitch: 62, duration: 240)),
            .note(Note(pitch: 64, duration: 480)),
            .rest(Rest(duration: 120))
        ])
        let text = NoteSerializer.melodyText(part, slotsPerMeasure: 480)
        XCTAssertEqual(text, " c2 d2\n e1\n r4")
    }
}
