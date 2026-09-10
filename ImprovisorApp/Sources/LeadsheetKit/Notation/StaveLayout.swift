//
//  StaveLayout.swift
//  LeadsheetKit
//
//  Lays a Score out as systems of equal-width measures (like the Java Stave's
//  construction-line grid): clef, key and time signature at the left of each
//  system, chord symbols above each measure, section markers, and the melody
//  part's notes/rests with accidentals, stems, beams, flags, dots, ties and
//  tuplet brackets. Pure geometry — no drawing here.
//

import Foundation
import CoreGraphics
import ImprovisorEngine

public struct StaveOptions: Equatable, Sendable {
    public var width: CGFloat = 800
    /// Bars per system; nil = use the score's `(layout n)` or 4.
    public var measuresPerLine: Int? = nil
    /// nil = use the melody part's stave type.
    public var staveType: StaveType? = nil
    public var showChordSymbols = true
    public var showSectionMarkers = true
    public var showMeasureNumbers = true
    public var geometry = StaffGeometry()
    public var leftMargin: CGFloat = 12
    public var rightMargin: CGFloat = 12
    public var topMargin: CGFloat = 8

    public init() {}
}

public enum StaveLayout {

    // MARK: Constants (in units of space height)

    static let clefWidthSpaces: CGFloat = 4.0
    static let keyAccidentalSpaces: CGFloat = 1.1
    static let timeSignatureSpaces: CGFloat = 3.0
    static let stemSpaces: CGFloat = 3.5
    static let headWidthSpaces: CGFloat = 1.3
    static let padAboveSpaces: CGFloat = 3.5     // room for notes above the staff
    static let padBelowSpaces: CGFloat = 3.0
    static let chordRowSpaces: CGFloat = 2.6
    static let markerRowSpaces: CGFloat = 2.0
    static let grandGapSpaces: CGFloat = 4.0
    static let systemGapSpaces: CGFloat = 1.5
    static let measureInsetSpaces: CGFloat = 1.6

