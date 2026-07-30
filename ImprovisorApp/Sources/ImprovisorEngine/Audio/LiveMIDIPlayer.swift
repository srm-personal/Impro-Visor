//
//  LiveMIDIPlayer.swift
//  ImprovisorEngine
//
//  Streams generated notes live to a CoreMIDI destination — e.g. a hardware
//  digital piano like the Roland FP-90X — so playback uses the instrument's own
//  sound engine instead of the Mac's built-in General MIDI synth. This is the
//  first slice of the Step 7 audio work: real-time output timing over CoreMIDI.
//
//  (A companion in-app path will use AVAudioEngine + a SoundFont for users
//  without external hardware.)
//

#if canImport(CoreMIDI)
import Foundation
import CoreMIDI

public final class LiveMIDIPlayer {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private let destination: MIDIEndpointRef
    public let destinationName: String

    /// A discovered MIDI output destination.
    public struct Destination {
        public let index: Int
        public let name: String
    }

    /// All available CoreMIDI output destinations.
    public static func destinations() -> [Destination] {
        (0..<MIDIGetNumberOfDestinations()).map { i in
            Destination(index: i, name: name(of: MIDIGetDestination(i)))
        }
    }

    private static func name(of endpoint: MIDIEndpointRef) -> String {
        var cf: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &cf) == noErr,
              let value = cf?.takeRetainedValue()
        else { return "" }
        return value as String
    }

    /// Create a player targeting the destination whose name contains `hint`
    /// (case-insensitive); if `hint` is nil, the first destination is used.
    /// Returns `nil` if there are no destinations or no match.
    public init?(destinationHint hint: String?) {
        let all = LiveMIDIPlayer.destinations()
        guard !all.isEmpty else { return nil }

        let chosen: Destination
        if let hint, !hint.isEmpty {
            let lower = hint.lowercased()
            guard let match = all.first(where: { $0.name.lowercased().contains(lower) }) else {
                return nil
            }
            chosen = match
        } else {
            chosen = all[0]
        }

        self.destination = MIDIGetDestination(chosen.index)
        self.destinationName = chosen.name
        MIDIClientCreate("ImprovisorEngine" as CFString, nil, nil, &client)
        MIDIOutputPortCreate(client, "Out" as CFString, &port)
    }

    // MARK: Playback

    private struct TimedEvent {
        let seconds: Double
        let bytes: [UInt8]
        let noteOff: Bool
    }

    /// Play the tracks in real time, blocking until finished. Program-change
    /// messages set each channel's sound before the notes begin.
    public func play(tracks: [MIDITrack], tempoBPM: Double) {
        let secondsPerTick = 60.0 / (max(1, tempoBPM) * Double(Constants.BEAT))
        var events: [TimedEvent] = []

        for track in tracks {
            let ch = track.channel & 0x0F
            if let program = track.program {
                events.append(TimedEvent(seconds: 0, bytes: [0xC0 | ch, program & 0x7F], noteOff: false))
            }
            for note in track.notes {
                let pitch = clampByte(note.pitch)
                let vel = clampByte(note.velocity)
                events.append(TimedEvent(seconds: Double(note.startTick) * secondsPerTick,
                                         bytes: [0x90 | ch, pitch, vel], noteOff: false))
                events.append(TimedEvent(seconds: Double(note.startTick + max(1, note.duration)) * secondsPerTick,
                                         bytes: [0x80 | ch, pitch, 0], noteOff: true))
            }
        }

        // Order by time; at a tie, program changes and note-offs precede note-ons.
        events.sort { a, b in
            a.seconds != b.seconds ? a.seconds < b.seconds : (a.noteOff && !b.noteOff)
        }

        let start = Date()
        for event in events {
            let target = start.addingTimeInterval(event.seconds)
            let wait = target.timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            send(event.bytes)
        }
        // Let the final notes ring briefly, then silence everything.
        Thread.sleep(forTimeInterval: 0.2)
        allNotesOff()
    }

    /// Send an All-Notes-Off / All-Sound-Off on every channel (panic).
    public func allNotesOff() {
        for ch in 0..<16 {
            send([0xB0 | UInt8(ch), 123, 0]) // All Notes Off
            send([0xB0 | UInt8(ch), 120, 0]) // All Sound Off
        }
    }

    private func send(_ bytes: [UInt8]) {
        var packetList = MIDIPacketList()
        let current = MIDIPacketListInit(&packetList)
        _ = MIDIPacketListAdd(&packetList, 1024, current, 0, bytes.count, bytes)
        MIDISend(port, destination, &packetList)
    }

    deinit {
        if port != 0 { MIDIPortDispose(port) }
        if client != 0 { MIDIClientDispose(client) }
    }
}
#endif
