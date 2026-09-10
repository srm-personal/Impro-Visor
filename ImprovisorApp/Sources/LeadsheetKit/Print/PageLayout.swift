//
//  PageLayout.swift
//  LeadsheetKit
//
//  Paginates one or more choruses of a score onto fixed-size pages: the
//  notation is laid out with StaveLayout at the page's printable width, then
//  whole systems are packed onto pages below a header (title, composer,
//  style/tempo) on the first page and a running header afterwards.
//

import Foundation
import CoreGraphics
import ImprovisorEngine

public struct PageSpec: Equatable, Sendable {
    /// Page size in points (default US Letter).
    public var size = CGSize(width: 612, height: 792)
    public var margin: CGFloat = 40
    public var titleHeaderHeight: CGFloat = 64
    public var runningHeaderHeight: CGFloat = 22
    public var footerHeight: CGFloat = 20

    public init() {}

    public static let letter = PageSpec()
    public static var a4: PageSpec { var s = PageSpec(); s.size = CGSize(width: 595, height: 842); return s }

    public var printableWidth: CGFloat { size.width - 2 * margin }
}

/// A run of systems from one chorus placed on a page.
public struct PageSegment: Equatable, Sendable {
    public var part: Int
    public var layout: LayoutDocument
    public var systems: Range<Int>
    /// Where the first system's top lands on the page.
    public var y: CGFloat

    /// The rectangle of the source layout that this segment shows.
    public var sourceRect: CGRect {
        let first = layout.systems[systems.lowerBound], last = layout.systems[systems.upperBound - 1]
        return CGRect(x: 0, y: first.frame.minY, width: layout.width, height: last.frame.maxY - first.frame.minY)
    }
    /// A chorus label when this segment starts a chorus (nil otherwise).
    public var chorusLabel: String?
}

public struct Page: Equatable, Sendable {
    public var index: Int
    public var segments: [PageSegment]
    public var isFirst: Bool { index == 0 }
}

public enum PageLayout {

    /// Lay out `parts` (chorus indexes; empty = all) of `score` onto pages.
    public static func pages(score: Score, parts: [Int] = [], spec: PageSpec = .letter,
                             measuresPerLine: Int? = nil) -> [Page] {
        let partIndexes = parts.isEmpty ? Array(0..<max(1, score.melodyParts.count)) : parts
        var options = StaveOptions()
        options.width = spec.printableWidth
        options.measuresPerLine = measuresPerLine ?? (score.layout.first.flatMap { $0 > 0 ? $0 : nil } ?? 4)
        options.leftMargin = 0
        options.rightMargin = 0
        options.topMargin = 0

        var pages: [Page] = []
        var current: [PageSegment] = []
        var y = spec.margin + spec.titleHeaderHeight
        var pageIndex = 0
        func bottom() -> CGFloat { spec.size.height - spec.margin - spec.footerHeight }
        func flush() {
            pages.append(Page(index: pageIndex, segments: current))
            current = []
            pageIndex += 1
            y = spec.margin + spec.runningHeaderHeight
        }

        for part in partIndexes {
            let layout = StaveLayout.layout(score: score, part: part, options: options)
            guard !layout.systems.isEmpty else { continue }
            let label: String? = partIndexes.count > 1
                ? (part < score.melodyParts.count && !score.melodyParts[part].info.title.isEmpty ? score.melodyParts[part].info.title : "Chorus \(part + 1)")
                : nil
            var start = 0
            var labelPending = label
            while start < layout.systems.count {
                let labelHeight: CGFloat = labelPending == nil ? 0 : 18
                var end = start
                var height: CGFloat = labelHeight
                while end < layout.systems.count, height + layout.systems[end].frame.height <= bottom() - y {
                    height += layout.systems[end].frame.height
                    end += 1
                }
                if end == start {
                    if !current.isEmpty { flush(); continue }
                    end = start + 1 // a system taller than a page: place it anyway
                }
                var segment = PageSegment(part: part, layout: layout, systems: start..<end, y: y + labelHeight)
                segment.chorusLabel = labelPending
                labelPending = nil
                current.append(segment)
                y += height
                start = end
                if start < layout.systems.count { flush() }
            }
        }
        if !current.isEmpty || pages.isEmpty { flush() }
        return pages
    }
}
