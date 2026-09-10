//
//  StaveLayoutTests.swift
//  LeadsheetKitTests
//
//  Phase 5 layout engine: geometry, spelling, splitting, beaming, layout.
//

import XCTest
@testable import LeadsheetKit
@testable import ImprovisorEngine

final class StaveLayoutTests: XCTestCase {

    let library = DataLibrary(root: LeadsheetDocumentTests.repoRoot)
    var vocab: Vocabulary { library.vocabulary }

    // MARK: Geometry

    func testDiatonicYRoundTripsForEveryPitchOnBothClefs() {
        let g = StaffGeometry()
        for clef in Clef.allCases {
            for pitch in 0...127 {
                for preferSharp in [true, false] {
                    let d = PitchSpelling.spell(pitch, preferSharp: preferSharp).diatonic
                    let y = g.y(forDiatonic: d, clef: clef, staffTop: 100)
                    XCTAssertEqual(g.diatonic(atY: y, clef: clef, staffTop: 100), d, "pitch \(pitch) \(clef)")
                }
            }
        }
        // Middle C sits one ledger line below the treble staff and one above the bass staff.
        let c4 = PitchSpelling.spell(60, preferSharp: false).diatonic
        XCTAssertEqual(c4, 28)
        XCTAssertEqual(g.y(forDiatonic: c4, clef: .treble, staffTop: 0), 32 + 8)
        XCTAssertEqual(g.ledgerDiatonics(forDiatonic: c4, clef: .treble), [28])
        XCTAssertEqual(g.ledgerDiatonics(forDiatonic: c4, clef: .bass), [28])
        XCTAssertEqual(g.ledgerDiatonics(forDiatonic: 34, clef: .treble), [])       // B4 middle line
        XCTAssertEqual(g.ledgerDiatonics(forDiatonic: 42, clef: .treble), [40, 42]) // C6 → two ledgers
    }

    func testSpelling() {
        XCTAssertEqual(PitchSpelling.spell(61, preferSharp: true), SpelledPitch(letter: 0, accidental: 1, octave: 4))
        XCTAssertEqual(PitchSpelling.spell(61, preferSharp: false), SpelledPitch(letter: 1, accidental: -1, octave: 4))
        XCTAssertEqual(PitchSpelling.spell(59, preferSharp: false), SpelledPitch(letter: 6, accidental: 0, octave: 3))
        for pitch in 0...127 {
            XCTAssertEqual(PitchSpelling.spell(pitch, preferSharp: true).midi, pitch)
            XCTAssertEqual(PitchSpelling.spell(pitch, preferSharp: false).midi, pitch)
        }
        // Key signatures.
        XCTAssertEqual(PitchSpelling.keyAccidentals(Key(index: 2)), [1, 0, 0, 1, 0, 0, 0])   // D major: F# C#
        XCTAssertEqual(PitchSpelling.keyAccidentals(Key(index: -3)), [0, 0, -1, 0, 0, -1, -1]) // Eb: Bb Eb Ab
        XCTAssertEqual(PitchSpelling.keySignature(Key(index: 1), clef: .treble).map(\.diatonic), [38])
        XCTAssertEqual(PitchSpelling.keySignature(Key(index: 1), clef: .bass).map(\.diatonic), [24])
        // A flat-spelled note in a sharp key keeps its flat.
        XCTAssertEqual(PitchSpelling.spell(Note(pitch: 70, duration: 60, spelling: .flat), key: Key(index: 3)).letter, 6)
        XCTAssertEqual(PitchSpelling.spell(Note(pitch: 70, duration: 60), key: Key(index: 3)).letter, 5) // A# in A major
    }

    // MARK: Values and splitting

    func testNoteValueSlots() {
        XCTAssertEqual(NoteValue(.quarter).slots, 120)
        XCTAssertEqual(NoteValue(.half, dots: 1).slots, 360)
        XCTAssertEqual(NoteValue(.eighth, tuplet: 3).slots, 40)
        XCTAssertEqual(NoteValue(.sixteenth).flags, 2)
        XCTAssertFalse(NoteValue(.half).isFilled)
        XCTAssertFalse(NoteValue(.whole).hasStem)
        XCTAssertEqual(NoteValue.candidates.first?.slots, 720)
    }

