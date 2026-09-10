//
//  Transport.swift
//  ImprovisorEngine
//
//  Phase 3: a real-time transport with a MUSICAL clock. Unlike SequencePlayer
//  (Step 8), which bakes wall-clock seconds into every event at play() time,
//  Transport keeps position in slots and advances it every tick by
//  `Δt * tempo * BEAT / 60`, reading the current tempo fresh each tick. That
//  means `setTempo` takes effect immediately, mid-playback, with no re-bake.
//
//  Threading model: all public setters just flip fields (or, where a backend
//  call is implied — play/seek/stop — queue a `Command`) under one lock and
//  return immediately. The actual work — advancing position, deciding which
//  events are due, and touching the `InstrumentBackend` — happens only in
//  `tick()`, which runs on a single dedicated scheduler thread in production.
//  Keeping all backend I/O on that one thread means callers never race each
//  other at the backend.
//
//  `tick()` is `internal` (not `private`) on purpose: it is the seam tests use
//  to drive the transport deterministically. A test builds a `Transport` with
//  `startScheduler: false` (no background thread), pairs it with a `FakeClock`
//  it controls, and calls `tick()` directly after advancing the fake clock —
//  no races, no real sleeping.
//

import Foundation

/// A source of time for the transport's scheduler. Production code uses
/// `SystemClock`; tests inject a fake so they can drive time deterministically
/// without real sleeping.
public protocol TransportClock: Sendable {
    func now() -> TimeInterval
    func sleep(_ seconds: TimeInterval)
}

/// Wall-clock `TransportClock` used in production.
public struct SystemClock: TransportClock {
    public init() {}
    public func now() -> TimeInterval { Date().timeIntervalSinceReferenceDate }
    public func sleep(_ seconds: TimeInterval) {
        guard seconds > 0 else { return }
        Thread.sleep(forTimeInterval: seconds)
    }
}

/// A loop region in slot space. `count` is the number of times the loop still
/// has left to repeat; `nil` means loop forever.
public struct LoopSpec: Equatable, Sendable {
    public var range: Range<Int>
    public var count: Int?

    public init(range: Range<Int>, count: Int? = nil) {
        self.range = range
        self.count = count
    }
}

/// A real-time scheduler that drives an `InstrumentBackend` from a loaded set
/// of tracks, with live tempo, loop, mute/volume, count-in and seek.
///
/// `@unchecked Sendable`: all mutable state lives behind `lock` (a single
/// `NSLock`); every public method takes the lock for the duration of its
/// (cheap) mutation, and the one place that does real work — `tick()` —
/// collects backend/callback side effects while locked, then runs them after
/// unlocking, so a callback can safely call back into the transport (e.g.
/// `pause()` from inside `onStateChange`) without deadlocking.
public final class Transport: @unchecked Sendable {

    public enum State: Sendable, Equatable {
        case stopped, countingIn, playing, paused
    }

    // MARK: Callbacks

    /// Called with the current slot position, throttled to ~30 Hz of clock
    /// time (not wall-clock time — a `FakeClock` in tests controls this too).
    public var onPosition: (@Sendable (Int) -> Void)?
    public var onStateChange: (@Sendable (State) -> Void)?
    /// Called once when playback runs off the end with no loop remaining.
    public var onFinished: (@Sendable () -> Void)?

    /// Test convenience: when true, callbacks fire synchronously on whatever
    /// thread calls `tick()` instead of being dispatched to the main queue.
    /// Production leaves this false.
    public var deliverCallbacksSynchronously = false

    // MARK: Construction

    private let backend: InstrumentBackend
    private let clock: TransportClock
    private var schedulerThread: Thread?
    private var isRunning = true

    private static let tickInterval: TimeInterval = 0.003
    private static let positionCallbackInterval: TimeInterval = 1.0 / 30.0

    public init(backend: InstrumentBackend, clock: TransportClock = SystemClock()) {
        self.backend = backend
        self.clock = clock
        let now = clock.now()
        self.lastTickTime = now
        self.lastPositionCallbackTime = now
        startSchedulerThread()
    }

    /// Test-only entry point (visible to `@testable import`): skips starting
    /// the real-time background thread so a test can call `tick()` directly.
    init(backend: InstrumentBackend, clock: TransportClock, startScheduler: Bool) {
        self.backend = backend
        self.clock = clock
        let now = clock.now()
        self.lastTickTime = now
        self.lastPositionCallbackTime = now
        if startScheduler { startSchedulerThread() }
    }

    deinit {
        isRunning = false
    }

