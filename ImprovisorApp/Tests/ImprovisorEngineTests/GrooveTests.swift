//
//  GrooveTests.swift
//  ImprovisorEngineTests
//
//  Step 7 coverage: the swing-feel transform (port of Part.makeSwing).
//

import XCTest
@testable import ImprovisorEngine

final class GrooveTests: XCTestCase {

    private let beat = Constants.BEAT   // 120

    private func note(_ start: Int, _ dur: Int, pitch: Int = 60, ch: UInt8 = 1) -> ScheduledNote {
        ScheduledNote(pitch: pitch, velocity: 80, startTick: start, duration: dur, channel: ch)
    }

    /// Straight eighths on one beat: onsets at 0 and 60.
    private func eighthPair() -> [ScheduledNote] {
        [note(0, 60), note(60, 60)]
    }

    func testStraightSwingIsNoOp() {
        let notes = eighthPair()
        XCTAssertEqual(Groove.swung(notes, swing: 0.5), notes)
    }

    func testOffbeatEighthMovesToTripletSlot() {
        let swung = Groove.swung(eighthPair(), swing: 0.67)
        // Downbeat unmoved but extended to the new onset (0 → now ends at 80).
        XCTAssertEqual(swung[0].startTick, 0)
        XCTAssertEqual(swung[0].startTick + swung[0].duration, 80)
        // Offbeat delayed 60 → 80, end kept fixed at 120 (duration 60 → 40).
        XCTAssertEqual(swung[1].startTick, 80)   // int(120 * 0.67)
        XCTAssertEqual(swung[1].startTick + swung[1].duration, 120)
    }

    func testLightSwingRatio() {
        // 0.6 → offbeat at int(120*0.6) = 72.
        let swung = Groove.swung(eighthPair(), swing: 0.6)
        XCTAssertEqual(swung[1].startTick, 72)
    }

    func testDownbeatsAcrossBarsAreUnmoved() {
        // Quarter notes on each beat of a bar — no offbeat eighths to swing.
        let notes = (0..<4).map { note($0 * beat, beat) }
        let swung = Groove.swung(notes, swing: 0.67)
        XCTAssertEqual(swung.map(\.startTick), notes.map(\.startTick))
    }

    func testSixteenthRunIsNotSwung() {
        // Onsets at 0, 30, 60, 90 — a sixteenth at slot 30 blocks swinging.
        let notes = [note(0, 30), note(30, 30), note(60, 30), note(90, 30)]
        let swung = Groove.swung(notes, swing: 0.67)
        XCTAssertEqual(swung.map(\.startTick), notes.map(\.startTick))
    }

    func testShortOffbeatIsNotSwung() {
        // Offbeat onset at 60 but its rhythmic gap to the next onset (75) is only
        // 15 (< an eighth), so it must not swing.
        let notes = [note(0, 60), note(60, 15), note(75, 45)]
        let swung = Groove.swung(notes, swing: 0.67)
        XCTAssertEqual(swung[1].startTick, 60)
    }

    func testSwingsEveryBeatInABar() {
        // Offbeat eighths on all four beats: 60, 180, 300, 420 → +20 each.
        var notes: [ScheduledNote] = []
        for b in 0..<4 {
            notes.append(note(b * beat, 60))
            notes.append(note(b * beat + 60, 60))
        }
        let swung = Groove.swung(notes, swing: 0.67)
        let offbeats = swung.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element.startTick }
        XCTAssertEqual(offbeats, [80, 200, 320, 440])
    }

    func testChordGroupMovesTogether() {
        // A three-note chord struck on the offbeat moves as a unit.
        let notes = [
            note(0, 60, pitch: 60), note(0, 60, pitch: 64),
            note(60, 60, pitch: 67), note(60, 60, pitch: 71), note(60, 60, pitch: 74)
        ]
        let swung = Groove.swung(notes, swing: 0.67)
        for n in swung where [67, 71, 74].contains(n.pitch) {
            XCTAssertEqual(n.startTick, 80)
        }
    }

    func testRideCymbalPatternSwings() throws {
        // The swing style's ride is straight eighths; after swinging, the offbeat
        // ride hits should land on the triplet slot (beat + 80).
        let vocab = Vocabulary(source: try TestData.contents("vocab/My.voc"))
        let style = try StyleParser.parse(contentsOf: TestData.url("styles/swing.sty"))
        var part = ChordPart()
        part.append(ChordSymbol.parse("Dm7", vocabulary: vocab)!, duration: Constants.WHOLE)
        let acc = AccompanimentGenerator(style: style).generate(chordPart: part, seed: 3)

        let ride = acc.drums.filter { $0.pitch == 51 }   // Ride Cymbal 1
        XCTAssertGreaterThan(ride.count, 0)
        let swung = Groove.swung(acc.drums, swing: style.compSwing).filter { $0.pitch == 51 }
        // At least one ride hit should now sit on an offbeat triplet slot (…80 within a beat).
        XCTAssertTrue(swung.contains { $0.startTick % Constants.BEAT == 80 },
                      "expected a swung offbeat ride hit at beat+80")
    }
}
