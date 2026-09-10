//
//  MIDIInputSource.swift
//  ImprovisorEngine
//
//  Receives notes from every connected MIDI source (a keyboard, or a DAW over
//  the IAC bus) for step entry and chord entry. The packet parser is a pure
//  function so it can be tested without hardware.
//

import Foundation
#if canImport(CoreMIDI)
import CoreMIDI
#endif

public enum MIDIMessage: Equatable, Sendable {
    case noteOn(pitch: UInt8, velocity: UInt8, channel: UInt8)
    case noteOff(pitch: UInt8, channel: UInt8)
    case other
}

public final class MIDIInputSource: @unchecked Sendable {
    public var onNoteOn: (@Sendable (UInt8, UInt8) -> Void)?
    public var onNoteOff: (@Sendable (UInt8) -> Void)?

    #if canImport(CoreMIDI)
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    #endif
    private let lock = NSLock()
    private var running = false

    public init() {}

    /// Whether any MIDI source is present.
    public static var sourceCount: Int {
        #if canImport(CoreMIDI)
        return MIDIGetNumberOfSources()
        #else
        return 0
        #endif
    }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        running = true
        #if canImport(CoreMIDI)
        MIDIClientCreateWithBlock("LeadsheetStudio.Input" as CFString, &client) { [weak self] _ in
            self?.reconnectSources()
        }
        MIDIInputPortCreateWithProtocol(client, "In" as CFString, ._1_0, &port) { [weak self] list, _ in
            guard let self else { return }
            for message in MIDIInputSource.parse(list.pointee) { self.dispatch(message) }
        }
        reconnectSources()
        #endif
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        running = false
        #if canImport(CoreMIDI)
        MIDIPortDispose(port)
        MIDIClientDispose(client)
        port = MIDIPortRef()
        client = MIDIClientRef()
        #endif
    }

    /// Feed raw MIDI 1.0 bytes (tests, or a virtual source).
    public func deliver(bytes: [UInt8]) {
        for message in MIDIInputSource.parse(bytes: bytes) { dispatch(message) }
    }

    private func dispatch(_ message: MIDIMessage) {
        switch message {
        case let .noteOn(pitch, velocity, _): onNoteOn?(pitch, velocity)
        case let .noteOff(pitch, _): onNoteOff?(pitch)
        case .other: break
        }
    }

    #if canImport(CoreMIDI)
    private func reconnectSources() {
        for i in 0..<MIDIGetNumberOfSources() {
            MIDIPortConnectSource(port, MIDIGetSource(i), nil)
        }
    }

    /// Parse a MIDI 1.0 event list into messages.
    static func parse(_ list: MIDIEventList) -> [MIDIMessage] {
        var out: [MIDIMessage] = []
        var copy = list
        let count = Int(copy.numPackets)
        withUnsafeMutablePointer(to: &copy.packet) { first in
            var packet = UnsafePointer(first)
            for _ in 0..<count {
                let wordCount = Int(packet.pointee.wordCount)
                let words: [UInt32] = withUnsafeBytes(of: packet.pointee.words) { raw in
                    Array(raw.bindMemory(to: UInt32.self).prefix(wordCount))
                }
                out += parse(words: words)
                packet = UnsafePointer(MIDIEventPacketNext(packet))
            }
        }
        return out
    }
    #endif

    // MARK: Pure parsers

    /// Parse MIDI 1.0 Universal MIDI Packet words (message type 2).
    public static func parse(words: [UInt32]) -> [MIDIMessage] {
        words.compactMap { word in
            let type = (word >> 28) & 0xF
            guard type == 2 else { return nil }
            let status = UInt8((word >> 16) & 0xFF)
            let data1 = UInt8((word >> 8) & 0x7F)
            let data2 = UInt8(word & 0x7F)
            return message(status: status, data1: data1, data2: data2)
        }
    }

    /// Parse a byte stream of MIDI 1.0 channel messages (running status not supported).
    public static func parse(bytes: [UInt8]) -> [MIDIMessage] {
        var out: [MIDIMessage] = []
        var i = 0
        while i < bytes.count {
            let status = bytes[i]
            guard status & 0x80 != 0 else { i += 1; continue }
            let kind = status & 0xF0
            let length = (kind == 0xC0 || kind == 0xD0) ? 2 : 3
            guard i + length <= bytes.count else { break }
            let d1 = bytes[i + 1], d2 = length == 3 ? bytes[i + 2] : 0
            if let m = message(status: status, data1: d1, data2: d2) { out.append(m) }
            i += length
        }
        return out
    }

    static func message(status: UInt8, data1: UInt8, data2: UInt8) -> MIDIMessage? {
        let channel = status & 0x0F
        switch status & 0xF0 {
        case 0x90: return data2 == 0 ? .noteOff(pitch: data1, channel: channel) : .noteOn(pitch: data1, velocity: data2, channel: channel)
        case 0x80: return .noteOff(pitch: data1, channel: channel)
        case 0xA0...0xE0: return .other
        default: return nil
        }
    }
}
