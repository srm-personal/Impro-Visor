//
//  LeadsheetDocumentTests.swift
//  LeadsheetKitTests
//
//  Phase 4: document read/write, undo/redo, data library location.
//

import XCTest
import UniformTypeIdentifiers
@testable import LeadsheetKit
@testable import ImprovisorEngine

final class LeadsheetDocumentTests: XCTestCase {

    static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { u.deleteLastPathComponent() } // Tests/LeadsheetKitTests/file → repo
        return u
    }()
    let library = DataLibrary(root: LeadsheetDocumentTests.repoRoot)

    func testLibraryLocatesTheCorpus() {
        XCTAssertTrue(library.hasCorpus)
        XCTAssertTrue(DataLibrary.shared.hasCorpus, "shared library should find the checkout during swift test")
        XCTAssertGreaterThan(library.styleNames.count, 100)
        XCTAssertTrue(library.styleNames.contains("swing"))
        XCTAssertGreaterThan(library.grammarNames.count, 50)
        XCTAssertGreaterThan(library.leadsheetURLs().count, 3000)
        XCTAssertNotNil(library.style(named: "swing"))
        XCTAssertNil(library.style(named: "no-such-style"))
        XCTAssertEqual(library.style(named: "swing"), library.style(named: "swing")) // cached
    }

    func testBlankDocument() {
        let doc = LeadsheetDocument()
        XCTAssertEqual(doc.score.measureCount, 32)
        XCTAssertEqual(doc.score.melodyParts.count, 1)
        XCTAssertEqual(doc.score.melodyParts[0].size, 32 * 480)
        XCTAssertTrue(doc.score.chordPart.entries.allSatisfy { $0.symbol.isNoChord })
        XCTAssertEqual(doc.score.sections.records.first?.styleName, "swing")
        XCTAssertTrue(LeadsheetDocument.readableContentTypes.contains(.leadsheet))
        // The `ls` extension is declared by the app's Info.plist (checked in the
        // app test bundle); here only the identifier is known.
        XCTAssertEqual(UTType.leadsheet.identifier, "com.srmorin.leadsheetstudio.leadsheet")
    }

    func testReadWriteRoundTrip() throws {
        let url = LeadsheetDocumentTests.repoRoot.appending(path: "leadsheets/_test.ls")
        let doc = try LeadsheetDocument(data: try Data(contentsOf: url), vocabulary: library.vocabulary)
        XCTAssertEqual(doc.score.title, "The Night Has a Thousand Eyes")
        let snapshot = try doc.snapshot(contentType: .leadsheet)
        let data = LeadsheetDocument.data(for: snapshot)
        let again = try LeadsheetDocument(data: data, vocabulary: library.vocabulary)
        XCTAssertEqual(again.score, doc.score)
    }

    @MainActor
    func testUndoRedo() {
        let doc = LeadsheetDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        doc.perform("Change Title", undoManager: undo) { $0.title = "One" }
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        doc.perform("Change Title", undoManager: undo) { $0.title = "Two" }
        undo.endUndoGrouping()
        XCTAssertEqual(doc.score.title, "Two")
        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(undo.undoActionName, "Change Title")
        undo.undo()
        XCTAssertEqual(doc.score.title, "One")
        undo.undo()
        XCTAssertEqual(doc.score.title, "")
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(doc.score.title, "One")
        undo.redo()
        XCTAssertEqual(doc.score.title, "Two")

        // A no-op edit registers nothing.
        let fresh = UndoManager()
        fresh.groupsByEvent = false
        fresh.beginUndoGrouping()
        doc.perform("Nothing", undoManager: fresh) { _ in }
        fresh.endUndoGrouping()
        XCTAssertEqual(doc.score.title, "Two")
    }

    @MainActor
    func testChordTextEditIsUndoable() {
        let doc = LeadsheetDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let part = LeadsheetParser.chordPart(fromText: "Dm7 | G7 | C | C |", meter: .fourFour, vocabulary: library.vocabulary)
        undo.beginUndoGrouping()
        doc.perform("Change Chords", undoManager: undo) { $0.chordPart = part }
        undo.endUndoGrouping()
        XCTAssertEqual(doc.score.measureCount, 4)
        undo.undo()
        XCTAssertEqual(doc.score.measureCount, 32)
    }

    @MainActor
    func testPlaybackControllerBuildsArrangementAndExports() throws {
        let playback = PlaybackController(library: library)
        let doc = LeadsheetDocument(score: LeadsheetParser.parse("(meter 4 4)(style swing)(part (type chords))\nDm7 | G7 | C | C |", vocabulary: library.vocabulary))
        let tmp = FileManager.default.temporaryDirectory.appending(path: "leadsheetkit-\(UUID().uuidString).mid")
        playback.choruses = 2
        playback.exportMIDI(score: doc.score, to: tmp)
        let data = try Data(contentsOf: tmp)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "MThd")
        XCTAssertTrue(playback.status.hasPrefix("Exported"))
        try? FileManager.default.removeItem(at: tmp)
    }
}
