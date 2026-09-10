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
public struct Chord: Equatable, Sendable {
    public var symbol: ChordSymbol
    public var duration: Int

    public init(symbol: ChordSymbol, duration: Int) {
        self.symbol = symbol
        self.duration = duration
    }
}

/// An ordered, slot-positioned sequence of chords.
public struct ChordPart: Equatable, Sendable {
    /// One chord placed at an absolute start slot.
    public struct Entry: Equatable, Sendable {
        public var symbol: ChordSymbol
        public var start: Int
        public var duration: Int
        public var end: Int { start + duration }
    }

    public private(set) var entries: [Entry]
    /// Total length in slots.
    public private(set) var size: Int
    /// Leadsheet `(part …)` header metadata for this part.
    public var info: PartInfo

    public init(entries: [Entry] = [], size: Int = 0, info: PartInfo = .defaultChords) {
        self.entries = entries
        self.size = max(size, entries.last.map(\.end) ?? 0)
        self.info = info
    }

    /// Lengthen the last chord by `slots` (used to flesh out a partial final bar).
    public mutating func extendLast(by slots: Int) {
        guard slots > 0, let last = entries.indices.last else { return }
        entries[last].duration += slots
        size = entries[last].end
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

    /// The chords sounding within `range` (absolute slots), clipped to it and
    /// re-based so the slice starts at slot 0. Chords that begin before the
    /// range start at 0 with their remaining duration.
    public func slice(_ range: Range<Int>) -> ChordPart {
        var out = ChordPart(info: info)
        guard !range.isEmpty else { return out }
        for entry in entries {
            let start = max(entry.start, range.lowerBound)
            let end = min(entry.end, range.upperBound)
            if end > start {
                out.entries.append(Entry(symbol: entry.symbol, start: start - range.lowerBound,
                                         duration: end - start))
            }
        }
        out.size = out.entries.last?.end ?? 0
        return out
    }
}
