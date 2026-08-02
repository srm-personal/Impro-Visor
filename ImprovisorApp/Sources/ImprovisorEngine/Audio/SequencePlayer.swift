//
//  SequencePlayer.swift
//  ImprovisorEngine
//
//  Plays a flattened PlaybackTimeline in real time through an InstrumentBackend,
//  non-blocking and stoppable (unlike LiveMIDIPlayer.play, which blocks). Built
//  for the Step 8 app's transport: Play starts a background scheduler, Stop
//  cancels it and silences the backend.
//

import Foundation

public final class SequencePlayer {
    private let backend: InstrumentBackend
    private let queue = DispatchQueue(label: "ImprovisorEngine.SequencePlayer", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0

    /// Called on the main queue when playback finishes on its own (not on stop).
    public var onFinished: (@Sendable () -> Void)?

    public init(backend: InstrumentBackend) {
        self.backend = backend
    }

    private func currentGeneration() -> Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    private func bumpGeneration() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }

    /// Start playing `tracks` at `tempoBPM`. Any current playback is stopped
    /// first. Returns immediately; work happens on a background queue.
    public func play(tracks: [MIDITrack], tempoBPM: Double, loops: Int = 1) {
        let events = PlaybackTimeline.events(tracks: tracks, tempoBPM: tempoBPM, loops: loops)
        play(events: events)
    }

    public func play(events: [PlaybackEvent]) {
        stop()
        let gen = bumpGeneration()
        try? backend.start()

        queue.async { [weak self] in
            guard let self else { return }
            let start = Date()
            for event in events {
                if self.currentGeneration() != gen { return }
                // Sleep until the event time, waking periodically so Stop is snappy.
                while true {
                    let remaining = start.addingTimeInterval(event.seconds).timeIntervalSinceNow
                    if remaining <= 0 { break }
                    if self.currentGeneration() != gen { return }
                    Thread.sleep(forTimeInterval: min(remaining, 0.05))
                }
                self.deliver(event)
            }
            Thread.sleep(forTimeInterval: 0.2)
            if self.currentGeneration() == gen {
                self.backend.allNotesOff()
                let handler = self.onFinished
                DispatchQueue.main.async { handler?() }
            }
        }
    }

    /// Stop playback and silence the backend.
    public func stop() {
        _ = bumpGeneration()
        backend.allNotesOff()
    }

    private func deliver(_ event: PlaybackEvent) {
        switch event.kind {
        case let .program(program):
            backend.programChange(program, channel: event.channel)
        case let .noteOn(pitch, velocity):
            backend.noteOn(pitch, velocity: velocity, channel: event.channel)
        case let .noteOff(pitch):
            backend.noteOff(pitch, channel: event.channel)
        }
    }
}
