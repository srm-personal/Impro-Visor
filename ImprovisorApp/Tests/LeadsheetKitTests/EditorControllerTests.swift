//
//  EditorControllerTests.swift
//  LeadsheetKitTests
//
//  Phase 6: the editor's key map, step entry, mouse placement with harmonic
//  snapping, selection, clipboard, transposition, undo — all without a window.
//

import XCTest
@testable import LeadsheetKit
@testable import ImprovisorEngine

@MainActor
final class EditorControllerTests: XCTestCase {

    let library = DataLibrary(root: LeadsheetDocumentTests.repoRoot)

    private func makeEditor(chords: String = "C | F | G7 | C |", bars: Int = 4) -> (EditorController, UndoManager) {
        let text = "(meter 4 4)(key 0)(style swing)(part (type chords))\n\(chords)"
        var score = LeadsheetParser.parse(text, vocabulary: library.vocabulary)
        score.melodyParts = [MelodyPart(events: [.rest(Rest(duration: bars * 480))])]
        let doc = LeadsheetDocument(score: score)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = EditorController(document: doc)
        editor.undoManager = undo
        editor.auditions = false
        var options = StaveOptions(); options.width = 1000; options.measuresPerLine = 4
        editor.layout = StaveLayout.layout(score: doc.score, options: options)
        return (editor, undo)
    }

    private func type(_ editor: EditorController, _ keys: String, modifiers: KeyEvent.Modifiers = []) {
        for ch in keys where ch != " " { XCTAssertTrue(editor.handle(KeyEvent(String(ch), modifiers: modifiers)), "unhandled key \(ch)") }
    }

    private func n(_ p: Int, _ d: Int, _ s: Accidental = .natural) -> MusicEvent { .note(Note(pitch: p, duration: d, volume: 127, spelling: s)) }
    private func r(_ d: Int) -> MusicEvent { .rest(Rest(duration: d)) }

    // MARK: Key map

    func testKeyMapTable() {
        XCTAssertEqual(KeyMap.action(for: KeyEvent("c")), .enterPitch(letter: 0, octaveShift: 0))
        XCTAssertEqual(KeyMap.action(for: KeyEvent("B", modifiers: .shift)), .enterPitch(letter: 6, octaveShift: 1))
        XCTAssertEqual(KeyMap.action(for: KeyEvent("g", modifiers: .option)), .enterPitch(letter: 4, octaveShift: -1))
        XCTAssertEqual(KeyMap.action(for: KeyEvent("A", modifiers: .shift)), .approachNext)
        XCTAssertEqual(KeyMap.action(for: KeyEvent("4")), .setBase(.quarter))
        XCTAssertEqual(KeyMap.action(for: KeyEvent("6")), .setBase(.sixteenth))
        XCTAssertEqual(KeyMap.action(for: KeyEvent("3")), .toggleTriplet)
        XCTAssertEqual(KeyMap.action(for: KeyEvent(".")), .toggleDot)
        XCTAssertEqual(KeyMap.action(for: KeyEvent("-")), .tie)
        XCTAssertEqual(KeyMap.action(for: KeyEvent("r")), .rest)
        XCTAssertEqual(KeyMap.action(for: KeyEvent(special: .up)), .stepPitch(1))
        XCTAssertEqual(KeyMap.action(for: KeyEvent(special: .down, modifiers: .option)), .transpose(-1))
        XCTAssertEqual(KeyMap.action(for: KeyEvent(special: .up, modifiers: .command)), .transpose(12))
        XCTAssertEqual(KeyMap.action(for: KeyEvent(special: .right, modifiers: .shift)), .extendSelection(1))
        XCTAssertEqual(KeyMap.action(for: KeyEvent(special: .delete)), .eraseSelection)
        XCTAssertEqual(KeyMap.action(for: KeyEvent(special: .delete, modifiers: .option)), .removeSelection)
        XCTAssertEqual(KeyMap.action(for: KeyEvent(special: .space)), .playPause)
        XCTAssertEqual(KeyMap.action(for: KeyEvent(special: .return)), .playSelection)
        XCTAssertEqual(KeyMap.action(for: KeyEvent("z", modifiers: .command)), .undo)
        XCTAssertEqual(KeyMap.action(for: KeyEvent("z", modifiers: [.command, .shift])), .redo)
        XCTAssertEqual(KeyMap.action(for: KeyEvent("c", modifiers: [.command, .shift])), .copy(.chords))
        XCTAssertEqual(KeyMap.action(for: KeyEvent("v", modifiers: [.command, .option])), .paste(.both))
        XCTAssertEqual(KeyMap.action(for: KeyEvent("k", modifiers: [.command, .shift])), .focusChords)
        XCTAssertNil(KeyMap.action(for: KeyEvent("q")))
    }

