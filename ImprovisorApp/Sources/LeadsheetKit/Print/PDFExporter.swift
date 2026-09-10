//
//  PDFExporter.swift
//  LeadsheetKit
//
//  Renders pages as vector PDF (SwiftUI ImageRenderer into a CGContext) and
//  drives the system print dialog through PDFKit.
//

import SwiftUI
import AppKit
import PDFKit
import ImprovisorEngine

/// One printed page.
public struct PageView: View {
    public var page: Page
    public var score: Score
    public var spec: PageSpec
    public var pageCount: Int

    public init(page: Page, score: Score, spec: PageSpec, pageCount: Int) {
        self.page = page
        self.score = score
        self.spec = spec
        self.pageCount = pageCount
    }

    private static let theme = StaveTheme(
        background: .white, ink: .black, staffLine: .black, chordSymbol: .black, sectionMarker: Color(white: 0.3),
        measureNumber: Color(white: 0.4), playhead: .clear, selection: .clear, cursor: .clear)

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            // Header.
            VStack(alignment: .leading, spacing: 2) {
                if page.isFirst {
                    Text(score.title.isEmpty ? "Untitled" : score.title).font(.system(size: 22, weight: .bold))
                    HStack {
                        if !score.composer.isEmpty { Text(score.composer).font(.system(size: 12)) }
                        Spacer()
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(Color(white: 0.3))
                    }
                } else {
                    HStack {
                        Text(score.title.isEmpty ? "Untitled" : score.title).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text(subtitle).font(.system(size: 9)).foregroundStyle(Color(white: 0.3))
                    }
                }
            }
            .frame(width: spec.printableWidth, alignment: .leading)
            .offset(x: spec.margin, y: spec.margin)
            // Notation segments.
            ForEach(Array(page.segments.enumerated()), id: \.offset) { _, segment in
                if let label = segment.chorusLabel {
                    Text(label).font(.system(size: 11, weight: .semibold))
                        .offset(x: spec.margin, y: segment.y - 16)
                }
                let rect = segment.sourceRect
                Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                    context.translateBy(x: 0, y: -rect.minY)
                    StaveRenderer.draw(segment.layout, in: &context, theme: PageView.theme, visible: rect)
                }
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .offset(x: spec.margin, y: segment.y)
            }
            // Footer.
            Text("\(page.index + 1) / \(pageCount)")
                .font(.system(size: 9)).foregroundStyle(Color(white: 0.4))
                .frame(width: spec.printableWidth, alignment: .center)
                .offset(x: spec.margin, y: spec.size.height - spec.margin - 10)
        }
        .frame(width: spec.size.width, height: spec.size.height)
        .foregroundStyle(.black)
    }

    private var subtitle: String {
        var parts: [String] = []
        parts.append(score.styleName)
        parts.append("\(Int(score.tempo)) bpm")
        parts.append("\(score.meter.numerator)/\(score.meter.denominator)")
        return parts.joined(separator: " · ")
    }
}

@MainActor
public enum PDFExporter {

    /// Vector PDF of `parts` (empty = all choruses).
    public static func pdfData(score: Score, parts: [Int] = [], spec: PageSpec = .letter) -> Data? {
        let pages = PageLayout.pages(score: score, parts: parts, spec: spec)
        guard !pages.isEmpty else { return nil }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var box = CGRect(origin: .zero, size: spec.size)
        guard let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for page in pages {
            let renderer = ImageRenderer(content: PageView(page: page, score: score, spec: spec, pageCount: pages.count))
            renderer.proposedSize = ProposedViewSize(spec.size)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return data as Data
    }

    /// Write a PDF file.
    public static func export(score: Score, parts: [Int] = [], to url: URL, spec: PageSpec = .letter) throws {
        guard let data = pdfData(score: score, parts: parts, spec: spec) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    /// Show the system print dialog for the score.
    public static func print(score: Score, parts: [Int] = [], window: NSWindow? = nil) {
        guard let data = pdfData(score: score, parts: parts), let document = PDFDocument(data: data) else { return }
        let info = NSPrintInfo.shared
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: false) else { return }
        operation.jobTitle = score.title.isEmpty ? "Leadsheet" : score.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window { operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) }
        else { operation.run() }
    }
}
