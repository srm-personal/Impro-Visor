//
//  ModelTests.swift
//  ImprovisorEngineTests
//
//  Step 2 coverage: pitch classes, durations, note parsing, keys, and the
//  chord vocabulary / ChordSymbol resolution against the real My.voc.
//

import XCTest
@testable import ImprovisorEngine

final class ModelTests: XCTestCase {

    // MARK: Shared vocabulary (loaded once from the real vocab file)

    static let vocabulary: Vocabulary = {
        let source = try! TestData.contents("vocab/My.voc")
        return Vocabulary(source: source)
    }()
    var vocab: Vocabulary { ModelTests.vocabulary }

    // MARK: PitchClass

    func testPitchClassSemitones() {
        XCTAssertEqual(PitchClass.named("c")?.semitones, 0)
        XCTAssertEqual(PitchClass.named("f#")?.semitones, 6)
        XCTAssertEqual(PitchClass.named("bb")?.semitones, 10)
        XCTAssertEqual(PitchClass.named("db")?.semitones, 1)
        XCTAssertEqual(PitchClass.named("eb")?.semitones, PitchClass.named("d#")?.semitones)
        XCTAssertNil(PitchClass.named("h"))
    }

    func testPitchClassTranspose() {
        XCTAssertEqual(PitchClass.named("c")!.transposed(by: 2).semitones, 2) // C -> D
        XCTAssertEqual(PitchClass.named("b")!.transposed(by: 1).semitones, 0) // B -> C
    }

    // MARK: Duration

    func testDurationParsing() {
        XCTAssertEqual(Duration.slots("4"), 120)   // quarter
        XCTAssertEqual(Duration.slots("8"), 60)    // eighth
        XCTAssertEqual(Duration.slots("1"), 480)   // whole
        XCTAssertEqual(Duration.slots("2"), 240)   // half
        XCTAssertEqual(Duration.slots("2."), 360)  // dotted half
        XCTAssertEqual(Duration.slots("8/3"), 40)  // eighth triplet
        XCTAssertEqual(Duration.slots("1+1+2"), 480 + 480 + 240) // additive
    }

    func testTripletsFillABeat() {
        // Three eighth-note triplets should sum to a quarter note.
        XCTAssertEqual(3 * Duration.slots("8/3"), Duration.slots("4"))
    }

    // MARK: NoteSymbol parsing

    func testNoteParsing() {
        guard case let .note(n)? = NoteSymbol.parse("c4") else { return XCTFail() }
        XCTAssertEqual(n.pitch, 60)          // middle C
        XCTAssertEqual(n.duration, 120)      // quarter

        guard case let .note(a)? = NoteSymbol.parse("a-8") else { return XCTFail() }
        XCTAssertEqual(a.pitch, 60 + 9 - 12) // A below middle C = 57
        XCTAssertEqual(a.duration, 60)

        guard case let .note(up)? = NoteSymbol.parse("c+2") else { return XCTFail() }
        XCTAssertEqual(up.pitch, 72)         // C an octave up
    }

    func testRestParsing() {
        guard case let .rest(r)? = NoteSymbol.parse("r8") else { return XCTFail() }
        XCTAssertEqual(r.duration, 60)
    }

    func testNoteTransposition() {
        let c4 = Note(pitch: 60, duration: 120)
        XCTAssertEqual(c4.transposed(by: 2).pitch, 62)
    }

    // MARK: Key

    func testKeySignature() {
        XCTAssertEqual(Key(index: 0).sharps, 0)
        XCTAssertEqual(Key(index: 0).flats, 0)
        XCTAssertEqual(Key(index: 1).sharps, 1)   // G major
        XCTAssertEqual(Key(index: -1).flats, 1)   // F major
        XCTAssertEqual(Key(index: 1).tonic.semitones, 7)  // G
        XCTAssertEqual(Key(index: -1).tonic.semitones, 5) // F
    }

    // MARK: Vocabulary / ChordForm

    func testVocabularyLoaded() {
        // My.voc defines 114 spelled chord forms and 120 (same …) alias
        // entries, two of which are duplicate names (Csus4, C7b9sus4) → 118 keys.
        XCTAssertEqual(vocab.formCount, 114)
        XCTAssertEqual(vocab.aliasCount, 118)
        XCTAssertNotNil(vocab.chordForm(named: "CM7"))
        // maj7 is an alias of CM7.
        XCTAssertEqual(vocab.chordForm(named: "Cmaj7"), vocab.chordForm(named: "CM7"))
    }

    // MARK: ChordSymbol resolution

    func testChordSymbolDm7() {
        guard let dm7 = ChordSymbol.parse("Dm7", vocabulary: vocab) else { return XCTFail() }
        XCTAssertEqual(dm7.root.semitones, 2)   // D
        XCTAssertEqual(dm7.type, "m7")
        // D minor 7 = D F A C
        XCTAssertEqual(Set(dm7.chordTones.map(\.semitones)), [2, 5, 9, 0])
        XCTAssertEqual(dm7.bass.semitones, 2)   // no slash: bass == root
    }

    func testChordSymbolC7() {
        guard let c7 = ChordSymbol.parse("C7", vocabulary: vocab) else { return XCTFail() }
        // C7 = C E G Bb
        XCTAssertEqual(Set(c7.chordTones.map(\.semitones)), [0, 4, 7, 10])
    }

    func testSlashChord() {
        guard let cOverE = ChordSymbol.parse("C/E", vocabulary: vocab) else { return XCTFail() }
        XCTAssertEqual(cOverE.root.semitones, 0)  // C
        XCTAssertEqual(cOverE.bass.semitones, 4)  // E in the bass
        XCTAssertEqual(Set(cOverE.chordTones.map(\.semitones)), [0, 4, 7])
    }

    func testNoChord() {
        guard let nc = ChordSymbol.parse("NC", vocabulary: vocab) else { return XCTFail() }
        XCTAssertTrue(nc.isNoChord)
        XCTAssertTrue(nc.chordTones.isEmpty)
    }

    // MARK: Coloration

    func testColoration() {
        let cmaj7 = ChordSymbol.parse("CM7", vocabulary: vocab)!
        XCTAssertEqual(Coloration.classify(pitch: 60, chord: cmaj7), .chord)   // C
        XCTAssertEqual(Coloration.classify(pitch: 62, chord: cmaj7), .color)   // D (9th, color)
        XCTAssertEqual(Coloration.classify(pitch: 61, chord: cmaj7, isApproach: true), .approach) // Db
        XCTAssertEqual(Coloration.classify(pitch: 61, chord: cmaj7), .foreign)  // Db, no context
    }

    // MARK: ChordPart container

    func testChordPart() {
        var part = ChordPart()
        part.append(ChordSymbol.parse("Dm7", vocabulary: vocab)!, duration: 480)
        part.append(ChordSymbol.parse("G7", vocabulary: vocab)!, duration: 480)
        XCTAssertEqual(part.size, 960)
        XCTAssertEqual(part.chord(at: 0)?.name, "Dm7")
        XCTAssertEqual(part.chord(at: 479)?.name, "Dm7")
        XCTAssertEqual(part.chord(at: 480)?.name, "G7")
        XCTAssertNil(part.chord(at: 960))
    }
}