    // MARK: Step entry

    func testTypingLettersEntersEighthsAndAdvances() {
        let (editor, _) = makeEditor()
        type(editor, "ceg")
        XCTAssertEqual(editor.melody.events, [n(60, 60), n(64, 60), n(67, 60), r(4 * 480 - 180)])
        XCTAssertEqual(editor.cursorSlot, 180)
        XCTAssertEqual(editor.lastPitch, 67)
        // Nearest octave: after G4, "c" is C5 (72), not C4 (60).
        type(editor, "c")
        XCTAssertEqual(editor.melody.events[3], n(72, 60))
    }

    func testDurationDotTripletTieAndRest() {
        let (editor, _) = makeEditor()
        type(editor, "4c")                 // quarter C
        type(editor, ".d")                 // dotted quarter D
        XCTAssertEqual(editor.melody.events.prefix(2), [n(60, 120), n(62, 180)])
        type(editor, ".")                  // dot off
        type(editor, "83e")                // triplet eighth E
        XCTAssertEqual(editor.melody.events[2], n(64, 40))
        type(editor, "3")                  // triplet off
        type(editor, "-")                  // extend E by an eighth
        XCTAssertEqual(editor.melody.events[2], n(64, 100))
        type(editor, "r")                  // eighth rest
        type(editor, "f")
        XCTAssertEqual(editor.melody.events[3], r(60))
        XCTAssertEqual(editor.melody.events[4], n(65, 60))
        XCTAssertEqual(editor.melody.size, 4 * 480)
    }

    func testSharpKeysSpellLettersFromTheKey() {
        let (editor, _) = makeEditor(chords: "G | D7 | G | G |")
        editor.document.perform("key", undoManager: nil) { $0.key = Key(index: 1) }
        type(editor, "f")
        XCTAssertEqual(editor.melody.events.first, n(66, 60, .sharp))   // F# in G major
    }

    func testUndoRestoresEachEntry() {
        let (editor, undo) = makeEditor()
        for ch in "ceg" { undo.beginUndoGrouping(); type(editor, String(ch)); undo.endUndoGrouping() }
        XCTAssertEqual(editor.melody.noteCount, 3)
        undo.undo(); XCTAssertEqual(editor.melody.noteCount, 2)
        undo.undo(); undo.undo()
        XCTAssertEqual(editor.melody.events, [r(4 * 480)])
        undo.redo(); XCTAssertEqual(editor.melody.noteCount, 1)
    }

    // MARK: Selection, arrows, transposition

    func testArrowsMoveCursorAndSelection() {
        let (editor, _) = makeEditor()
        editor.handle(KeyEvent(special: .right)); editor.handle(KeyEvent(special: .right))
        XCTAssertEqual(editor.cursorSlot, 120)
        editor.handle(KeyEvent(special: .right, modifiers: .shift))
        XCTAssertEqual(editor.selection, 120..<180)
        editor.handle(KeyEvent(special: .right, modifiers: .shift))
        XCTAssertEqual(editor.selection, 120..<240)
        editor.handle(KeyEvent(special: .left))
        XCTAssertNil(editor.selection)
        XCTAssertEqual(editor.cursorSlot, 180)
        editor.handle(KeyEvent(special: .escape))
    }

