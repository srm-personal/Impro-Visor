//
//  ChordEditingTests.swift
//  LeadsheetKitTests
//
//  Phase 7: chord autocomplete ordering, bar text ↔ ChordPart, transposition commands.
//

import XCTest
@testable import LeadsheetKit
@testable import ImprovisorEngine

@MainActor
final class ChordEditingTests: XCTestCase {

    let library = DataLibrary(root: LeadsheetDocumentTests.repoRoot)
    var vocab: Vocabulary { library.vocabulary }

    private func makeEditor(_ chords: String) -> EditorController {
        let score = LeadsheetParser.parse("(meter 4 4)(key 0)(style swing)(part (type chords))\n\(chords)", vocabulary: vocab)
        let editor = EditorController(document: LeadsheetDocument(score: score))
        editor.auditions = false
        return editor
    }

    func testCompleterOrdering() {
        let d = ChordCompleter.suggest("D", vocabulary: vocab)
        XCTAssertEqual(d.first, "D")
        XCTAssertEqual(Array(d.prefix(4)), ["D", "D7", "Dm7", "DM7"])
        let dm = ChordCompleter.suggest("Dm", vocabulary: vocab)
        XCTAssertEqual(dm.first, "Dm")
        XCTAssertTrue(dm.contains("Dm7") && dm.contains("Dm6") && dm.contains("Dm9"))
        XCTAssertTrue(dm.allSatisfy { $0.hasPrefix("Dm") })
        let eb7 = ChordCompleter.suggest("Eb7", vocabulary: vocab)
        XCTAssertEqual(eb7.first, "Eb7")
        XCTAssertTrue(eb7.contains("Eb7b9"))
        XCTAssertEqual(ChordCompleter.suggest("n", vocabulary: vocab), ["NC"])
        XCTAssertEqual(ChordCompleter.suggest("", vocabulary: vocab).count, 8)   // 7 roots + NC
        XCTAssertEqual(ChordCompleter.suggest("x", vocabulary: vocab), [])
        XCTAssertTrue(ChordCompleter.isKnown("F#m7b5", vocabulary: vocab))
        XCTAssertFalse(ChordCompleter.isKnown("Fzz", vocabulary: vocab))
        XCTAssertFalse(ChordCompleter.isKnown("H7", vocabulary: vocab))
    }

    func testBarTextRoundTrip() {
        let editor = makeEditor("C | F G7 | C / A7 / | Dm7 |")
        XCTAssertEqual(editor.chordText(forMeasure: 0), "C")
        XCTAssertEqual(editor.chordText(forMeasure: 1), "F G7")
        XCTAssertEqual(editor.chordText(forMeasure: 2), "C A7")   // fewest cells that express the same changes
        editor.commitChordText("Em7 A7", forMeasure: 3)
        XCTAssertEqual(editor.chordText(forMeasure: 3), "Em7 A7")
        XCTAssertEqual(editor.score.chordPart.size, 4 * 480)
        // Leading slash holds the previous bar's chord.
        editor.commitChordText("/ Bb7", forMeasure: 1)
        XCTAssertEqual(editor.chordText(forMeasure: 1), "/ Bb7")
        XCTAssertEqual(editor.score.chordPart.chord(at: 480)?.name, "C")
        // Empty text = hold the previous chord for the bar.
        editor.commitChordText("", forMeasure: 2)
        XCTAssertEqual(editor.score.chordPart.chord(at: 960)?.name, "Bb7")
        XCTAssertEqual(editor.chordText(forMeasure: 2), "/")
        // Bars beyond the current end extend the progression.
        editor.commitChordText("G7", forMeasure: 5)
        XCTAssertEqual(editor.score.chordPart.size, 6 * 480)
        XCTAssertEqual(editor.chordText(forMeasure: 4), "/")
        // Round trip through the file format.
        let text = LeadsheetWriter.leadsheet(score: editor.score)
        XCTAssertEqual(LeadsheetParser.parse(text, vocabulary: vocab).chordPart, editor.score.chordPart)
        XCTAssertEqual(editor.unknownChordTokens(in: "C Fzz / G7"), ["Fzz"])
    }

    func testTransposeCommands() {
        let editor = makeEditor("Dm7 | G7 | C | C |")
        editor.document.perform("melody", undoManager: nil) { $0.melodyParts = [MelodyPart(events: [.note(Note(pitch: 62, duration: 480)), .rest(Rest(duration: 3 * 480))])] }
        editor.transpose(.both, by: 2)
        XCTAssertEqual(editor.score.chordPart.entries.map(\.symbol.name), ["Em7", "A7", "D"])
        XCTAssertEqual(editor.melody.notes.first?.pitch, 64)
        editor.select(range: 0..<480)
        editor.transpose(.chords, by: -2)
        XCTAssertEqual(editor.score.chordPart.entries.map(\.symbol.name), ["Dm7", "A7", "D"])
        XCTAssertEqual(editor.melody.notes.first?.pitch, 64)
        editor.transpose(.melody, by: -2)
        XCTAssertEqual(editor.melody.notes.first?.pitch, 62)
    }

    func testMIDINoteEntry() {
        let editor = makeEditor("C | F | G7 | C |")
        editor.document.perform("melody", undoManager: nil) { $0.melodyParts = [MelodyPart(events: [.rest(Rest(duration: 4 * 480))])] }
        editor.midiInput.deliver(bytes: [0x90, 64, 100, 0x80, 64, 0, 0x90, 67, 100, 0x80, 67, 0])
        let exp = expectation(description: "midi notes entered on main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(editor.melody.notes.map(\.pitch), [64, 67])
        XCTAssertEqual(editor.cursorSlot, 120)
    }
}
