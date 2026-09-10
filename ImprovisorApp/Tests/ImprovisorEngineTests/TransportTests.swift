//
//  TransportTests.swift
//  ImprovisorEngineTests
//
//  Phase 3 coverage for Transport, the real-time musical-clock scheduler.
//
//  Every test builds a Transport with `startScheduler: false` (no background
//  thread) paired with a FakeClock, then drives time by calling `advance` on
//  the clock and `tick()` on the transport directly and synchronously — no
//  real sleeping, no races. `deliverCallbacksSynchronously` makes the
//  on*/callback closures fire inline during `tick()` too.
//

import XCTest
@testable import ImprovisorEngine

/// A `TransportClock` the test fully controls: `now()` only changes when the
/// test calls `advance`.
final class FakeClock: TransportClock, @unchecked Sendable {
    private var currentNow: TimeInterval
    init(start: TimeInterval = 0) { currentNow = start }
    func now() -> TimeInterval { currentNow }
    /// Never invoked in these tests (the scheduler thread is disabled), but
    /// implemented for protocol conformance / production parity.
    func sleep(_ seconds: TimeInterval) { currentNow += seconds }
    func advance(_ seconds: TimeInterval) { currentNow += seconds }
}

/// Records every InstrumentBackend call, tagged with the fake time it
/// happened at (read from the same FakeClock the test drives).
final class RecordingBackend: InstrumentBackend {
    enum Call: Equatable {
        case start
        case stop
        case program(UInt8, channel: UInt8)
        case noteOn(pitch: UInt8, velocity: UInt8, channel: UInt8)
        case noteOff(pitch: UInt8, channel: UInt8)
        case allNotesOff
    }
    struct Recorded: Equatable {
        var call: Call
        var atFakeTime: TimeInterval
    }

    var calls: [Recorded] = []
    var currentTime: () -> TimeInterval = { 0 }

    func start() throws { record(.start) }
    func stop() { record(.stop) }
    func programChange(_ program: UInt8, channel: UInt8) { record(.program(program, channel: channel)) }
    func noteOn(_ pitch: UInt8, velocity: UInt8, channel: UInt8) {
        record(.noteOn(pitch: pitch, velocity: velocity, channel: channel))
    }
    func noteOff(_ pitch: UInt8, channel: UInt8) { record(.noteOff(pitch: pitch, channel: channel)) }
    func allNotesOff() { record(.allNotesOff) }

    private func record(_ call: Call) {
        calls.append(Recorded(call: call, atFakeTime: currentTime()))
    }
}

final class TransportTests: XCTestCase {

    private func makeTransport(start: TimeInterval = 0) -> (Transport, RecordingBackend, FakeClock) {
        let backend = RecordingBackend()
        let clock = FakeClock(start: start)
        backend.currentTime = { clock.now() }
        let transport = Transport(backend: backend, clock: clock, startScheduler: false)
        transport.deliverCallbacksSynchronously = true
        return (transport, backend, clock)
    }

    // MARK: (a) Slot-ordered events at correct fake times