    func testPitchArrowsAndTranspose() {
        let (editor, _) = makeEditor()
        type(editor, "4c")                       // C4 quarter at 0, cursor 120
        editor.select(range: 0..<120)
        editor.handle(KeyEvent(special: .up))    // diatonic step → D
        XCTAssertEqual(editor.melody.notes[0].pitch, 62)
        editor.handle(KeyEvent(special: .up, modifiers: .option))   // semitone → Eb
        XCTAssertEqual(editor.melody.notes[0].pitch, 63)
        editor.handle(KeyEvent(special: .up, modifiers: .command))  // octave
        XCTAssertEqual(editor.melody.notes[0].pitch, 75)
        editor.handle(KeyEvent("="))                                 // enharmonic
        XCTAssertEqual(editor.melody.notes[0].spelling, .sharp)
        // No selection: the arrow applies to the note at the cursor.
        editor.selection = nil; editor.cursorSlot = 60
        editor.handle(KeyEvent(special: .down, modifiers: .command))
        XCTAssertEqual(editor.melody.notes[0].pitch, 63)
    }

    func testDeleteErasesAndOptionDeleteCloses() {
        let (editor, _) = makeEditor()
        type(editor, "4cdef")
        editor.select(range: 120..<240)
        editor.handle(KeyEvent(special: .delete))
        XCTAssertEqual(editor.melody.events.prefix(3), [n(60, 120), r(120), n(64, 120)])
        editor.select(range: 120..<240)
        editor.handle(KeyEvent(special: .delete, modifiers: .option))
        XCTAssertEqual(editor.melody.events.prefix(3), [n(60, 120), n(64, 120), n(65, 120)])
        XCTAssertEqual(editor.melody.size, 4 * 480)               // refilled to the form
    }

    func testNudgeMovesNotesInTime() {
        let (editor, _) = makeEditor()
        type(editor, "4c")
        editor.select(range: 0..<120)
        editor.entry.base = .eighth
        editor.handle(KeyEvent(special: .right, modifiers: .option))
        XCTAssertEqual(editor.melody.events.prefix(2), [r(60), n(60, 120)])
        XCTAssertEqual(editor.selection, 60..<180)
    }

    // MARK: Clipboard

    func testCopyPasteMelodyAndChords() {
        let (editor, _) = makeEditor()
        type(editor, "4cegc")
        editor.select(range: 0..<240)
        editor.copy(.both)
        XCTAssertEqual(Clipboard.local?.melody, [n(60, 120), n(64, 120)])
        XCTAssertEqual(Clipboard.local?.chords?.entries.first?.symbol.name, "C")
        editor.cursorSlot = 960; editor.selection = nil
        editor.paste(.melody)
        XCTAssertEqual(editor.melody.events(in: 960..<1200), [n(60, 120), n(64, 120)])
        XCTAssertEqual(editor.cursorSlot, 1200)
        // Chords: paste C over bar 3 (G7).
        editor.cursorSlot = 960
        editor.paste(.chords)
        XCTAssertEqual(editor.score.chordPart.chord(at: 960)?.name, "C")
        XCTAssertEqual(editor.score.chordPart.chord(at: 1200)?.name, "G7")
        XCTAssertEqual(editor.score.chordPart.size, 4 * 480)
        // Text form round trips.
        let clip = Clip.parse(Clipboard.local!.text, meter: .fourFour, vocabulary: library.vocabulary)
        XCTAssertEqual(clip.melody?.map { $0.note?.pitch }, Clipboard.local?.melody?.map { $0.note?.pitch })
        XCTAssertEqual(clip.melody?.map(\.duration), Clipboard.local?.melody?.map(\.duration))
        XCTAssertEqual(clip.chords?.entries.map(\.symbol.name), Clipboard.local?.chords?.entries.map(\.symbol.name))
    }

    func testCutLeavesRests() {
        let (editor, _) = makeEditor()
        type(editor, "4cd")
        editor.select(range: 0..<240)
        editor.cut(.melody)
        XCTAssertEqual(editor.melody.events, [r(4 * 480)])
        XCTAssertEqual(Clipboard.local?.melody?.count, 2)
    }

    // MARK: Mouse

