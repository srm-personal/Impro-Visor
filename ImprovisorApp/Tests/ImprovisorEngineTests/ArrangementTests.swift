//
//  ArrangementTests.swift
//  ImprovisorEngineTests
//
//  Phase 2: My.voc scales, leadsheet style overrides, chord-part slicing, and
//  the section-aware ArrangementBuilder.
//

import XCTest
@testable import ImprovisorEngine

final class ArrangementTests: XCTestCase {

    static let vocabulary = Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    var vocab: Vocabulary { ArrangementTests.vocabulary }

    static let styles: StyleCatalog = {
        let names = ["swing", "ballad", "latin", "waltz", "latin-pedal-bass-1", "swing-SonnyClark", "swing-BarryHarris"]
        let loaded = names.compactMap { try? StyleParser.parse(contentsOf: TestData.url("styles/\($0).sty")) }
        return StyleCatalog(styles: loaded)
    }()

    // MARK: Scales

    func testScalesLoadFromVocabulary() {
        XCTAssertGreaterThan(vocab.scaleCount, 90)
        XCTAssertEqual(vocab.scale(named: "major")?.map(\.semitones), [0, 2, 4, 5, 7, 9, 11])
        XCTAssertEqual(vocab.scale(named: "major pentatonic")?.count, 5)
    }

    func testChordFormsCarryScaleReferences() {
        let cm7 = vocab.chordForm(named: "CM7")!
        XCTAssertEqual(cm7.scales.first, ScaleReference(root: PitchClass.named("c")!, type: "major"))
        XCTAssertTrue(cm7.scales.contains(ScaleReference(root: PitchClass.named("g")!, type: "major pentatonic")))
    }

    func testChordSymbolScaleTonesAreTransposed() {
        let dm7 = ChordSymbol.parse("Dm7", vocabulary: vocab)!
        XCTAssertFalse(dm7.scaleTones.isEmpty)
        // Whatever the preferred scale, it must contain the chord tones of Dm7.
        let scale = Set(dm7.scaleTones.map(\.semitones))
        for tone in dm7.chordTones { XCTAssertTrue(scale.contains(tone.semitones), "\(tone)") }
        // G7's first scale (mixolydian family) contains F, not F#.
        let g7 = ChordSymbol.parse("G7", vocabulary: vocab)!
        XCTAssertTrue(Set(g7.scaleTones.map(\.semitones)).contains(5))
    }

    func testBassScaleToneRuleUsesScaleTones() {
        // A style whose only bass rule is S (scale tones): every bass pitch must be
        // in the chord's preferred scale.
        let style = Style(name: "scaley", bassPatterns: [Pattern(rules: ["S4", "S4", "S4", "S4"], weight: 1)])
        var part = ChordPart()
        part.append(ChordSymbol.parse("G7", vocabulary: vocab)!, duration: 480 * 4)
        let acc = AccompanimentGenerator(style: style).generate(chordPart: part, seed: 3)
        let scale = Set(part.entries[0].symbol.scaleTones.map(\.semitones))
        XCTAssertEqual(acc.bass.count, 16)
        for n in acc.bass { XCTAssertTrue(scale.contains(n.pitch % 12), "pitch \(n.pitch)") }
    }

    // MARK: Style overrides

    func testStyleOverrideFromLeadsheet() throws {
        let score = try LeadsheetParser.parse(contentsOf: TestData.url("leadsheets/_test.ls"), vocabulary: vocab)
        let base = try StyleParser.parse(contentsOf: TestData.url("styles/latin-pedal-bass-1.sty"))
        let over = base.applying(override: score.styleOverride)
        XCTAssertEqual(over.swing, 0.55)
        XCTAssertEqual(over.compSwing, 0.55)
        XCTAssertEqual(over.bassLow, "g--")
        XCTAssertEqual(over.chordHigh, "a")
        XCTAssertEqual(over.bassPatterns, base.bassPatterns) // patterns untouched
        XCTAssertEqual(base.applying(override: nil), base)
    }

    // MARK: Slicing

    func testChordPartSlice() {
        var part = ChordPart()
        let c = ChordSymbol.parse("C", vocabulary: vocab)!, f = ChordSymbol.parse("F", vocabulary: vocab)!
        part.append(c, duration: 960)
        part.append(f, duration: 480)
        let slice = part.slice(480..<1200)
        XCTAssertEqual(slice.size, 720)
        let described: [String] = slice.entries.map { "\($0.symbol.name)@\($0.start)+\($0.duration)" }
        XCTAssertEqual(described, ["C@0+480", "F@480+240"])
        XCTAssertEqual(part.slice(0..<0).size, 0)
    }

    // MARK: ArrangementBuilder

