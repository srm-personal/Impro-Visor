//
//  PrintTests.swift
//  LeadsheetKitTests
//
//  Phase 9: pagination, PDF export, About credits.
//

import XCTest
import PDFKit
@testable import LeadsheetKit
@testable import ImprovisorEngine

@MainActor
final class PrintTests: XCTestCase {

    let library = DataLibrary(root: LeadsheetDocumentTests.repoRoot)

    private func tune(bars: Int) -> Score {
        var score = Score.blank(measures: bars)
        score.title = "Pagination Test"
        score.composer = "Tests"
        var chords = ChordPart()
        let names = ["Dm7", "G7", "Cmaj7", "A7"]
        for i in 0..<bars { chords.append(ChordSymbol.parse(names[i % 4], vocabulary: library.vocabulary)!, duration: 480) }
        score.chordPart = chords
        var melody = MelodyPart(events: [])
        for i in 0..<bars {
            melody.append(.note(Note(pitch: 60 + (i % 7), duration: 240, volume: 127)))
            melody.append(.note(Note(pitch: 67 - (i % 5), duration: 240, volume: 127)))
        }
        score.melodyParts = [melody]
        return score
    }

    func testPageCounts() {
        let p32 = PageLayout.pages(score: tune(bars: 32))
        let p64 = PageLayout.pages(score: tune(bars: 64))
        XCTAssertEqual(p32.count, 2)
        XCTAssertEqual(p64.count, 4)   // 16 systems: 4 on the title page, 5 per page after
        // Every system appears exactly once and none overflows the page.
        for pages in [p32, p64] {
            var seen = 0
            for page in pages {
                for seg in page.segments {
                    seen += seg.systems.count
                    XCTAssertLessThanOrEqual(seg.y + seg.sourceRect.height, PageSpec.letter.size.height - PageSpec.letter.margin, "page \(page.index)")
                }
            }
            XCTAssertEqual(seen, pages.first!.segments.first!.layout.systems.count)
        }
        // Two choruses print with chorus labels.
        var two = tune(bars: 32)
        two.melodyParts.append(two.melodyParts[0])
        let pages = PageLayout.pages(score: two)
        XCTAssertEqual(pages.flatMap(\.segments).compactMap(\.chorusLabel), ["Chorus 1", "Chorus 2"])
    }

    func testPDFHasUniformPagesAndInk() throws {
        let score = tune(bars: 64)
        let data = try XCTUnwrap(PDFExporter.pdfData(score: score))
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 4)
        let sizes = (0..<document.pageCount).map { document.page(at: $0)!.bounds(for: .mediaBox).size }
        XCTAssertTrue(sizes.allSatisfy { $0 == sizes[0] })
        XCTAssertEqual(sizes[0], CGSize(width: 612, height: 792))
        // Page 1 has ink and the title text.
        let page = try XCTUnwrap(document.page(at: 0))
        let image = page.thumbnail(of: CGSize(width: 306, height: 396), for: .mediaBox)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        var dark = 0, total = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                total += 1
                if let c = rep.colorAt(x: x, y: y), c.brightnessComponent < 0.5 { dark += 1 }
            }
        }
        XCTAssertGreaterThan(Double(dark) / Double(total), 0.01)
        try data.write(to: SnapshotTests.outputDir.appending(path: "print-64-bars.pdf"))
    }

    func testAboutCredits() {
        let about = AboutInfo.current(library: library)
        XCTAssertTrue(about.credits.contains("Impro-Visor"))
        XCTAssertTrue(about.credits.contains("Robert Keller"))
        XCTAssertTrue(about.credits.contains("Harvey Mudd College"))
        XCTAssertTrue(about.licenseText.contains("GNU GENERAL PUBLIC LICENSE"))
        XCTAssertEqual(about.sourceURL.host, "github.com")
        XCTAssertFalse(about.version.isEmpty)
    }
}