    func testEventsFireInSlotOrderAtCorrectTimes() {
        let (transport, backend, clock) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 120, duration: 120, channel: 0)
        transport.load(tracks: [MIDITrack(name: "t", channel: 0, program: 0, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(120) // 120*120/60 = 240 slots/sec
        transport.play()
        transport.tick() // applies the play command: silence + program
        XCTAssertEqual(backend.calls.map(\.call), [.allNotesOff, .program(0, channel: 0)])
        backend.calls.removeAll()

        clock.advance(0.5) // slot 120 -> 120/240 = 0.5s
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.noteOn(pitch: 60, velocity: 80, channel: 0)])
        XCTAssertEqual(backend.calls[0].atFakeTime, 0.5, accuracy: 1e-9)
        backend.calls.removeAll()

        clock.advance(0.5) // slot 240 -> 1.0s; also the last event, so playback finishes right after
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.noteOff(pitch: 60, channel: 0), .allNotesOff])
        XCTAssertEqual(backend.calls[0].atFakeTime, 1.0, accuracy: 1e-9)
    }

    // MARK: (b) Live tempo change halves remaining wall time

    func testDoublingTempoMidwayHalvesRemainingWallTime() {
        let (transport, backend, clock) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 240, duration: 10, channel: 0)
        transport.load(tracks: [MIDITrack(name: "t", channel: 0, program: nil, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(60) // 60*120/60 = 120 slots/sec
        transport.play()
        transport.tick()
        backend.calls.removeAll()

        clock.advance(1.0) // halfway: position = 120 slots of 240
        transport.tick()
        XCTAssertTrue(backend.calls.isEmpty)
        XCTAssertEqual(transport.positionSlot, 120)

        transport.setTempo(120) // double: remaining 120 slots now take 0.5s, not 1.0s

        clock.advance(0.4)
        transport.tick()
        XCTAssertTrue(backend.calls.isEmpty, "must not fire before the halved remaining time elapses")

        clock.advance(0.1) // total 0.5s since the tempo change
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.noteOn(pitch: 60, velocity: 80, channel: 0)])
    }

    // MARK: (c) Pause holds position, resume continues

    func testPauseHoldsPositionResumeContinues() {
        let (transport, backend, clock) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 240, duration: 10, channel: 0)
        transport.load(tracks: [MIDITrack(name: "t", channel: 0, program: nil, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(120) // 240 slots/sec
        transport.play()
        transport.tick()
        backend.calls.removeAll()

        clock.advance(0.5) // position = 120 slots
        transport.tick()
        XCTAssertEqual(transport.positionSlot, 120)

        transport.pause()
        XCTAssertEqual(transport.state, .paused)

        clock.advance(5.0) // large jump while paused must be ignored
        transport.tick()
        XCTAssertEqual(transport.positionSlot, 120)
        XCTAssertTrue(backend.calls.isEmpty)

        transport.resume()
        XCTAssertEqual(transport.state, .playing)

        clock.advance(0.5) // another 120 slots -> reaches slot 240, note fires
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.noteOn(pitch: 60, velocity: 80, channel: 0)])
    }

    // MARK: (d) Loop re-sends program changes and repeats notes

    func testLoopResendsProgramChangesAndRepeatsNotes() {
        let (transport, backend, clock) = makeTransport()
        let note = ScheduledNote(pitch: 64, velocity: 90, startTick: 0, duration: 60, channel: 0)
        transport.load(tracks: [MIDITrack(name: "t", channel: 0, program: 5, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(120) // 240 slots/sec
        transport.setLoop(LoopSpec(range: 0..<120, count: 1))
        transport.play()
        transport.tick() // play-apply + immediate slot-0 note-on, all in one tick
        XCTAssertEqual(backend.calls.map(\.call),
                       [.allNotesOff, .program(5, channel: 0), .noteOn(pitch: 64, velocity: 90, channel: 0)])
        backend.calls.removeAll()

        clock.advance(0.5) // slot 120: note-off (slot 60) fires, then the loop wraps and repeats
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [
            .noteOff(pitch: 64, channel: 0),
            .allNotesOff,
            .program(5, channel: 0),
            .noteOn(pitch: 64, velocity: 90, channel: 0)
        ])
        XCTAssertEqual(transport.positionSlot, 0, "loop wrap should rewind position by the loop length")
    }

    // MARK: (e) Muted channel drops note-ons, keeps note-offs

    func testMutedChannelDropsNoteOnKeepsNoteOff() {
        let (transport, backend, clock) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 100, startTick: 0, duration: 10, channel: 2)
        transport.load(tracks: [MIDITrack(name: "t", channel: 2, program: nil, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(120)
        transport.setMix(TrackMix(volume: 1, muted: true), channel: 2)
        transport.play()
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.allNotesOff], "note-on must be dropped while muted")
        backend.calls.removeAll()

        clock.advance(10.0 / 240.0) // slot 10: note-off; also the last event, so playback finishes right after
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.noteOff(pitch: 60, channel: 2), .allNotesOff],
                       "note-off must still be sent even while muted")
    }

    // MARK: (f) Volume scales velocity

    func testVolumeScalesVelocity() {
        let (transport, backend, _) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 100, startTick: 0, duration: 10, channel: 1)
        transport.load(tracks: [MIDITrack(name: "t", channel: 1, program: nil, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(120)
        transport.setMix(TrackMix(volume: 0.5), channel: 1)
        transport.setMasterVolume(0.5)
        transport.play()
        transport.tick()
        // round(100 * 0.5 * 0.5) = 25
        XCTAssertEqual(backend.calls.map(\.call),
                       [.allNotesOff, .noteOn(pitch: 60, velocity: 25, channel: 1)])
    }

    func testVolumeNeverRoundsAnAudibleNoteToZero() {
        let (transport, backend, _) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 1, startTick: 0, duration: 10, channel: 3)
        transport.load(tracks: [MIDITrack(name: "t", channel: 3, program: nil, notes: [note])], slotsPerMeasure: 480)
        transport.setMix(TrackMix(volume: 0.01), channel: 3)
        transport.play()
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.allNotesOff, .noteOn(pitch: 60, velocity: 1, channel: 3)])
    }

    // MARK: (g) Count-in clicks before slot 0, then transitions to .playing

    func testCountInEmitsClicksThenTransitionsToPlaying() {
        let (transport, backend, clock) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 0, duration: 10, channel: 0)
        transport.load(tracks: [MIDITrack(name: "t", channel: 0, program: nil, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(120) // 240 slots/sec
        transport.setCountIn(bars: 1) // 4 beats (480/120), starting at slot -480

        transport.play()
        transport.tick() // play-apply lands exactly on the first (downbeat) click
        XCTAssertEqual(transport.state, .countingIn)
        XCTAssertEqual(transport.positionSlot, -480)
        XCTAssertEqual(backend.calls.map(\.call), [.allNotesOff, .noteOn(pitch: 37, velocity: 100, channel: 9)])
        backend.calls.removeAll()

        clock.advance(30.0 / 240.0) // click duration BEAT/4 = 30 slots -> note-off
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.noteOff(pitch: 37, channel: 9)])
        backend.calls.removeAll()

        clock.advance(90.0 / 240.0) // next beat (slot -360): off-beat click, velocity 80
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.noteOn(pitch: 37, velocity: 80, channel: 9)])
        backend.calls.removeAll()

        clock.advance(1.5) // cross the remaining 360 slots into slot 0
        transport.tick()
        XCTAssertEqual(transport.state, .playing)
        XCTAssertEqual(transport.positionSlot, 0)
        XCTAssertTrue(backend.calls.map(\.call).contains(.noteOn(pitch: 60, velocity: 80, channel: 0)),
                      "the real tune should start right as count-in crosses slot 0")
    }

    // MARK: (h) Seek repositions

    func testSeekRepositions() {
        let (transport, backend, _) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 240, duration: 10, channel: 0)
        transport.load(tracks: [MIDITrack(name: "t", channel: 0, program: 3, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(120)
        transport.play()
        transport.tick()
        backend.calls.removeAll()

        transport.seek(toSlot: 240)
        transport.tick()
        XCTAssertEqual(transport.positionSlot, 240)
        XCTAssertEqual(backend.calls.map(\.call),
                       [.allNotesOff, .program(3, channel: 0), .noteOn(pitch: 60, velocity: 80, channel: 0)])
    }

    // MARK: (i) Stop sends allNotesOff and state .stopped

    func testStopSendsAllNotesOffAndStops() {
        let (transport, backend, _) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 0, duration: 10, channel: 0)
        transport.load(tracks: [MIDITrack(name: "t", channel: 0, program: nil, notes: [note])], slotsPerMeasure: 480)
        transport.play()
        transport.tick()
        backend.calls.removeAll()

        transport.stop()
        XCTAssertEqual(transport.state, .playing, "stop is applied on the next tick, not immediately")
        transport.tick()
        XCTAssertEqual(transport.state, .stopped)
        XCTAssertEqual(backend.calls.map(\.call), [.allNotesOff])
        XCTAssertEqual(transport.positionSlot, 0)
    }

    // MARK: Bonus: onFinished / onStateChange fire when playback runs off the end

    func testFinishesAndNotifiesWhenEventsRunOutWithNoLoop() {
        let (transport, backend, clock) = makeTransport()
        let note = ScheduledNote(pitch: 60, velocity: 80, startTick: 0, duration: 10, channel: 0)
        transport.load(tracks: [MIDITrack(name: "t", channel: 0, program: nil, notes: [note])], slotsPerMeasure: 480)
        transport.setTempo(120)

        nonisolated(unsafe) var finished = false
        nonisolated(unsafe) var lastState: Transport.State?
        transport.onFinished = { finished = true }
        transport.onStateChange = { lastState = $0 }

        transport.play()
        transport.tick() // fires note-on immediately (slot 0)
        backend.calls.removeAll()

        clock.advance(10.0 / 240.0) // slot 10: note-off, then no more events -> finish
        transport.tick()
        XCTAssertEqual(backend.calls.map(\.call), [.noteOff(pitch: 60, channel: 0), .allNotesOff])
        XCTAssertTrue(finished)
        XCTAssertEqual(lastState, .stopped)
        XCTAssertEqual(transport.state, .stopped)
    }

    // MARK: (j) SlotTimeline ordering equals PlaybackTimeline ordering

    func testSlotTimelineOrderingMatchesPlaybackTimeline() {
        let a = ScheduledNote(pitch: 60, velocity: 80, startTick: 0, duration: 120, channel: 0)
        let b = ScheduledNote(pitch: 67, velocity: 80, startTick: 120, duration: 120, channel: 0)
        let tracks = [MIDITrack(name: "t", channel: 0, program: 4, notes: [a, b])]
        let tempo = 100.0

        let slotEvents = SlotTimeline.events(tracks: tracks, loops: 2)
        let playbackEvents = PlaybackTimeline.events(tracks: tracks, tempoBPM: tempo, loops: 2)

        XCTAssertEqual(slotEvents.count, playbackEvents.count)
        let secondsPerSlot = 60.0 / (tempo * Double(Constants.BEAT))
        for (s, p) in zip(slotEvents, playbackEvents) {
            XCTAssertEqual(p.seconds, Double(s.slot) * secondsPerSlot, accuracy: 1e-9)
            XCTAssertEqual(p.channel, s.channel)
            XCTAssertEqual(p.kind, s.kind)
        }
    }
}
