//
//  PlaybackTimelineTests.swift
//  ImprovisorEngineTests
//
//  Step 8 coverage: the pure timeline builder that feeds any InstrumentBackend.
//

import XCTest
@testable import ImprovisorEngine

final class PlaybackTimelineTests: XCTestCase {

    private func track(program: UInt8?, notes: [ScheduledNote], channel: UInt8 = 0) -> MIDITrack {
        MIDITrack(name: "t", channel: channel, program: program, notes: notes)
    }

    func testNoteBecomesOnOffAtSlotTiming() {
        // 120 BPM → one quarter (120 slots) = 0.5s, so 1 slot = 1/240 s.
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 120, duration: 120, channel: 0)
        let events = PlaybackTimeline.events(tracks: [track(program: 0, notes: [note])], tempoBPM: 120)

        // program @0, note-on @0.5s, note-off @1.0s
        XCTAssertEqual(events[0].kind, .program(0))
        let on = events.first { $0.kind == .noteOn(pitch: 60, velocity: 80) }!
        let off = events.first { $0.kind == .noteOff(pitch: 60) }!
        XCTAssertEqual(on.seconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(off.seconds, 1.0, accuracy: 1e-9)
    }

    func testTieOrderingProgramThenOffThenOn() {
        // A note-off and a note-on at the same instant: off must precede on.
        let a = ScheduledNote(pitch: 60, velocity: 80, startTick: 0, duration: 120, channel: 0)
        let b = ScheduledNote(pitch: 67, velocity: 80, startTick: 120, duration: 120, channel: 0)
        let events = PlaybackTimeline.events(tracks: [track(program: 4, notes: [a, b])], tempoBPM: 120)
        // At t=0.5s: off(60) then on(67).
        let atHalf = events.filter { abs($0.seconds - 0.5) < 1e-9 }
        XCTAssertEqual(atHalf.map(\.kind), [.noteOff(pitch: 60), .noteOn(pitch: 67, velocity: 80)])
    }

    func testLoopOffsetsRepeatsByFormSpan() {
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 0, duration: 240, channel: 0)
        let events = PlaybackTimeline.events(tracks: [track(program: nil, notes: [note])],
                                             tempoBPM: 120, loops: 2)
        let ons = events.filter { $0.kind == .noteOn(pitch: 60, velocity: 80) }.map(\.seconds)
        // span = 240 slots = 1.0s; second loop's note-on is one span later.
        XCTAssertEqual(ons.count, 2)
        XCTAssertEqual(ons[0], 0.0, accuracy: 1e-9)
        XCTAssertEqual(ons[1], 1.0, accuracy: 1e-9)
    }

    func testProgramEmittedOnceAcrossLoops() {
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 0, duration: 120, channel: 0)
        let events = PlaybackTimeline.events(tracks: [track(program: 33, notes: [note])],
                                             tempoBPM: 120, loops: 3)
        XCTAssertEqual(events.filter { $0.kind == .program(33) }.count, 1)
    }

    func testTempoScalesTiming() {
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 120, duration: 120, channel: 0)
        let slow = PlaybackTimeline.events(tracks: [track(program: nil, notes: [note])], tempoBPM: 60)
        // At 60 BPM a quarter = 1.0s, so the note-on at slot 120 lands at 1.0s.
        XCTAssertEqual(slow.first { $0.kind == .noteOn(pitch: 60, velocity: 80) }!.seconds, 1.0, accuracy: 1e-9)
    }
}
