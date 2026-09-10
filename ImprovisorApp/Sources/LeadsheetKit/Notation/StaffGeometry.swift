//
//  StaffGeometry.swift
//  LeadsheetKit
//
//  Vertical geometry of a five-line staff. Pitches are placed by *diatonic
//  index* (C0 = 0, one step per letter name: … B3 = 27, C4 = 28, D4 = 29 …),
//  which maps to a line or space; the staff's bottom line is E4 on a treble
//  staff and G2 on a bass staff. Half a space per diatonic step, as in the
//  Java Stave (staveSpaceHeight = 8).
//

import Foundation
import CoreGraphics

public enum Clef: String, Equatable, Sendable, CaseIterable {
    case treble, bass

    /// Diatonic index of the staff's bottom line (E4 / G2).
    public var bottomLineDiatonic: Int { self == .treble ? 30 : 18 }
    /// Diatonic index of the middle line (B4 / D3) — the stem-direction pivot.
    public var middleLineDiatonic: Int { bottomLineDiatonic + 4 }
}

public struct StaffGeometry: Equatable, Sendable {
    /// Distance between adjacent staff lines.
    public var spaceHeight: CGFloat
    public var lineWidth: CGFloat

    public init(spaceHeight: CGFloat = 8, lineWidth: CGFloat = 1) {
        self.spaceHeight = spaceHeight
        self.lineWidth = lineWidth
    }

    /// Height from the top line to the bottom line.
    public var staffHeight: CGFloat { spaceHeight * 4 }
    /// Half a space: the vertical distance of one diatonic step.
    public var stepHeight: CGFloat { spaceHeight / 2 }

    /// The y of a diatonic index on a staff whose top line is at `staffTop`.
    public func y(forDiatonic d: Int, clef: Clef, staffTop: CGFloat) -> CGFloat {
        staffTop + staffHeight - CGFloat(d - clef.bottomLineDiatonic) * stepHeight
    }

    /// Inverse of `y(forDiatonic:)`: the nearest diatonic index at `y`.
    public func diatonic(atY y: CGFloat, clef: Clef, staffTop: CGFloat) -> Int {
        let steps = (staffTop + staffHeight - y) / stepHeight
        return clef.bottomLineDiatonic + Int(steps.rounded())
    }

    /// The y of each of the five lines, top to bottom.
    public func lineYs(staffTop: CGFloat) -> [CGFloat] {
        (0..<5).map { staffTop + CGFloat($0) * spaceHeight }
    }

    /// Diatonic indexes of the ledger lines needed for a note at `d` (lines lie
    /// on even offsets from the bottom line, outside the staff).
    public func ledgerDiatonics(forDiatonic d: Int, clef: Clef) -> [Int] {
        let bottom = clef.bottomLineDiatonic
        let top = bottom + 8
        var lines: [Int] = []
        if d < bottom {
            var l = bottom - 2
            while l >= d { lines.append(l); l -= 2 }
        } else if d > top {
            var l = top + 2
            while l <= d { lines.append(l); l += 2 }
        }
        return lines
    }
}

/// Diatonic helpers shared by spelling and layout.
public enum Diatonic {
    /// Letter index 0–6 (C D E F G A B) of a diatonic index.
    public static func letter(_ d: Int) -> Int { ((d % 7) + 7) % 7 }
    /// Octave (scientific, C4 = middle C) of a diatonic index.
    public static func octave(_ d: Int) -> Int { Int((Double(d) / 7).rounded(.down)) }
    public static func index(letter: Int, octave: Int) -> Int { octave * 7 + letter }
    public static let letterNames: [Character] = ["C", "D", "E", "F", "G", "A", "B"]
}
