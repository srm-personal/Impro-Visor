//
//  MIDIFileWriter.swift
//  ImprovisorEngine
//
//  Serializes generated notes to a Standard MIDI File (format 1) so the engine's
//  output can be auditioned in any player or DAW before the in-app CoreMIDI/
//  AVAudioEngine playback (Step 7) exists.
//
//  The slot system maps cleanly onto MIDI ticks: there are 120 slots per quarter
//  note, so the file's division (ticks-per-quarter) is set to 120 and each slot
//  is one tick.
//

import Foundation

/// One instrument track to be written to the MIDI file.
public struct MIDITrack {
    public var name: String
    /// MIDI channel (0–15). Drums use 9.
    public var channel: UInt8
    /// GM program to select on this channel, or `nil` to leave it unset
    /// (drums ignore program on channel 9).
    public var program: UInt8?
    public var notes: [ScheduledNote]

    public init(name: String, channel: UInt8, program: UInt8?, notes: [ScheduledNote]) {
        self.name = name
        self.channel = channel
        self.program = program
        self.notes = notes
    }
}

public enum MIDIFileWriter {
    /// Ticks per quarter note — equal to slots per quarter (Constants.BEAT).
    static let division = 120

    /// Build a Standard MIDI File from the given tracks at `tempoBPM`.
    public static func data(tracks: [MIDITrack], tempoBPM: Double) -> Data {
        var file = Data()

        // Header chunk: format 1, one conductor track + the instrument tracks.
        let trackCount = tracks.count + 1
        file.append(contentsOf: Array("MThd".utf8))
        file.appendUInt32(6)
        file.appendUInt16(1)                       // format 1
        file.appendUInt16(UInt16(trackCount))
        file.appendUInt16(UInt16(division))

        // Conductor track: just the tempo.
        file.append(conductorTrack(tempoBPM: tempoBPM))

        // Instrument tracks.
        for track in tracks {
            file.append(instrumentTrack(track))
        }
        return file
    }

    /// Write a MIDI file to `url`.
    public static func write(tracks: [MIDITrack], tempoBPM: Double, to url: URL) throws {
        try data(tracks: tracks, tempoBPM: tempoBPM).write(to: url)
    }

    // MARK: Track builders

    private static func conductorTrack(tempoBPM: Double) -> Data {
        var body = Data()

        // "GM System On" SysEx so hardware SMF players (e.g. a Roland FP-90X
        // reading from a USB stick) enter General MIDI mode — drums on channel
        // 10, program changes honored per channel.
        body.appendVLQ(0)
        body.append(contentsOf: [0xF0])
        let gmOn: [UInt8] = [0x7E, 0x7F, 0x09, 0x01, 0xF7]
        body.appendVLQ(UInt32(gmOn.count))
        body.append(contentsOf: gmOn)

        let usPerQuarter = UInt32(60_000_000.0 / max(1, tempoBPM))
        body.appendVLQ(0)
        body.append(contentsOf: [0xFF, 0x51, 0x03])
        body.append(contentsOf: [
            UInt8((usPerQuarter >> 16) & 0xFF),
            UInt8((usPerQuarter >> 8) & 0xFF),
            UInt8(usPerQuarter & 0xFF)
        ])
        body.appendEndOfTrack()
        return chunk("MTrk", body)
    }

    private static func instrumentTrack(_ track: MIDITrack) -> Data {
        var body = Data()

        // Track name meta event.
        body.appendVLQ(0)
        body.append(contentsOf: [0xFF, 0x03])
        let nameBytes = Array(track.name.utf8)
        body.appendVLQ(UInt32(nameBytes.count))
        body.append(contentsOf: nameBytes)

        // Program change.
        if let program = track.program {
            body.appendVLQ(0)
            body.append(contentsOf: [0xC0 | (track.channel & 0x0F), program & 0x7F])
        }

        // Build note-on/off events, sorted by tick (offs before ons at a tie so
        // repeated pitches retrigger cleanly).
        struct Ev { let tick: Int; let on: Bool; let pitch: UInt8; let vel: UInt8 }
        var events: [Ev] = []
        for note in track.notes {
            events.append(Ev(tick: note.startTick, on: true,
                             pitch: clampByte(note.pitch), vel: clampByte(note.velocity)))
            events.append(Ev(tick: note.startTick + max(1, note.duration), on: false,
                             pitch: clampByte(note.pitch), vel: 0))
        }
        events.sort { a, b in a.tick != b.tick ? a.tick < b.tick : (!a.on && b.on) }

        var last = 0
        for ev in events {
            let delta = UInt32(max(0, ev.tick - last))
            last = ev.tick
            body.appendVLQ(delta)
            let status: UInt8 = (ev.on ? 0x90 : 0x80) | (track.channel & 0x0F)
            body.append(contentsOf: [status, ev.pitch, ev.vel])
        }

        body.appendEndOfTrack()
        return chunk("MTrk", body)
    }

    private static func chunk(_ tag: String, _ body: Data) -> Data {
        var out = Data()
        out.append(contentsOf: Array(tag.utf8))
        out.appendUInt32(UInt32(body.count))
        out.append(body)
        return out
    }
}

// MARK: - Data encoding helpers

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(contentsOf: [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ])
    }

    /// Append a MIDI variable-length quantity.
    mutating func appendVLQ(_ value: UInt32) {
        var buffer = [UInt8(value & 0x7F)]
        var v = value >> 7
        while v > 0 {
            buffer.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        append(contentsOf: buffer.reversed())
    }

    mutating func appendEndOfTrack() {
        appendVLQ(0)
        append(contentsOf: [0xFF, 0x2F, 0x00])
    }
}
