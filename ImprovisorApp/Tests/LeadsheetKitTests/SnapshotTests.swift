//
//  SnapshotTests.swift
//  LeadsheetKitTests
//
//  Renders notation to PNG files so the result can be inspected by eye (the
//  files land in $LEADSHEET_SNAPSHOT_DIR, default /tmp/leadsheet-snapshots),
//  and checks that the images are non-trivial and stable across two renders.
//

import XCTest
import AppKit
@testable import LeadsheetKit
@testable import ImprovisorEngine

@MainActor
final class SnapshotTests: XCTestCase {

    let library = DataLibrary(root: LeadsheetDocumentTests.repoRoot)

    static let outputDir: URL = {
        let path = ProcessInfo.processInfo.environment["LEADSHEET_SNAPSHOT_DIR"] ?? "/tmp/leadsheet-snapshots"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @discardableResult
    private func snapshot(_ name: String, score: Score, part: Int = 0, options: StaveOptions = StaveOptions(),
                          theme: StaveTheme = .light) throws -> Data {
        let data = try XCTUnwrap(SnapshotRenderer.png(score: score, part: part, options: options, theme: theme), "render \(name)")
        try data.write(to: SnapshotTests.outputDir.appending(path: "\(name).png"))
        // Non-trivial: a real image with some ink.
        let image = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertGreaterThan(image.pixelsWide, 100)
        var dark = 0, samples = 0
        for y in stride(from: 0, to: image.pixelsHigh, by: 7) {
            for x in stride(from: 0, to: image.pixelsWide, by: 7) {
                samples += 1
                if let c = image.colorAt(x: x, y: y), c.brightnessComponent < 0.5 { dark += 1 }
            }
        }
        let ratio = Double(dark) / Double(max(1, samples))
        if theme == .light { XCTAssertGreaterThan(ratio, 0.005, "\(name) looks blank") }
        return data
    }

    func testTestTuneSnapshot() throws {
        let score = try LeadsheetParser.parse(contentsOf: LeadsheetDocumentTests.repoRoot.appending(path: "leadsheets/_test.ls"), vocabulary: library.vocabulary)
        var options = StaveOptions(); options.width = 1000; options.measuresPerLine = 4
        let a = try snapshot("test-tune", score: score, options: options)
        let b = try snapshot("test-tune", score: score, options: options)
        // Text rasterization can differ by a few bytes; the geometry must not.
        let ia = try XCTUnwrap(NSBitmapImageRep(data: a)), ib = try XCTUnwrap(NSBitmapImageRep(data: b))
        XCTAssertEqual(ia.pixelsWide, ib.pixelsWide); XCTAssertEqual(ia.pixelsHigh, ib.pixelsHigh)
        XCTAssertEqual(Double(a.count), Double(b.count), accuracy: Double(a.count) * 0.01)
        try snapshot("test-tune-dark", score: score, options: options, theme: .dark)
    }

    func testRhythmFixtureSnapshot() throws {
        // Every value, dots, triplets, ties across a bar, rests, accidentals, ledger lines.
        let text = """
        (title Rhythm Fixture)(meter 4 4)(key -2)(tempo 120.0)(style swing)
        (part (type chords))
        Bbmaj7 | Eb7 Edim7 | F7 | Bb6 |
        Cm7 F7 | Dm7 G7 | Cm7 | F7#9 |
        (part (type melody)(stave treble))
        bb1 d+2 f+4 g+8 a+8
        bb+8/3 a+8/3 g+8/3 f+4 eb+16 d+16 c+16 bb16 a4+8 g8
        f2+4 r4
        d8 eb8 e8 f8 r8 g8 ab8 a8
        c+4. bb8 a4 g4
        f#8 g8 r4 a-4 bb-4
        c2 r2
        f+1+1
        """
        let score = LeadsheetParser.parse(text, vocabulary: library.vocabulary)
        var options = StaveOptions(); options.width = 1000; options.measuresPerLine = 4
        try snapshot("rhythm-fixture", score: score, options: options)
    }

    func testGrandStaffSnapshot() throws {
        var score = Score.blank(measures: 4, styleName: "swing")
        score.key = Key(index: 3)
        score.melodyParts[0] = MelodyPart(events: [
            .note(Note(pitch: 43, duration: 240)), .note(Note(pitch: 48, duration: 240)),
            .note(Note(pitch: 55, duration: 120)), .note(Note(pitch: 60, duration: 120)), .note(Note(pitch: 64, duration: 120)), .note(Note(pitch: 67, duration: 120)),
            .note(Note(pitch: 72, duration: 480)),
            .note(Note(pitch: 40, duration: 480))
        ], info: PartInfo(stave: .grand))
        var options = StaveOptions(); options.width = 900; options.measuresPerLine = 4
        try snapshot("grand-staff", score: score, options: options)
    }

    func testThirtyTwoBarStandardSnapshot() throws {
        let url = LeadsheetDocumentTests.repoRoot.appending(path: "leadsheets/imaginary-book/AllOfMe.ls")
        let score = try LeadsheetParser.parse(contentsOf: url, vocabulary: library.vocabulary)
        var options = StaveOptions(); options.width = 1000
        try snapshot("all-of-me", score: score, options: options)
    }
}
