//
//  StaveRenderer.swift
//  LeadsheetKit
//
//  Draws a LayoutDocument into a SwiftUI GraphicsContext. Everything is
//  geometric Paths except text (chord symbols, numerals, clefs and accidentals,
//  which use the system font's music symbols), so rendering is deterministic
//  for snapshot tests and needs no bundled music font.
//

import SwiftUI

public enum StaveRenderer {

    public struct Overlay: Equatable, Sendable {
        public var playheadSlot: Int?
        public var selection: Range<Int>?
        public var cursorSlot: Int?
        public var cursorDiatonic: Int?
        public var cursorClef: Clef
        public init(playheadSlot: Int? = nil, selection: Range<Int>? = nil, cursorSlot: Int? = nil,
                    cursorDiatonic: Int? = nil, cursorClef: Clef = .treble) {
            self.playheadSlot = playheadSlot
            self.selection = selection
            self.cursorSlot = cursorSlot
            self.cursorDiatonic = cursorDiatonic
            self.cursorClef = cursorClef
        }
    }

    /// Draw the notation. `visible` limits work to systems intersecting the rect.
    public static func draw(_ layout: LayoutDocument, in context: inout GraphicsContext,
                            theme: StaveTheme, visible: CGRect? = nil) {
        let g = layout.geometry
        let sp = g.spaceHeight
        let ink = GraphicsContext.Shading.color(theme.ink)

        // Which systems are visible (by y).
        let visibleYs: ClosedRange<CGFloat>? = visible.map { ($0.minY - 200)...($0.maxY + 200) }
        func isVisible(_ y: CGFloat) -> Bool { visibleYs?.contains(y) ?? true }

        for glyph in layout.glyphs {
            switch glyph {
            case let .staffLines(x0, x1, top):
                guard isVisible(top) else { continue }
                var p = Path()
                for y in g.lineYs(staffTop: top) { p.move(to: CGPoint(x: x0, y: y)); p.addLine(to: CGPoint(x: x1, y: y)) }
                context.stroke(p, with: .color(theme.staffLine), lineWidth: g.lineWidth)

            case let .clef(clef, x, top):
                guard isVisible(top) else { continue }
                drawClef(clef, x: x, staffTop: top, geometry: g, theme: theme, in: &context)

            case let .keyAccidental(acc, x, y):
                guard isVisible(y) else { continue }
                drawAccidental(acc, x: x, y: y, sp: sp, theme: theme, in: &context)

            case let .timeSignature(n, d, x, top):
                guard isVisible(top) else { continue }
                let font = Font.system(size: sp * 2.3, weight: .bold, design: .serif)
                context.draw(Text("\(n)").font(font).foregroundColor(theme.ink), at: CGPoint(x: x + sp, y: top + sp), anchor: .center)
                context.draw(Text("\(d)").font(font).foregroundColor(theme.ink), at: CGPoint(x: x + sp, y: top + sp * 3), anchor: .center)

            case let .barline(x, top, bottom, kind):
                guard isVisible(top) else { continue }
                var p = Path()
                p.move(to: CGPoint(x: x, y: top)); p.addLine(to: CGPoint(x: x, y: bottom))
                context.stroke(p, with: .color(theme.staffLine), lineWidth: g.lineWidth)
                if kind == .final {
                    var thick = Path()
                    thick.move(to: CGPoint(x: x - sp * 0.45, y: top)); thick.addLine(to: CGPoint(x: x - sp * 0.45, y: bottom))
                    context.stroke(thick, with: .color(theme.staffLine), lineWidth: sp * 0.35)
                }

            case let .noteHead(x, y, filled, _):
                guard isVisible(y) else { continue }
                let w = sp * StaveLayout.headWidthSpaces, h = sp * 0.95
                var head = Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                head = head.applying(CGAffineTransform(rotationAngle: -0.35))
                head = head.applying(CGAffineTransform(translationX: x, y: y))
                if filled {
                    context.fill(head, with: ink)
                } else {
                    context.stroke(head, with: ink, lineWidth: sp * 0.22)
                }

            case let .ledger(x, y):
                guard isVisible(y) else { continue }
                var p = Path()
                p.move(to: CGPoint(x: x - sp * 1.0, y: y)); p.addLine(to: CGPoint(x: x + sp * 1.0, y: y))
                context.stroke(p, with: .color(theme.staffLine), lineWidth: g.lineWidth)

            case let .accidental(acc, x, y):
                guard isVisible(y) else { continue }
                drawAccidental(acc, x: x, y: y, sp: sp, theme: theme, in: &context)

            case let .stem(x, y0, y1):
                guard isVisible(y0) else { continue }
                var p = Path()
                p.move(to: CGPoint(x: x, y: y0)); p.addLine(to: CGPoint(x: x, y: y1))
                context.stroke(p, with: ink, lineWidth: sp * 0.14)

            case let .beam(from, to):
                guard isVisible(from.y) else { continue }
                var p = Path()
                p.move(to: from); p.addLine(to: to)
                context.stroke(p, with: ink, lineWidth: sp * 0.55)

            case let .flag(x, y, up, count):
                guard isVisible(y) else { continue }
                for i in 0..<count {
                    let dy = CGFloat(i) * sp * 0.8 * (up ? 1 : -1)
                    var p = Path()
                    let start = CGPoint(x: x, y: y + dy)
                    p.move(to: start)
                    let dir: CGFloat = up ? 1 : -1
                    p.addCurve(to: CGPoint(x: x + sp * 1.1, y: y + dy + dir * sp * 2.2),
                               control1: CGPoint(x: x + sp * 0.2, y: y + dy + dir * sp * 0.9),
                               control2: CGPoint(x: x + sp * 1.3, y: y + dy + dir * sp * 1.2))
                    context.stroke(p, with: ink, lineWidth: sp * 0.3)
                }

            case let .dot(x, y):
                guard isVisible(y) else { continue }
                context.fill(Path(ellipseIn: CGRect(x: x - sp * 0.18, y: y - sp * 0.18, width: sp * 0.36, height: sp * 0.36)), with: ink)

            case let .rest(value, x, top, _):
                guard isVisible(top) else { continue }
                drawRest(value, x: x, staffTop: top, sp: sp, ink: ink, in: &context)

            case let .tie(from, to, below):
                guard isVisible(from.y) else { continue }
                var p = Path()
                let dir: CGFloat = below ? 1 : -1
                p.move(to: CGPoint(x: from.x, y: from.y + dir * sp * 0.4))
                p.addQuadCurve(to: CGPoint(x: to.x, y: to.y + dir * sp * 0.4),
                               control: CGPoint(x: (from.x + to.x) / 2, y: from.y + dir * sp * 1.4))
                context.stroke(p, with: ink, lineWidth: sp * 0.16)

            case let .tuplet(number, x0, x1, y):
                guard isVisible(y) else { continue }
                var p = Path()
                p.move(to: CGPoint(x: x0, y: y + sp * 0.5)); p.addLine(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x1, y: y)); p.addLine(to: CGPoint(x: x1, y: y + sp * 0.5))
                context.stroke(p, with: ink, lineWidth: g.lineWidth)
                context.draw(Text("\(number)").font(.system(size: sp * 1.3, weight: .semibold, design: .serif).italic()).foregroundColor(theme.ink),
                             at: CGPoint(x: (x0 + x1) / 2, y: y - sp * 0.9), anchor: .center)

            case let .chordSymbol(text, x, y):
                guard isVisible(y) else { continue }
                context.draw(Text(prettyChord(text)).font(.system(size: sp * 1.7, weight: .semibold)).foregroundColor(theme.chordSymbol),
                             at: CGPoint(x: x - sp * 0.6, y: y), anchor: .leading)

            case let .sectionMarker(text, x, y):
                guard isVisible(y) else { continue }
                let label = Text(text).font(.system(size: sp * 1.15, weight: .medium, design: .rounded)).foregroundColor(theme.sectionMarker)
                context.draw(label, at: CGPoint(x: x + sp * 0.5, y: y), anchor: .leading)

            case let .measureNumber(n, x, y):
                guard isVisible(y) else { continue }
                context.draw(Text("\(n)").font(.system(size: sp * 1.1)).foregroundColor(theme.measureNumber),
                             at: CGPoint(x: x, y: y), anchor: .leading)
            }
        }
    }

    /// Draw playhead / selection / cursor on top of the notation.
    public static func drawOverlay(_ overlay: Overlay, layout: LayoutDocument, in context: inout GraphicsContext, theme: StaveTheme) {
        let sp = layout.geometry.spaceHeight
        if let selection = overlay.selection {
            for rect in layout.rects(forSlots: selection) {
                context.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: sp * 0.5), cornerRadius: 3), with: .color(theme.selection))
            }
        }
        if let cursor = overlay.cursorSlot, let line = layout.playheadLine(slot: cursor) {
            var p = Path()
            p.move(to: CGPoint(x: line.x, y: line.top + sp)); p.addLine(to: CGPoint(x: line.x, y: line.bottom - sp))
            context.stroke(p, with: .color(theme.cursor.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let d = overlay.cursorDiatonic, let point = layout.point(forSlot: cursor, diatonic: d, clef: overlay.cursorClef) {
                let w = sp * StaveLayout.headWidthSpaces
                context.stroke(Path(ellipseIn: CGRect(x: point.x - w / 2, y: point.y - sp * 0.5, width: w, height: sp)),
                               with: .color(theme.cursor), lineWidth: 1.2)
            }
        }
        if let slot = overlay.playheadSlot, let line = layout.playheadLine(slot: slot) {
            var p = Path()
            p.move(to: CGPoint(x: line.x, y: line.top)); p.addLine(to: CGPoint(x: line.x, y: line.bottom))
            context.stroke(p, with: .color(theme.playhead), lineWidth: 2)
        }
    }

    // MARK: Pieces

    static func prettyChord(_ name: String) -> String {
        name.replacingOccurrences(of: "b", with: "♭").replacingOccurrences(of: "#", with: "♯")
            .replacingOccurrences(of: "♭♭", with: "♭♭")
    }

    private static func drawAccidental(_ acc: AccidentalGlyph, x: CGFloat, y: CGFloat, sp: CGFloat,
                                       theme: StaveTheme, in context: inout GraphicsContext) {
        let symbol: String
        switch acc {
        case .sharp: symbol = "♯"
        case .flat: symbol = "♭"
        case .natural: symbol = "♮"
        }
        let offset: CGFloat = acc == .flat ? -sp * 0.35 : 0
        context.draw(Text(symbol).font(.system(size: sp * 2.4)).foregroundColor(theme.ink),
                     at: CGPoint(x: x, y: y + offset), anchor: .center)
    }

    private static func drawClef(_ clef: Clef, x: CGFloat, staffTop: CGFloat, geometry g: StaffGeometry,
                                 theme: StaveTheme, in context: inout GraphicsContext) {
        let sp = g.spaceHeight
        switch clef {
        case .treble:
            // 𝄞 centred on the G line (second from bottom).
            let gLine = staffTop + sp * 3
            context.draw(Text("𝄞").font(.system(size: sp * 4.6)).foregroundColor(theme.ink),
                         at: CGPoint(x: x + sp * 1.5, y: gLine - sp * 0.15), anchor: .center)
        case .bass:
            let fLine = staffTop + sp
            context.draw(Text("𝄢").font(.system(size: sp * 3.6)).foregroundColor(theme.ink),
                         at: CGPoint(x: x + sp * 1.5, y: fLine + sp * 0.9), anchor: .center)
        }
    }

    private static func drawRest(_ value: NoteValue, x: CGFloat, staffTop: CGFloat, sp: CGFloat,
                                 ink: GraphicsContext.Shading, in context: inout GraphicsContext) {
        let mid = staffTop + sp * 2
        switch value.base {
        case .whole:
            context.fill(Path(CGRect(x: x - sp * 0.7, y: staffTop + sp, width: sp * 1.4, height: sp * 0.5)), with: ink)
        case .half:
            context.fill(Path(CGRect(x: x - sp * 0.7, y: mid - sp * 0.5, width: sp * 1.4, height: sp * 0.5)), with: ink)
        case .quarter:
            var p = Path()
            p.move(to: CGPoint(x: x - sp * 0.3, y: mid - sp * 1.6))
            p.addLine(to: CGPoint(x: x + sp * 0.5, y: mid - sp * 0.7))
            p.addLine(to: CGPoint(x: x - sp * 0.3, y: mid + sp * 0.2))
            p.addLine(to: CGPoint(x: x + sp * 0.5, y: mid + sp * 1.1))
            p.addQuadCurve(to: CGPoint(x: x - sp * 0.3, y: mid + sp * 1.5), control: CGPoint(x: x - sp * 0.4, y: mid + sp * 0.6))
            context.stroke(p, with: ink, lineWidth: sp * 0.28)
        case .eighth, .sixteenth, .thirtySecond:
            let hooks = value.flags
            var p = Path()
            let top = mid - sp * 0.9
            p.move(to: CGPoint(x: x + sp * 0.6, y: top)); p.addLine(to: CGPoint(x: x - sp * 0.4, y: top + sp * (1.6 + CGFloat(hooks - 1) * 0.9)))
            context.stroke(p, with: ink, lineWidth: sp * 0.16)
            for i in 0..<hooks {
                let hy = top + CGFloat(i) * sp * 0.9
                var hook = Path()
                hook.move(to: CGPoint(x: x + sp * 0.6 - CGFloat(i) * sp * 0.25, y: hy))
                hook.addQuadCurve(to: CGPoint(x: x - sp * 0.3, y: hy + sp * 0.1), control: CGPoint(x: x + sp * 0.1, y: hy + sp * 0.6))
                context.stroke(hook, with: ink, lineWidth: sp * 0.16)
                context.fill(Path(ellipseIn: CGRect(x: x - sp * 0.55, y: hy - sp * 0.1, width: sp * 0.45, height: sp * 0.45)), with: ink)
            }
        }
        for dot in 0..<value.dots {
            context.fill(Path(ellipseIn: CGRect(x: x + sp * (1.0 + CGFloat(dot) * 0.6), y: mid - sp * 0.7, width: sp * 0.36, height: sp * 0.36)), with: ink)
        }
    }
}