    private func startSchedulerThread() {
        let thread = Thread { [weak self] in
            while true {
                guard let self, self.isRunning else { return }
                self.tick()
                self.clock.sleep(Self.tickInterval)
            }
        }
        thread.name = "ImprovisorEngine.Transport"
        thread.qualityOfService = .userInitiated
        thread.start()
        schedulerThread = thread
    }

    // MARK: Locked state

    private let lock = NSLock()

    private var _state: State = .stopped
    private var pausedFromState: State?
    private var _tempoBPM: Double = 120

    /// Position in slots. Negative during count-in.
    private var positionSlots: Double = 0
    private var loopSpec: LoopSpec?
    private var loopRemaining: Int?
    private var mixByChannel: [UInt8: TrackMix] = [:]
    private var masterVolume: Double = 1.0

    /// What `load()` produced: the flattened, tempo-agnostic slot timeline.
    private var loadedEvents: [SlotEvent] = []
    /// What the scheduler actually walks for the current play session — the
    /// same as `loadedEvents`, prefixed with count-in clicks when a count-in
    /// is active for this session.
    private var activeEvents: [SlotEvent] = []
    private var cursor: Int = 0

    private var countInBars: Int = 0
    private var slotsPerMeasure: Int = Constants.WHOLE

    private var lastTickTime: TimeInterval
    private var lastPositionCallbackTime: TimeInterval

    /// An action queued by `play`/`seek`/`stop` for the scheduler to apply on
    /// its next `tick()` — the only place that touches the backend, so plain
    /// setters never race the scheduler at the instrument.
    private enum Command {
        case reset(toSlot: Int, newState: State, resetLoopCount: Bool)
        case stop
    }
    private var pendingCommand: Command?

    // MARK: Read-only state

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    public var tempoBPM: Double {
        lock.lock(); defer { lock.unlock() }
        return _tempoBPM
    }

    public var positionSlot: Int {
        lock.lock(); defer { lock.unlock() }
        return Int(positionSlots.rounded(.down))
    }

    // MARK: Loading

    /// Flatten `tracks` into the transport's slot timeline and reset to
    /// stopped/position 0. Does not touch the backend.
    public func load(tracks: [MIDITrack], slotsPerMeasure: Int, loops: Int = 1) {
        let flat = SlotTimeline.events(tracks: tracks, loops: loops)
        lock.lock()
        loadedEvents = flat
        activeEvents = Self.stripPrograms(flat)
        self.slotsPerMeasure = max(1, slotsPerMeasure)
        cursor = 0
        positionSlots = 0
        pendingCommand = nil
        _state = .stopped
        loopRemaining = loopSpec?.count
        lock.unlock()
    }

    // MARK: Transport controls

    /// Start playback from `slot`. If a count-in is configured and `slot` is
    /// 0, playback starts in `.countingIn` at a negative position and crosses
    /// into `.playing` at slot 0 (see `advanceAndFire`). Backend effects
    /// (silence + program re-emit) happen on the next `tick()`.
    public func play(from slot: Int = 0) {
        lock.lock(); defer { lock.unlock() }
        if countInBars > 0 && slot == 0 {
            activeEvents = buildCountInClicks() + Self.stripPrograms(loadedEvents)
            pendingCommand = .reset(toSlot: -countInBars * slotsPerMeasure,
                                     newState: .countingIn, resetLoopCount: true)
        } else {
            activeEvents = Self.stripPrograms(loadedEvents)
            pendingCommand = .reset(toSlot: slot, newState: .playing, resetLoopCount: true)
        }
    }

    /// Freeze position. Does not silence the backend — any currently-sounding
    /// notes keep ringing (their note-offs simply won't arrive until resumed).
    public func pause() {
        var notify = false
        lock.lock()
        if _state == .playing || _state == .countingIn {
            pausedFromState = _state
            _state = .paused
            notify = true
        }
        lock.unlock()
        if notify { dispatchCallback { [weak self] in self?.onStateChange?(.paused) } }
    }

    /// Continue from the paused position at the current tempo.
    public func resume() {
        var resumed: State?
        lock.lock()
        if _state == .paused, let prev = pausedFromState {
            _state = prev
            pausedFromState = nil
            lastTickTime = clock.now() // don't charge the paused interval as elapsed time
            resumed = prev
        }
        lock.unlock()
        if let s = resumed { dispatchCallback { [weak self] in self?.onStateChange?(s) } }
    }

