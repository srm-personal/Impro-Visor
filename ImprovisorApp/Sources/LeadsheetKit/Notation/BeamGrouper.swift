//
//  BeamGrouper.swift
//  LeadsheetKit
//
//  Groups consecutive beamable pieces (eighths and shorter, not rests) that lie
//  within one beat into beams, and consecutive triplet pieces into tuplet
//  brackets. Beaming per beat is what the Java Stave does and reads well for
//  jazz eighth-note lines.
//

import Foundation

public struct BeamGroup: Equatable, Sendable {
    /// Indexes into the layout's piece array, in time order.
    public var pieces: [Int]
}

public enum BeamGrouper {
    /// Beam groups among `indexes` (pieces of one measure, time-ordered).
    public static func beams(pieces all: [NotePiece], indexes: [Int], slotsPerBeat: Int) -> [BeamGroup] {
        var groups: [BeamGroup] = []
        var current: [Int] = []
        var currentBeat = -1
        func flush() {
            if current.count >= 2 { groups.append(BeamGroup(pieces: current)) }
            current = []
        }
        for i in indexes {
            let p = all[i]
            let beamable = !p.isRest && p.value.flags >= 1
            let beat = slotsPerBeat > 0 ? p.start / slotsPerBeat : 0
            if !beamable {
                flush(); currentBeat = -1
                continue
            }
            if beat != currentBeat { flush(); currentBeat = beat }
            current.append(i)
        }
        flush()
        return groups
    }

    /// Runs of consecutive triplet pieces (notes or rests) within a beat.
    public static func tuplets(pieces all: [NotePiece], indexes: [Int], slotsPerBeat: Int) -> [BeamGroup] {
        var groups: [BeamGroup] = []
        var current: [Int] = []
        var currentBeat = -1
        func flush() {
            if current.count >= 2 { groups.append(BeamGroup(pieces: current)) }
            current = []
        }
        for i in indexes {
            let p = all[i]
            let beat = slotsPerBeat > 0 ? p.start / slotsPerBeat : 0
            if p.value.tuplet != 3 { flush(); currentBeat = -1; continue }
            if beat != currentBeat { flush(); currentBeat = beat }
            current.append(i)
        }
        flush()
        return groups
    }
}