    func testSectionsUseTheirOwnStyles() throws {
        // Two sections: bar 0-1 swing (walking bass), bar 2-3 ballad.
        let text = """
        (title T)(meter 4 4)(key 0)(tempo 120.0)(style swing)
        (part (type chords))
        C | F |
        (section (style ballad))
        G7 | C |
        """
        let score = LeadsheetParser.parse(text, vocabulary: vocab)
        let arr = ArrangementBuilder.build(score: score, styles: ArrangementTests.styles)
        XCTAssertEqual(arr.formSlots, 4 * 480)
        let bass = try XCTUnwrap(arr.tracks.first { $0.name == ArrangementBuilder.bassTrackName })
        let firstHalf = bass.notes.filter { $0.startTick < 960 }
        let secondHalf = bass.notes.filter { $0.startTick >= 960 }
        XCTAssertFalse(firstHalf.isEmpty); XCTAssertFalse(secondHalf.isEmpty)

        // Same tune all-swing vs. sectioned: the first half is identical (same
        // seed, same slice), the second half differs because ballad ≠ swing.
        var allSwing = score
        allSwing.sections = SectionInfo(records: [SectionRecord(measure: 0, styleName: "swing")])
        let ref = ArrangementBuilder.build(score: allSwing, styles: ArrangementTests.styles)
        let refBass = try XCTUnwrap(ref.tracks.first { $0.name == ArrangementBuilder.bassTrackName })
        XCTAssertNotEqual(refBass.notes.filter { $0.startTick >= 960 }, secondHalf)
        // Every note lies inside the form.
        for t in arr.tracks { for n in t.notes { XCTAssertLessThan(n.startTick, arr.formSlots) } }
    }

    func testTuneStyleAndOverridesAreHonored() throws {
        let score = try LeadsheetParser.parse(contentsOf: TestData.url("leadsheets/_test.ls"), vocabulary: vocab)
        let arr = ArrangementBuilder.build(score: score, styles: ArrangementTests.styles)
        XCTAssertEqual(arr.choruses, 1)
        XCTAssertEqual(arr.formSlots, 48 * 480)
        XCTAssertEqual(arr.masterVolume, 80)
        let names = Set(arr.tracks.map(\.name))
        XCTAssertEqual(names, ["Bass", "Chords", "Drums", "Melody"])
        let bass = arr.tracks.first { $0.name == "Bass" }!
        XCTAssertEqual(bass.program, 33)          // (bass-instrument 33)
        XCTAssertEqual(bass.volume, 100)          // (bass-volume 100)
        let melody = arr.tracks.first { $0.name == "Melody" }!
        XCTAssertEqual(melody.program, 11)        // part (instrument 11)
        XCTAssertEqual(melody.channel, 2)
        XCTAssertEqual(melody.volume, 85)         // min(melody-volume 127, part volume 85)
        XCTAssertEqual(melody.notes.count, score.melodyParts[0].noteCount)
        // Bass register respects the override (bass-low g-- = 43, bass-high c = 60).
        for n in bass.notes { XCTAssertTrue((43...60).contains(n.pitch), "bass pitch \(n.pitch)") }
    }

    func testChorusesRepeatTheFormAndSeedIsDeterministic() {
        let score = LeadsheetParser.parse("(meter 4 4)(style swing)(part (type chords))\nDm7 | G7 | C | C |", vocabulary: vocab)
        var options = ArrangementOptions()
        options.choruses = 3
        options.seed = 42
        let a = ArrangementBuilder.build(score: score, styles: ArrangementTests.styles, options: options)
        let b = ArrangementBuilder.build(score: score, styles: ArrangementTests.styles, options: options)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.totalSlots, 3 * 4 * 480)
        let drums = a.tracks.first { $0.name == "Drums" }!
        XCTAssertGreaterThan(drums.notes.filter { $0.startTick >= 2 * 1920 }.count, 0)
        XCTAssertTrue(drums.notes.allSatisfy { $0.startTick < a.totalSlots })

        options.seed = 43
        let c = ArrangementBuilder.build(score: score, styles: ArrangementTests.styles, options: options)
        let bassA: [ScheduledNote] = a.tracks.first { $0.name == "Bass" }!.notes
        let bassC: [ScheduledNote] = c.tracks.first { $0.name == "Bass" }!.notes
        XCTAssertNotEqual(bassA, bassC)
    }

    func testTrackTogglesAndStraightFeel() {
        let score = LeadsheetParser.parse("(meter 4 4)(style swing)(part (type chords))\nDm7 | G7 |", vocabulary: vocab)
        var options = ArrangementOptions()
        options.includeDrums = false
        options.includeChords = false
        let arr = ArrangementBuilder.build(score: score, styles: ArrangementTests.styles, options: options)
        XCTAssertEqual(arr.tracks.map(\.name), ["Bass"])

        options.applySwing = false
        let straight = ArrangementBuilder.build(score: score, styles: ArrangementTests.styles, options: options)
        // Straight eighths land on multiples of 60; swung ones may land on 80.
        XCTAssertTrue(straight.tracks[0].notes.allSatisfy { $0.startTick % 60 == 0 })
    }

    func testMIDIFileCarriesTrackVolume() {
        let track = MIDITrack(name: "T", channel: 0, program: 0,
                              notes: [ScheduledNote(pitch: 60, velocity: 90, startTick: 0, duration: 120, channel: 0)],
                              volume: 100)
        let data = MIDIFileWriter.data(tracks: [track], tempoBPM: 120)
        let bytes = [UInt8](data)
        // Controller 7 on channel 0 with value 100.
        var found = false
        for i in 0..<(bytes.count - 2) where bytes[i] == 0xB0 && bytes[i + 1] == 0x07 && bytes[i + 2] == 100 { found = true }
        XCTAssertTrue(found)
    }
}
