//
//  LayoutModel.swift
//  LeadsheetKit
//
//  The output of StaveLayout: systems, measure boxes and resolution-independent
//  glyphs. The renderer draws glyphs; the editor hit-tests measure boxes.
//

import Foundation
import CoreGraphics
import ImprovisorEngine

public enum BarlineKind: Equatable, Sendable { case single, final }

public enum AccidentalGlyph: Int, Equatable, Sendable { case flat = -1, natural = 0, sharp = 1 }

public enum Glyph: Equatable, Sendable {
    case staffLines(x0: CGFloat, x1: CGFloat, staffTop: CGFloat)
    case clef(Clef, x: CGFloat, staffTop: CGFloat)
    case keyAccidental(AccidentalGlyph, x: CGFloat, y: CGFloat)
    case timeSignature(numerator: Int, denominator: Int, x: CGFloat, staffTop: CGFloat)
    case barline(x: CGFloat, top: CGFloat, bottom: CGFloat, kind: BarlineKind)
    case noteHead(x: CGFloat, y: CGFloat, filled: Bool, piece: Int)
    case ledger(x: CGFloat, y: CGFloat)
    case accidental(AccidentalGlyph, x: CGFloat, y: CGFloat)
    case stem(x: CGFloat, y0: CGFloat, y1: CGFloat)
    case beam(from: CGPoint, to: CGPoint)
    case flag(x: CGFloat, y: CGFloat, up: Bool, count: Int)
    case dot(x: CGFloat, y: CGFloat)
    case rest(NoteValue, x: CGFloat, staffTop: CGFloat, piece: Int)
    case tie(from: CGPoint, to: CGPoint, below: Bool)
    case tuplet(number: Int, x0: CGFloat, x1: CGFloat, y: CGFloat)
    case chordSymbol(String, x: CGFloat, y: CGFloat)
    case sectionMarker(String, x: CGFloat, y: CGFloat)
    case measureNumber(Int, x: CGFloat, y: CGFloat)
}

public struct MeasureBox: Equatable, Sendable {
    public var index: Int
    public var system: Int
    /// Full box (including the bar line area).
    public var frame: CGRect
    /// Horizontal span in which slots are placed (inset from the bar lines).
    public var slotX0: CGFloat
    public var slotX1: CGFloat
    public var startSlot: Int
    public var endSlot: Int

    public var slotWidth: CGFloat { slotX1 - slotX0 }
    public var slots: Int { endSlot - startSlot }

    public func x(forSlot slot: Int) -> CGFloat {
        guard slots > 0 else { return slotX0 }
        return slotX0 + CGFloat(slot - startSlot) / CGFloat(slots) * slotWidth
    }

    public func slot(atX x: CGFloat) -> Int {
        guard slotWidth > 0 else { return startSlot }
        let f = max(0, min(1, (x - slotX0) / slotWidth))
        return startSlot + min(slots - 1, Int((f * CGFloat(slots)).rounded()))
    }
}

public struct SystemLayout: Equatable, Sendable {
    public var index: Int
    public var frame: CGRect
    /// Top line of the treble (or only) staff.
    public var staffTop: CGFloat
    /// Top line of the bass staff when this is a grand staff.
    public var bassStaffTop: CGFloat?
    public var measureRange: Range<Int>
    /// Baseline for chord symbols.
    public var chordY: CGFloat

    /// The clef whose staff contains `y` (grand staff only splits).
    public func clef(atY y: CGFloat, geometry: StaffGeometry) -> Clef {
        guard let bassTop = bassStaffTop else { return .treble }
        let split = (staffTop + geometry.staffHeight + bassTop) / 2
        return y < split ? .treble : .bass
    }

    public func staffTop(for clef: Clef) -> CGFloat {
        clef == .bass ? (bassStaffTop ?? staffTop) : staffTop
    }
}