    public static func layout(score: Score, part partIndex: Int = 0, options: StaveOptions = StaveOptions()) -> LayoutDocument {
        let g = options.geometry
        let sp = g.spaceHeight
        let meter = score.meter
        let spm = max(1, meter.slotsPerMeasure)
        let melody = partIndex < score.melodyParts.count ? score.melodyParts[partIndex] : nil
        let staveType = options.staveType ?? melody?.info.stave ?? .treble
        let isGrand = staveType == .grand
        let baseClef: Clef = staveType == .bass ? .bass : .treble

        let totalSlots = max(score.chordPart.size, melody?.size ?? 0)
        let measureCount = max(1, Int((Double(totalSlots) / Double(spm)).rounded(.up)))
        let perLine = max(1, options.measuresPerLine ?? (score.layout.first.flatMap { $0 > 0 ? $0 : nil } ?? 4))

        let keySig = PitchSpelling.keySignature(score.key, clef: .treble)
        let indent = options.leftMargin + sp * (clefWidthSpaces + keyAccidentalSpaces * CGFloat(keySig.count) + timeSignatureSpaces)
        let measureWidth = max(sp * 6, (options.width - indent - options.rightMargin) / CGFloat(perLine))
        let inset = sp * measureInsetSpaces

        let hasMarkers = options.showSectionMarkers && !score.sections.records.isEmpty
        let markerRow = hasMarkers ? sp * markerRowSpaces : 0
        let chordRow = options.showChordSymbols ? sp * chordRowSpaces : 0
        let staffBlock = sp * padAboveSpaces + g.staffHeight + sp * padBelowSpaces
        let grandExtra = isGrand ? sp * grandGapSpaces + g.staffHeight + sp * padBelowSpaces : 0
        let systemHeight = markerRow + chordRow + staffBlock + grandExtra + sp * systemGapSpaces

        var systems: [SystemLayout] = []
        var measures: [MeasureBox] = []
        var glyphs: [Glyph] = []
        let pieces = melody.map { DurationSplitter.split($0, slotsPerMeasure: spm) } ?? []

        // Chord lookup by measure.
        var chordsByMeasure: [Int: [ChordPart.Entry]] = [:]
        for entry in score.chordPart.entries { chordsByMeasure[entry.start / spm, default: []].append(entry) }
        var markersByMeasure: [Int: SectionRecord] = [:]
        for r in score.sections.records { markersByMeasure[r.measure] = r }

        let systemCount = Int((Double(measureCount) / Double(perLine)).rounded(.up))
        var y = options.topMargin

        for s in 0..<systemCount {
            let firstMeasure = s * perLine
            let lastMeasure = min(measureCount, firstMeasure + perLine)
            let markerY = y + markerRow * 0.8
            let chordY = y + markerRow + chordRow * 0.75
            let staffTop = y + markerRow + chordRow + sp * padAboveSpaces
            let bassTop: CGFloat? = isGrand ? staffTop + g.staffHeight + sp * grandGapSpaces : nil
            let staffBottom = (bassTop ?? staffTop) + g.staffHeight
            let x0 = options.leftMargin
            let x1 = indent + measureWidth * CGFloat(lastMeasure - firstMeasure)

            let system = SystemLayout(index: s, frame: CGRect(x: 0, y: y, width: options.width, height: systemHeight),
                                      staffTop: staffTop, bassStaffTop: bassTop,
                                      measureRange: firstMeasure..<lastMeasure, chordY: chordY)
            systems.append(system)

            // Staff lines, clefs, key signatures, time signature (first system).
            for (clef, top) in staves(baseClef: baseClef, staffTop: staffTop, bassTop: bassTop) {
                glyphs.append(.staffLines(x0: x0, x1: x1, staffTop: top))
                glyphs.append(.clef(clef, x: x0 + sp * 0.5, staffTop: top))
                var kx = x0 + sp * clefWidthSpaces
                for (d, acc) in PitchSpelling.keySignature(score.key, clef: clef) {
                    glyphs.append(.keyAccidental(acc > 0 ? .sharp : .flat, x: kx, y: g.y(forDiatonic: d, clef: clef, staffTop: top)))
                    kx += sp * keyAccidentalSpaces
                }
                if s == 0 {
                    glyphs.append(.timeSignature(numerator: meter.numerator, denominator: meter.denominator,
                                                 x: kx + sp * 0.4, staffTop: top))
                }
            }
            // Opening bar line.
            glyphs.append(.barline(x: indent, top: staffTop, bottom: staffBottom, kind: .single))

            for m in firstMeasure..<lastMeasure {
                let mx = indent + measureWidth * CGFloat(m - firstMeasure)
                let box = MeasureBox(index: m, system: s,
                                     frame: CGRect(x: mx, y: y, width: measureWidth, height: systemHeight),
                                     slotX0: mx + inset, slotX1: mx + measureWidth - inset * 0.6,
                                     startSlot: m * spm, endSlot: (m + 1) * spm)
                measures.append(box)
                let isLast = m == measureCount - 1
                glyphs.append(.barline(x: mx + measureWidth, top: staffTop, bottom: staffBottom, kind: isLast ? .final : .single))

                if options.showMeasureNumbers, m % perLine == 0 {
                    glyphs.append(.measureNumber(m + 1, x: mx + 2, y: staffTop - sp * 2.6))
                }
                if hasMarkers, let marker = markersByMeasure[m] {
                    let label = marker.usesPreviousStyle ? (marker.isPhrase ? "phrase" : "section") : marker.styleName
                    glyphs.append(.sectionMarker(label, x: mx + 2, y: markerY))
                }
                if options.showChordSymbols {
                    for entry in chordsByMeasure[m] ?? [] where !entry.symbol.isNoChord {
                        glyphs.append(.chordSymbol(entry.symbol.name, x: box.x(forSlot: entry.start), y: chordY))
                    }
                }
            }
            y += systemHeight
        }

        // Melody pieces, measure by measure.
        if !pieces.isEmpty {
            var pieceIndex = 0
            let keyAcc = PitchSpelling.keyAccidentals(score.key)
            var lastPoint: [Int: (CGPoint, Bool)] = [:]   // piece → (head point, stem up) for ties
            for box in measures {
                var indexes: [Int] = []
                while pieceIndex < pieces.count, pieces[pieceIndex].start < box.endSlot {
                    if pieces[pieceIndex].start >= box.startSlot { indexes.append(pieceIndex) }
                    pieceIndex += 1
                }
                guard !indexes.isEmpty else { continue }
                let system = systems[box.system]
                var accState = keyAcc
                var heads: [Int: (x: CGFloat, y: CGFloat, clef: Clef, d: Int)] = [:]

                for i in indexes {
                    let p = pieces[i]
                    let x = box.x(forSlot: p.start)
                    if p.isRest {
                        glyphs.append(.rest(p.value, x: x, staffTop: system.staffTop(for: baseClef), piece: i))
                        continue
                    }
                    let note = Note(pitch: p.pitch, duration: p.duration, spelling: p.spelling)
                    let spelled = PitchSpelling.spell(note, key: score.key)
                    let clef: Clef = isGrand ? (p.pitch < score.breakpoint ? .bass : .treble) : baseClef
                    let top = system.staffTop(for: clef)
                    let d = spelled.diatonic
                    let ny = g.y(forDiatonic: d, clef: clef, staffTop: top)
                    heads[i] = (x, ny, clef, d)

                    for l in g.ledgerDiatonics(forDiatonic: d, clef: clef) {
                        glyphs.append(.ledger(x: x, y: g.y(forDiatonic: l, clef: clef, staffTop: top)))
                    }
                    if accState[spelled.letter] != spelled.accidental {
                        accState[spelled.letter] = spelled.accidental
                        glyphs.append(.accidental(AccidentalGlyph(rawValue: spelled.accidental) ?? .natural, x: x - sp * 1.1, y: ny))
                    }
                    glyphs.append(.noteHead(x: x, y: ny, filled: p.value.isFilled, piece: i))
                    for dot in 0..<p.value.dots {
                        // Dots sit in a space: nudge up when the head is on a line.
                        let onLine = (d - clef.bottomLineDiatonic) % 2 == 0
                        glyphs.append(.dot(x: x + sp * (1.2 + CGFloat(dot) * 0.6), y: onLine ? ny - g.stepHeight : ny))
                    }
                }

                // Stems, beams, flags.
                let beams = BeamGrouper.beams(pieces: pieces, indexes: indexes, slotsPerBeat: meter.slotsPerBeat)
                var beamed = Set<Int>()
                for group in beams {
                    let members = group.pieces.compactMap { i in heads[i].map { (i, $0) } }
                    guard members.count >= 2 else { continue }
                    beamed.formUnion(members.map(\.0))
                    let clef = members[0].1.clef
                    let avg = Double(members.map(\.1.d).reduce(0, +)) / Double(members.count)
                    let up = avg < Double(clef.middleLineDiatonic)
                    let stemLen = sp * stemSpaces
                    let beamY = up ? (members.map(\.1.y).min()! - stemLen) : (members.map(\.1.y).max()! + stemLen)
                    let headHalf = sp * headWidthSpaces / 2
                    for (i, h) in members {
                        let sx = up ? h.x + headHalf : h.x - headHalf
                        glyphs.append(.stem(x: sx, y0: h.y, y1: beamY))
                        lastPoint[i] = (CGPoint(x: h.x, y: h.y), up)
                    }
                    let first = members.first!.1, last = members.last!.1
                    let fx = up ? first.x + headHalf : first.x - headHalf
                    let lx = up ? last.x + headHalf : last.x - headHalf
                    glyphs.append(.beam(from: CGPoint(x: fx, y: beamY), to: CGPoint(x: lx, y: beamY)))
                    // Secondary beams between neighbours that both need them.
                    let dir: CGFloat = up ? 1 : -1
                    for level in 2...3 {
                        let offset = dir * sp * 0.75 * CGFloat(level - 1)
                        for k in 0..<(members.count - 1) {
                            let a = pieces[members[k].0], b = pieces[members[k + 1].0]
                            let ax = up ? members[k].1.x + headHalf : members[k].1.x - headHalf
                            let bx = up ? members[k + 1].1.x + headHalf : members[k + 1].1.x - headHalf
                            if a.value.flags >= level && b.value.flags >= level {
                                glyphs.append(.beam(from: CGPoint(x: ax, y: beamY + offset), to: CGPoint(x: bx, y: beamY + offset)))
                            } else if a.value.flags >= level {
                                glyphs.append(.beam(from: CGPoint(x: ax, y: beamY + offset), to: CGPoint(x: ax + (bx - ax) * 0.4, y: beamY + offset)))
                            } else if b.value.flags >= level && (k == members.count - 2 || pieces[members[k + 2].0].value.flags < level) {
                                glyphs.append(.beam(from: CGPoint(x: bx - (bx - ax) * 0.4, y: beamY + offset), to: CGPoint(x: bx, y: beamY + offset)))
                            }
                        }
                    }
                }
                for i in indexes where heads[i] != nil && !beamed.contains(i) {
                    let p = pieces[i], h = heads[i]!
                    guard p.value.hasStem else { lastPoint[i] = (CGPoint(x: h.x, y: h.y), true); continue }
                    let up = h.d < h.clef.middleLineDiatonic
                    let headHalf = sp * headWidthSpaces / 2
                    let sx = up ? h.x + headHalf : h.x - headHalf
                    let stemEnd = up ? h.y - sp * stemSpaces : h.y + sp * stemSpaces
                    glyphs.append(.stem(x: sx, y0: h.y, y1: stemEnd))
                    if p.value.flags > 0 { glyphs.append(.flag(x: sx, y: stemEnd, up: up, count: p.value.flags)) }
                    lastPoint[i] = (CGPoint(x: h.x, y: h.y), up)
                }

                // Tuplet brackets.
                for group in BeamGrouper.tuplets(pieces: pieces, indexes: indexes, slotsPerBeat: meter.slotsPerBeat) {
                    let xs = group.pieces.map { box.x(forSlot: pieces[$0].start) }
                    let ys = group.pieces.compactMap { heads[$0]?.y }
                    let top = (ys.min() ?? system.staffTop) - sp * (stemSpaces + 1.2)
                    glyphs.append(.tuplet(number: 3, x0: xs.min()!, x1: xs.max()! + sp * headWidthSpaces, y: min(top, system.staffTop - sp * 1.2)))
                }
            }

            // Ties between consecutive pieces of one event.
            for i in pieces.indices where pieces[i].tiedToNext && i + 1 < pieces.count {
                guard let (from, up) = lastPoint[i], let (to, _) = lastPoint[i + 1] else { continue }
                let headHalf = sp * headWidthSpaces / 2
                if abs(to.y - from.y) < 0.5 && to.x > from.x {
                    glyphs.append(.tie(from: CGPoint(x: from.x + headHalf, y: from.y), to: CGPoint(x: to.x - headHalf, y: to.y), below: up))
                } else {
                    // Across a system break: a short tie off the first note.
                    glyphs.append(.tie(from: CGPoint(x: from.x + headHalf, y: from.y), to: CGPoint(x: from.x + sp * 3, y: from.y), below: up))
                }
            }
        }

        return LayoutDocument(geometry: g, width: options.width, height: y + options.topMargin,
                              slotsPerMeasure: spm, systems: systems, measures: measures,
                              pieces: pieces, glyphs: glyphs, isGrand: isGrand, breakpoint: score.breakpoint)
    }

    private static func staves(baseClef: Clef, staffTop: CGFloat, bassTop: CGFloat?) -> [(Clef, CGFloat)] {
        if let bassTop { return [(.treble, staffTop), (.bass, bassTop)] }
        return [(baseClef, staffTop)]
    }
}