    /// Stop playback: silence the backend and reset to position 0. Applied on
    /// the next `tick()`.
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        pendingCommand = .stop
    }

    /// Reposition playback (queued for the next `tick()`), preserving the
    /// current play state. Silences the backend and re-emits program changes
    /// so instruments are correct after a jump.
    public func seek(toSlot slot: Int) {
        lock.lock(); defer { lock.unlock() }
        pendingCommand = .reset(toSlot: slot, newState: _state, resetLoopCount: false)
    }

    /// Clamped to 20…400 BPM. Takes effect on the very next tick since
    /// position is advanced using the current tempo each tick (no seconds are
    /// ever pre-baked).
    public func setTempo(_ bpm: Double) {
        lock.lock(); defer { lock.unlock() }
        _tempoBPM = min(400, max(20, bpm))
    }

    public func setLoop(_ spec: LoopSpec?) {
        lock.lock(); defer { lock.unlock() }
        loopSpec = spec
        loopRemaining = spec?.count
    }

    public func setMix(_ mix: TrackMix, channel: UInt8) {
        lock.lock(); defer { lock.unlock() }
        mixByChannel[channel] = mix
    }

    public func setMasterVolume(_ volume: Double) {
        lock.lock(); defer { lock.unlock() }
        masterVolume = min(1, max(0, volume))
    }

    /// 0 = no count-in. Only applies to a `play(from: 0)` call made after
    /// this is set.
    public func setCountIn(bars: Int) {
        lock.lock(); defer { lock.unlock() }
        countInBars = max(0, bars)
    }

    // MARK: Scheduler

    /// One scheduling step: apply any pending command, advance position by
    /// elapsed clock time at the current tempo, fire due events (with mix
    /// applied), handle count-in→playing and loop wrap/finish — all while
    /// locked — then run the collected backend calls and callbacks unlocked.
    ///
    /// Internal (not private) so tests can call it directly after advancing a
    /// `FakeClock`, driving the transport deterministically with no real
    /// background thread involved.
    func tick() {
        let now = clock.now()
        lock.lock()
        var effects: [Effect] = []

        if let cmd = pendingCommand {
            pendingCommand = nil
            applyCommand(cmd, now: now, effects: &effects)
        }

        let dt = now - lastTickTime
        lastTickTime = now
        let wasCountingIn = (_state == .countingIn)

        if (_state == .playing || _state == .countingIn) && dt > 0 {
            positionSlots += dt * _tempoBPM * Double(Constants.BEAT) / 60.0
        }

        if wasCountingIn && _state == .countingIn && positionSlots >= 0 {
            _state = .playing
            effects.append(.stateChange(.playing))
        }

        if _state == .playing || _state == .countingIn {
            advanceAndFire(&effects)
        }

        if now - lastPositionCallbackTime >= Self.positionCallbackInterval {
            lastPositionCallbackTime = now
            effects.append(.position(Int(positionSlots.rounded(.down))))
        }

        lock.unlock()
        perform(effects)
    }

    /// Must be called with `lock` held.
    private func applyCommand(_ cmd: Command, now: TimeInterval, effects: inout [Effect]) {
        switch cmd {
        case let .reset(toSlot, newState, resetLoopCount):
            effects.append(.allNotesOff)
            for e in loadedEvents where isProgramKind(e.kind) {
                appendDeliverEffect(e, into: &effects)
            }
            positionSlots = Double(toSlot)
            cursor = Self.firstIndex(in: activeEvents, atOrAfter: toSlot)
            let prev = _state
            _state = newState
            if resetLoopCount { loopRemaining = loopSpec?.count }
            lastTickTime = now
            if prev != newState { effects.append(.stateChange(newState)) }
        case .stop:
            effects.append(.allNotesOff)
            _state = .stopped
            cursor = 0
            positionSlots = 0
            activeEvents = Self.stripPrograms(loadedEvents)
            effects.append(.stateChange(.stopped))
        }
    }

    /// Fire every due event, handle loop wrap-around, and finish playback when
    /// events run out with no loop left. Must be called with `lock` held.
    private func advanceAndFire(_ effects: inout [Effect]) {
        while true {
            let floorSlot = Int(positionSlots.rounded(.down))
            while cursor < activeEvents.count && activeEvents[cursor].slot <= floorSlot {
                appendDeliverEffect(activeEvents[cursor], into: &effects)
                cursor += 1
            }
            guard _state == .playing, let loop = loopSpec,
                  positionSlots >= Double(loop.range.upperBound) else { break }
            if let remaining = loopRemaining {
                if remaining <= 0 {
                    finish(&effects)
                    return
                }
                loopRemaining = remaining - 1
            }
            effects.append(.allNotesOff)
            for e in loadedEvents where isProgramKind(e.kind) {
                appendDeliverEffect(e, into: &effects)
            }
            positionSlots -= Double(loop.range.count)
            cursor = Self.firstIndex(in: activeEvents, atOrAfter: loop.range.lowerBound)
        }
        if _state == .playing && loopSpec == nil && cursor >= activeEvents.count {
            finish(&effects)
        }
    }

    /// Must be called with `lock` held.
    private func finish(_ effects: inout [Effect]) {
        _state = .stopped
        effects.append(.allNotesOff)
        cursor = 0
        positionSlots = 0
        activeEvents = Self.stripPrograms(loadedEvents)
        effects.append(.stateChange(.stopped))
        effects.append(.finished)
    }

    /// Resolve mix/mute for a due event into a concrete backend effect, while
    /// still locked (so `perform` never needs to read `mixByChannel` after
    /// unlocking). Must be called with `lock` held.
    private func appendDeliverEffect(_ event: SlotEvent, into effects: inout [Effect]) {
        switch event.kind {
        case let .program(program):
            effects.append(.programChange(program, channel: event.channel))
        case let .noteOn(pitch, velocity):
            let mix = mixByChannel[event.channel] ?? TrackMix()
            if mix.muted { return } // drop noteOns only; matching noteOffs still pass through
            var scaled = Int((Double(velocity) * mix.volume * masterVolume).rounded())
            if velocity > 0 { scaled = max(1, scaled) }
            scaled = min(127, max(0, scaled))
            effects.append(.noteOn(pitch: pitch, velocity: UInt8(scaled), channel: event.channel))
        case let .noteOff(pitch):
            effects.append(.noteOff(pitch: pitch, channel: event.channel))
        }
    }

    private func isProgramKind(_ kind: PlaybackEvent.Kind) -> Bool {
        Self.isProgramKind(kind)
    }

    private static func isProgramKind(_ kind: PlaybackEvent.Kind) -> Bool {
        if case .program = kind { return true }
        return false
    }

    /// Program-change events are always re-emitted explicitly (on play/seek/
    /// loop-wrap, regardless of where the cursor lands) rather than walked by
    /// the normal due-event cursor — otherwise a reset that lands the cursor
    /// on slot 0 would fire the same program change twice. So the array the
    /// cursor walks never contains them.
    private static func stripPrograms(_ events: [SlotEvent]) -> [SlotEvent] {
        events.filter { !isProgramKind($0.kind) }
    }

    private func buildCountInClicks() -> [SlotEvent] {
        guard countInBars > 0 else { return [] }
        let beatsPerBar = max(1, slotsPerMeasure / Constants.BEAT)
        let totalBeats = countInBars * beatsPerBar
        let startSlot = -countInBars * slotsPerMeasure
        var clicks: [SlotEvent] = []
        clicks.reserveCapacity(totalBeats * 2)
        for b in 0..<totalBeats {
            let slot = startSlot + b * Constants.BEAT
            let velocity: UInt8 = (b % beatsPerBar == 0) ? 100 : 80
            clicks.append(SlotEvent(slot: slot, channel: Constants.DRUM_CHANNEL,
                                     kind: .noteOn(pitch: 37, velocity: velocity)))
            clicks.append(SlotEvent(slot: slot + Constants.BEAT / 4, channel: Constants.DRUM_CHANNEL,
                                     kind: .noteOff(pitch: 37)))
        }
        return clicks
    }

    /// Binary search: first index whose slot is >= `slot` (events are sorted
    /// ascending by slot). Used to reposition the cursor on play/seek/loop.
    private static func firstIndex(in events: [SlotEvent], atOrAfter slot: Int) -> Int {
        var lo = 0, hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if events[mid].slot < slot { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    // MARK: Effects (collected while locked, run after unlocking)

    private enum Effect {
        case allNotesOff
        case programChange(UInt8, channel: UInt8)
        case noteOn(pitch: UInt8, velocity: UInt8, channel: UInt8)
        case noteOff(pitch: UInt8, channel: UInt8)
        case stateChange(State)
        case position(Int)
        case finished
    }

    private func perform(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .allNotesOff:
                backend.allNotesOff()
            case let .programChange(program, channel):
                backend.programChange(program, channel: channel)
            case let .noteOn(pitch, velocity, channel):
                backend.noteOn(pitch, velocity: velocity, channel: channel)
            case let .noteOff(pitch, channel):
                backend.noteOff(pitch, channel: channel)
            case let .stateChange(state):
                dispatchCallback { [weak self] in self?.onStateChange?(state) }
            case let .position(slot):
                dispatchCallback { [weak self] in self?.onPosition?(slot) }
            case .finished:
                dispatchCallback { [weak self] in self?.onFinished?() }
            }
        }
    }

    private func dispatchCallback(_ block: @escaping @Sendable () -> Void) {
        if deliverCallbacksSynchronously {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