public struct LayoutDocument: Equatable, Sendable {
    public var geometry: StaffGeometry
    public var width: CGFloat
    public var height: CGFloat
    public var slotsPerMeasure: Int
    public var systems: [SystemLayout]
    public var measures: [MeasureBox]
    public var pieces: [NotePiece]
    public var glyphs: [Glyph]
    /// Whether the layout uses a grand staff.
    public var isGrand: Bool
    public var breakpoint: Int

    public init(geometry: StaffGeometry, width: CGFloat, height: CGFloat, slotsPerMeasure: Int,
                systems: [SystemLayout], measures: [MeasureBox], pieces: [NotePiece], glyphs: [Glyph],
                isGrand: Bool, breakpoint: Int) {
        self.geometry = geometry
        self.width = width
        self.height = height
        self.slotsPerMeasure = slotsPerMeasure
        self.systems = systems
        self.measures = measures
        self.pieces = pieces
        self.glyphs = glyphs
        self.isGrand = isGrand
        self.breakpoint = breakpoint
    }

    // MARK: Queries

    public func measure(containingSlot slot: Int) -> MeasureBox? {
        measures.first { slot >= $0.startSlot && slot < $0.endSlot } ?? (slot >= (measures.last?.endSlot ?? 0) ? measures.last : nil)
    }

    public func measure(at point: CGPoint) -> MeasureBox? {
        guard let system = systems.first(where: { $0.frame.minY <= point.y && point.y < $0.frame.maxY }) else { return nil }
        let inSystem = measures[system.measureRange]
        if let hit = inSystem.first(where: { $0.frame.minX <= point.x && point.x < $0.frame.maxX }) { return hit }
        if point.x < (inSystem.first?.frame.minX ?? 0) { return inSystem.first }
        return inSystem.last
    }

    /// The absolute slot under `point`, or nil outside all systems.
    public func slot(at point: CGPoint) -> Int? {
        measure(at: point)?.slot(atX: point.x)
    }

    public func x(forSlot slot: Int) -> CGFloat? {
        measure(containingSlot: slot)?.x(forSlot: slot)
    }

    /// The vertical line for a playhead at `slot`: x plus the system's y extent.
    public func playheadLine(slot: Int) -> (x: CGFloat, top: CGFloat, bottom: CGFloat)? {
        guard let m = measure(containingSlot: slot) else { return nil }
        let s = systems[m.system]
        return (m.x(forSlot: slot), s.frame.minY, s.frame.maxY)
    }

    /// Rectangles covering a slot range (one per system it touches).
    public func rects(forSlots range: Range<Int>) -> [CGRect] {
        var out: [CGRect] = []
        for system in systems {
            let boxes = measures[system.measureRange].filter { $0.endSlot > range.lowerBound && $0.startSlot < range.upperBound }
            guard let first = boxes.first, let last = boxes.last else { continue }
            let x0 = first.x(forSlot: max(range.lowerBound, first.startSlot))
            let x1 = range.upperBound >= last.endSlot ? last.frame.maxX : last.x(forSlot: range.upperBound)
            out.append(CGRect(x: x0, y: system.frame.minY, width: max(2, x1 - x0), height: system.frame.height))
        }
        return out
    }

    /// The diatonic index at `point`, using the staff under the point.
    public func diatonic(at point: CGPoint) -> (diatonic: Int, clef: Clef)? {
        guard let system = systems.first(where: { $0.frame.minY <= point.y && point.y < $0.frame.maxY }) else { return nil }
        let clef = system.clef(atY: point.y, geometry: geometry)
        return (geometry.diatonic(atY: point.y, clef: clef, staffTop: system.staffTop(for: clef)), clef)
    }

    /// The point where a note at `slot`/`diatonic` sits.
    public func point(forSlot slot: Int, diatonic: Int, clef: Clef) -> CGPoint? {
        guard let m = measure(containingSlot: slot) else { return nil }
        let s = systems[m.system]
        return CGPoint(x: m.x(forSlot: slot), y: geometry.y(forDiatonic: diatonic, clef: clef, staffTop: s.staffTop(for: clef)))
    }
}
