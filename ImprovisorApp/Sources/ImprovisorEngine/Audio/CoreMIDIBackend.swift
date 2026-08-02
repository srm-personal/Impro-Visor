//
//  CoreMIDIBackend.swift
//  ImprovisorEngine
//
//  InstrumentBackend that sends to an external CoreMIDI destination — a hardware
//  synth/piano, or another app acting as the sound source (e.g. GarageBand or
//  Logic receiving on the IAC bus). This is the zero-rework path to "use
//  GarageBand's sounds": route MIDI out, let that app play it.
//
//  (LiveMIDIPlayer remains the blocking CLI player; this is the non-blocking,
//  backend-shaped sibling used by SequencePlayer / the app. The small amount of
//  shared CoreMIDI plumbing is intentionally duplicated to keep the CLI stable.)
//

#if canImport(CoreMIDI)
import Foundation
import CoreMIDI

public final class CoreMIDIBackend: InstrumentBackend {
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private let destination: MIDIEndpointRef
    public let destinationName: String

    /// Target the destination whose name contains `hint` (case-insensitive), or
    /// the first available if `hint` is nil. Returns nil if none match.
    public init?(destinationHint hint: String? = nil) {
        let all = LiveMIDIPlayer.destinations()
        guard !all.isEmpty else { return nil }
        let chosen: LiveMIDIPlayer.Destination
        if let hint, !hint.isEmpty {
            guard let match = all.first(where: { $0.name.lowercased().contains(hint.lowercased()) })
            else { return nil }
            chosen = match
        } else {
            chosen = all[0]
        }
        destination = MIDIGetDestination(chosen.index)
        destinationName = chosen.name
        MIDIClientCreate("ImprovisorEngine" as CFString, nil, nil, &client)
        MIDIOutputPortCreate(client, "Out" as CFString, &port)
    }

    public func start() throws {}
    public func stop() { allNotesOff() }

    public func programChange(_ program: UInt8, channel: UInt8) {
        send([0xC0 | (channel & 0x0F), program & 0x7F])
    }
    public func noteOn(_ pitch: UInt8, velocity: UInt8, channel: UInt8) {
        send([0x90 | (channel & 0x0F), pitch & 0x7F, velocity & 0x7F])
    }
    public func noteOff(_ pitch: UInt8, channel: UInt8) {
        send([0x80 | (channel & 0x0F), pitch & 0x7F, 0])
    }
    public func allNotesOff() {
        for channel in 0..<16 {
            send([0xB0 | UInt8(channel), 123, 0])
            send([0xB0 | UInt8(channel), 120, 0])
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
