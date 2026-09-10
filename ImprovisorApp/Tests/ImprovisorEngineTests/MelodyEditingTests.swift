//
//  MelodyEditingTests.swift
//  ImprovisorEngineTests
//
//  Phase 6: slot-indexed melody edits and harmonic snapping.
//

import XCTest
@testable import ImprovisorEngine

final class MelodyEditingTests: XCTestCase {

    static let vocabulary = Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    var vocab: Vocabulary { MelodyEditingTests.vocabulary }

    private func blank(_ bars: Int) -> MelodyPart { MelodyPart(events: [.rest(Rest(duration: bars * 480))]) }
    private func n(_ p: Int, _ d: Int) -> MusicEvent { .note(Note(pitch: p, duration: d, volume: 127)) }
    private func r(_ d: Int) -> MusicEvent { .rest(Rest(duration: d)) }

    func testSetNoteIntoRestsKeepsLength() {
        var part = blank(1)
        part.setNote(at: 0, pitch: 60, duration: 60)
        part.setNote(at: 60, pitch: 64, duration: 60)
        XCTAssertEqual(part.events, [n(60, 60), n(64, 60), r(360)])
        XCTAssertEqual(part.size, 480)
        part.setNote(at: 240, pitch: 67, duration: 120)
        XCTAssertEqual(part.events, [n(60, 60), n(64, 60), r(120), n(67, 120), r(120)])
    }

    func testOverwritingALongNoteLeavesItsTailAsARest() {
        var part = MelodyPart(events: [n(60, 480)])
        part.setNote(at: 120, pitch: 62, duration: 120)
        XCTAssertEqual(part.events, [n(60, 120), n(62, 120), r(240)])
    }

    func testEraseAndRemove() {
        var part = MelodyPart(events: [n(60, 120), n(62, 120), n(64, 120), n(65, 120)])
        var erased = part
        erased.erase(range: 120..<360)
        XCTAssertEqual(erased.events, [n(60, 120), r(240), n(65, 120)])
        part.remove(range: 120..<360)
        XCTAssertEqual(part.events, [n(60, 120), n(65, 120)])
        XCTAssertEqual(part.size, 240)
    }

    func testInsertShiftsLaterEvents() {
        var part = MelodyPart(events: [n(60, 120), n(62, 120)])
        part.insert([n(70, 60)], at: 120)
        XCTAssertEqual(part.events, [n(60, 120), n(70, 60), n(62, 120)])
        part.insert([n(71, 60)], at: 60)   // splits the first note
        XCTAssertEqual(part.events, [n(60, 60), n(71, 60), n(60, 60), n(70, 60), n(62, 120)])
    }

    func testExtendNoteConsumesWhatFollows() {
        var part = blank(1)
        part.setNote(at: 0, pitch: 60, duration: 60)
        part.extendNote(endingAt: 60, by: 60)
        XCTAssertEqual(part.events, [n(60, 120), r(360)])
        part.setNote(at: 120, pitch: 62, duration: 60)
        part.extendNote(endingAt: 120, by: 120)          // extends the C over the D
        XCTAssertEqual(part.events, [n(60, 240), r(240)])
    }

    func testEventsInRangeAndQueries() {
        let part = MelodyPart(events: [n(60, 120), r(120), n(64, 240)])
        XCTAssertEqual(part.events(in: 60..<300), [n(60, 60), r(120), n(64, 60)])
        XCTAssertEqual(part.event(atSlot: 130)?.index, 1)
        XCTAssertEqual(part.lastNote(atOrBefore: 200)?.event, n(60, 120))
        XCTAssertNil(part.event(atSlot: 480))
    }

    func testTransposeAndEnharmonics() {
        var part = MelodyPart(events: [n(60, 120), n(61, 120), r(240)])
        part.transpose(range: 0..<240, by: 12)
        XCTAssertEqual(part.notes.map(\.pitch), [72, 73])
        part.mapNotes(in: 120..<240) { $0.enharmonicToggled() }
        XCTAssertEqual(part.notes[1].spelling, .sharp)
        part.mapNotes(in: 120..<240) { $0.enharmonicToggled() }
        XCTAssertEqual(part.notes[1].spelling, .flat)
        XCTAssertEqual(Note(pitch: 60, duration: 1).enharmonicToggled().spelling, .sharp) // b#
    }

    func testTruncateAndFill() {
        var part = MelodyPart(events: [n(60, 600)])
        part.truncate(to: 480)
        XCTAssertEqual(part.events, [n(60, 480)])
        part.fill(to: 960)
        XCTAssertEqual(part.events, [n(60, 480), r(480)])
    }

    // MARK: Harmony

    func testSnapToChordTones() {
        let c7 = ChordSymbol.parse("C7", vocabulary: vocab)!
        XCTAssertEqual(Harmony.snap(61, chord: c7, mode: .chordTones), 62 == 62 ? Harmony.nearest(61, in: [0, 4, 7, 10]) : 0)
        XCTAssertEqual(Harmony.nearest(61, in: [0, 4, 7, 10]), 60)      // 61 → C (down 1) vs E (up 3)
        XCTAssertEqual(Harmony.nearest(62, in: [0, 4, 7, 10]), 64)      // tie → prefers up
        XCTAssertEqual(Harmony.nearest(62, in: [0, 4, 7, 10], preferUp: false), 60)
        XCTAssertEqual(Harmony.snap(66, chord: c7, mode: .chordTones), 67)
        XCTAssertEqual(Harmony.snap(66, chord: nil, mode: .chordTones), 66)
        XCTAssertEqual(Harmony.snap(66, chord: c7, mode: .chromatic), 66)
        let scale = Harmony.pitchClasses(for: c7, mode: .scale)
        XCTAssertTrue(scale.contains(10) && scale.contains(4))
        XCTAssertTrue(Harmony.approachPitchClasses(for: c7).contains(1))
        XCTAssertFalse(Harmony.approachPitchClasses(for: c7).contains(0))
    }

    func testDiatonicStepAndLetterPitch() {
        let g = Key(index: 1)
        XCTAssertEqual(Harmony.step(60, by: 1, key: g), 62)
        XCTAssertEqual(Harmony.step(64, by: 1, key: g), 66)      // E → F# in G major
        XCTAssertEqual(Harmony.step(66, by: -1, key: g), 64)
        XCTAssertEqual(Harmony.step(65, by: 1, key: g), 66)      // F (non-scale) → F#
        XCTAssertEqual(Harmony.pitch(letter: 3, octave: 4, key: g), 66)             // F in G major = F#
        XCTAssertEqual(Harmony.pitch(letter: 3, octave: 4, key: g, natural: true), 65)
        XCTAssertEqual(Harmony.pitch(letter: 0, octave: 4, key: .cMajor), 60)
        XCTAssertEqual(Harmony.pitch(letter: 6, octave: 3, key: Key(index: -2)), 58) // Bb in Bb major
    }
}