    func testDurationValuesDecompose() {
        XCTAssertEqual(DurationSplitter.values(for: 120), [NoteValue(.quarter)])
        XCTAssertEqual(DurationSplitter.values(for: 180), [NoteValue(.quarter, dots: 1)])
        XCTAssertEqual(DurationSplitter.values(for: 40), [NoteValue(.eighth, tuplet: 3)])
        XCTAssertEqual(DurationSplitter.values(for: 600), [NoteValue(.whole), NoteValue(.quarter)])
        XCTAssertEqual(DurationSplitter.values(for: 140), [NoteValue(.quarter), NoteValue(.sixteenth, tuplet: 3)])
        for d in 10...960 {
            let vals = DurationSplitter.values(for: d)
            let total = vals.reduce(0) { $0 + $1.slots }
            XCTAssertLessThanOrEqual(total, d, "\(d)")
            XCTAssertLessThan(d - total, DurationSplitter.minimumSlots, "\(d) leaves \(d - total)")
        }
    }

    func testSplitPreservesTotalsAndNeverCrossesBarlines() {
        let part = MelodyPart(events: [
            .note(Note(pitch: 60, duration: 600)),   // crosses the bar line
            .rest(Rest(duration: 120)),
            .note(Note(pitch: 62, duration: 40)), .note(Note(pitch: 64, duration: 40)), .note(Note(pitch: 65, duration: 40)),
            .note(Note(pitch: 67, duration: 1080))   // 2 bars + a quarter
        ])
        let pieces = DurationSplitter.split(part, slotsPerMeasure: 480)
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.duration }, part.size)
        for p in pieces {
            XCTAssertEqual(p.start / 480, (p.end - 1) / 480, "piece \(p) crosses a bar line")
        }
        // The 600-slot note: whole (tied) + quarter.
        XCTAssertEqual(pieces[0].value, NoteValue(.whole)); XCTAssertTrue(pieces[0].tiedToNext)
        XCTAssertEqual(pieces[1].value, NoteValue(.quarter)); XCTAssertFalse(pieces[1].tiedToNext)
        XCTAssertTrue(pieces[2].isRest); XCTAssertFalse(pieces[2].tiedToNext)
        XCTAssertEqual(pieces[3].value, NoteValue(.eighth, tuplet: 3))
        // Every piece keeps its event index for hit-testing back to the melody.
        XCTAssertEqual(pieces.last?.eventIndex, 5)
    }

    func testBeamsStayWithinABeat() {
        let part = MelodyPart(events: (0..<16).map { _ in .note(Note(pitch: 67, duration: 30)) } + [.note(Note(pitch: 60, duration: 60)), .rest(Rest(duration: 60)), .note(Note(pitch: 60, duration: 60)), .note(Note(pitch: 60, duration: 240))])
        let pieces = DurationSplitter.split(part, slotsPerMeasure: 480)
        let bar1 = Array(0..<16)
        let beams = BeamGrouper.beams(pieces: pieces, indexes: bar1, slotsPerBeat: 120)
        XCTAssertEqual(beams.count, 4)
        for b in beams {
            XCTAssertEqual(b.pieces.count, 4)
            XCTAssertEqual(Set(b.pieces.map { pieces[$0].start / 120 }).count, 1)
        }
        // Bar 2: eighth, rest, eighth, half → the rest breaks the group, singles are not beamed.
        let bar2 = Array(16..<20)
        XCTAssertEqual(BeamGrouper.beams(pieces: pieces, indexes: bar2, slotsPerBeat: 120).count, 0)
    }

    // MARK: Layout

    func testThirtyTwoBarsFourPerLineGivesEightSystems() throws {
        let score = try LeadsheetParser.parse(contentsOf: LeadsheetDocumentTests.repoRoot.appending(path: "leadsheets/imaginary-book/SoWhat.ls"), vocabulary: vocab)
        var options = StaveOptions()
        options.width = 900
        options.measuresPerLine = 4
        let layout = StaveLayout.layout(score: score, options: options)
        XCTAssertEqual(layout.systems.count, 8)
        XCTAssertEqual(layout.measures.count, 32)
        XCTAssertEqual(layout.measures.map(\.frame.width).max()!, layout.measures.map(\.frame.width).min()!, accuracy: 0.001)
        XCTAssertGreaterThan(layout.height, 8 * 100)
        // Chord symbols: So What writes a chord every two bars (Dm7 | / | …).
        let chords = layout.glyphs.compactMap { g -> String? in if case let .chordSymbol(t, _, _) = g { return t } else { return nil } }
        XCTAssertEqual(chords.count, 16)
        XCTAssertEqual(chords[8], "Ebm7")
        // A clef per system, a time signature only on the first.
        XCTAssertEqual(layout.glyphs.filter { if case .clef = $0 { return true } else { return false } }.count, 8)
        XCTAssertEqual(layout.glyphs.filter { if case .timeSignature = $0 { return true } else { return false } }.count, 1)
    }

    func testHitTestingRoundTrips() {
        let score = Score.blank(measures: 8)
        var options = StaveOptions(); options.width = 800; options.measuresPerLine = 4
        let layout = StaveLayout.layout(score: score, options: options)
        for slot in stride(from: 0, to: 8 * 480, by: 60) {
            let x = layout.x(forSlot: slot)!
            let m = layout.measure(containingSlot: slot)!
            let point = CGPoint(x: x, y: layout.systems[m.system].staffTop + 16)
            XCTAssertEqual(layout.slot(at: point), slot)
        }
        // Playhead line spans the system.
        let line = layout.playheadLine(slot: 5 * 480)!
        XCTAssertEqual(line.top, layout.systems[1].frame.minY)
        // Diatonic under the middle line of the first staff is B4 (34).
        let mid = CGPoint(x: layout.measures[0].slotX0, y: layout.systems[0].staffTop + 16)
        XCTAssertEqual(layout.diatonic(at: mid)?.diatonic, 34)
        XCTAssertEqual(layout.rects(forSlots: 0..<(8 * 480)).count, 2)
    }

    func testMelodyGlyphsForTestTune() throws {
        let score = try LeadsheetParser.parse(contentsOf: LeadsheetDocumentTests.repoRoot.appending(path: "leadsheets/_test.ls"), vocabulary: vocab)
        let layout = StaveLayout.layout(score: score)
        let heads = layout.glyphs.filter { if case .noteHead = $0 { return true } else { return false } }.count
        let rests = layout.glyphs.filter { if case .rest = $0 { return true } else { return false } }.count
        let notePieces = layout.pieces.filter { !$0.isRest }.count
        XCTAssertEqual(heads, notePieces)
        XCTAssertEqual(rests, layout.pieces.filter(\.isRest).count)
        XCTAssertGreaterThan(heads, 100)
        // Key of G: the first f# needs no accidental glyph, but the c# does.
        let accidentals = layout.glyphs.filter { if case .accidental = $0 { return true } else { return false } }.count
        XCTAssertGreaterThan(accidentals, 0)
        XCTAssertTrue(layout.glyphs.contains { if case .tuplet = $0 { return true } else { return false } })
        XCTAssertTrue(layout.glyphs.contains { if case .beam = $0 { return true } else { return false } })
        XCTAssertTrue(layout.glyphs.contains { if case .sectionMarker("swing-SonnyClark", _, _) = $0 { return true } else { return false } })
    }

    func testGrandStaffSplitsAtBreakpoint() {
        var score = Score.blank(measures: 2)
        score.melodyParts[0] = MelodyPart(events: [.note(Note(pitch: 48, duration: 480)), .note(Note(pitch: 72, duration: 480))],
                                          info: PartInfo(stave: .grand))
        let layout = StaveLayout.layout(score: score)
        XCTAssertTrue(layout.isGrand)
        XCTAssertNotNil(layout.systems[0].bassStaffTop)
        let heads = layout.glyphs.compactMap { g -> CGFloat? in if case let .noteHead(_, y, _, _) = g { return y } else { return nil } }
        XCTAssertEqual(heads.count, 2)
        XCTAssertGreaterThan(heads[0], layout.systems[0].bassStaffTop!)   // low C on the bass staff
        XCTAssertLessThan(heads[1], layout.systems[0].staffTop + 32)       // high C on the treble staff
    }
}
