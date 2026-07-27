//
//  Chord.swift
//  ImprovisorEngine
//
//  A chord occurrence — a ChordSymbol sounding for a slot duration — and
//  ChordPart, the slot-positioned sequence of them. Ports the data-carrying
//  behavior of imp/data/Chord and imp/data/ChordPart that the engine needs.
//

import Foundation

/// A chord sounding for a given number of slots.
public struct Chord: Equatable {
    public var symbol: ChordSymbol
    public var duration: Int

    public init(symbol: ChordSymbol, duration: Int) {
        self.symbol = symbol
        self.duration = duration
    }
}

/// An ordered, slot-positioned sequence of chords.
public struct ChordPart: Equatable {
    /// One chord placed at an absolute start slot.
    public struct Entry: Equatable {
        public var symbol: ChordSymbol
        public var start: Int
        public var duration: Int
        public var end: Int { start + duration }
    }

    public private(set) var entries: [Entry]
    /// Total length in slots.
    public private(set) var size: Int

    public init(entries: [Entry] = [], size: Int = 0) {
        self.entries = entries
        self.size = max(size, entries.last.map(\.end) ?? 0)
    }

    /// Append a chord that starts immediately after the current content.
    public mutating func append(_ symbol: ChordSymbol, duration: Int) {
        let start = size
        entries.append(Entry(symbol: symbol, start: start, duration: duration))
        size = start + duration
    }

    /// The chord sounding at an absolute slot, or `nil` if out of range.
    public func chord(at slot: Int) -> ChordSymbol? {
        for entry in entries where slot >= entry.start && slot < entry.end {
            return entry.symbol
        }
        return nil
    }

    /// The number of chords.
    public var count: Int { entries.count }
}