    func testClickPlacesNoteSnappedToChordTone() {
        let (editor, _) = makeEditor(chords: "C7 | F | G7 | C |")
        editor.entry.mode = .chordTones
        let layout = editor.layout!
        // Point in bar 1 at the slot of beat 2, on the D4 line (diatonic 29) → harmonic snap to a C7 tone (C or E).
        let measure = layout.measures[0]
        let x = measure.x(forSlot: 120)
        let y = layout.geometry.y(forDiatonic: 29, clef: .treble, staffTop: layout.systems[0].staffTop)
        editor.entry.base = .quarter
        editor.click(at: CGPoint(x: x, y: y))
        let placed = editor.melody.placed.first { !$0.event.isRest }!
        XCTAssertEqual(placed.start, 120)
        XCTAssertTrue([60, 64].contains(placed.event.note!.pitch), "snapped pitch \(placed.event.note!.pitch)")
        XCTAssertEqual(placed.event.duration, 120)
        // Simple entry keeps the raw pitch.
        editor.entry.harmonic = false
        editor.click(at: CGPoint(x: measure.x(forSlot: 240), y: y))
        XCTAssertEqual(editor.melody.event(atSlot: 240)?.event.note?.pitch, 62)
        // Option-click enters a rest; a click on a note selects it.
        editor.click(at: CGPoint(x: measure.x(forSlot: 360), y: y), modifiers: .option)
        XCTAssertTrue(editor.melody.event(atSlot: 360)!.event.isRest)
        editor.layout = StaveLayout.layout(score: editor.score, options: { var o = StaveOptions(); o.width = 1000; o.measuresPerLine = 4; return o }())
        if case let .noteHead(hx, hy, _, _) = editor.layout!.glyphs.first(where: { if case .noteHead = $0 { return true } else { return false } })! {
            editor.click(at: CGPoint(x: hx, y: hy))
            XCTAssertEqual(editor.selection, 120..<240)
        } else { XCTFail("no note head") }
    }

    func testDragChangesPitchThenTime() {
        let (editor, _) = makeEditor()
        type(editor, "4c")
        editor.layout = StaveLayout.layout(score: editor.score, options: { var o = StaveOptions(); o.width = 1000; o.measuresPerLine = 4; return o }())
        guard case let .noteHead(hx, hy, _, _) = editor.layout!.glyphs.first(where: { if case .noteHead = $0 { return true } else { return false } })! else { return XCTFail() }
        editor.entry.harmonic = false
        editor.beginDrag(at: CGPoint(x: hx, y: hy))
        editor.drag(to: CGPoint(x: hx, y: hy - 2 * editor.layout!.geometry.stepHeight))   // two diatonic steps up → E
        editor.endDrag()
        XCTAssertEqual(editor.melody.notes[0].pitch, 64)
        // Horizontal drag by one beat.
        editor.layout = StaveLayout.layout(score: editor.score, options: { var o = StaveOptions(); o.width = 1000; o.measuresPerLine = 4; return o }())
        let m = editor.layout!.measures[0]
        editor.beginDrag(at: CGPoint(x: hx, y: hy - 2 * editor.layout!.geometry.stepHeight))
        editor.drag(to: CGPoint(x: m.x(forSlot: 120) + (hx - m.x(forSlot: 0)), y: hy - 2 * editor.layout!.geometry.stepHeight))
        editor.endDrag()
        XCTAssertEqual(editor.melody.events.prefix(2), [r(120), n(64, 120)])
    }

    // MARK: Snapshot of a scripted session

    func testScriptedSessionSnapshot() throws {
        let (editor, _) = makeEditor(chords: "Dm7 | G7 | Cmaj7 | A7b9 |")
        type(editor, "4d f a c")            // Dm7 arpeggio, quarters
        type(editor, "8g b d f")            // eighths
        type(editor, "4. e 8 d 4 c -")      // dotted quarter, eighth, quarter tied
        editor.handle(KeyEvent("A", modifiers: .shift)); type(editor, "e")   // approach tone request (letters bypass snapping)
        type(editor, "2 a")
        let data = try XCTUnwrap(SnapshotRenderer.png(score: editor.score, options: { var o = StaveOptions(); o.width = 1000; o.measuresPerLine = 4; return o }()))
        try data.write(to: SnapshotTests.outputDir.appending(path: "scripted-entry.png"))
        XCTAssertGreaterThan(editor.melody.noteCount, 10)
        // Writing and re-reading the edited tune is lossless.
        let text = LeadsheetWriter.leadsheet(score: editor.score)
        XCTAssertEqual(LeadsheetParser.parse(text, vocabulary: library.vocabulary), editor.score)
    }
}
