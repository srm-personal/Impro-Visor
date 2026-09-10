//
//  RoundTripTests.swift
//  ImprovisorEngineTests
//
//  Lossless `.ls` round trip (Phase 1): parse → write → parse yields an equal
//  Score for every shipped leadsheet, and the writer emits Java's structure.
//

import XCTest
@testable import ImprovisorEngine

final class RoundTripTests: XCTestCase {

    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()
    var vocab: Vocabulary { RoundTripTests.vocabulary }

    /// A human-readable description of the first place two scores differ.
    static func firstDifference(_ a: Score, _ b: Score) -> String? {
        if a.title != b.title { return "title \(a.title) vs \(b.title)" }
        if a.composer != b.composer { return "composer" }
        if a.showTitle != b.showTitle { return "show \(a.showTitle) vs \(b.showTitle)" }
        if a.year != b.year { return "year" }
        if a.comments != b.comments { return "comments \(a.comments) vs \(b.comments)" }
        if a.meter != b.meter { return "meter" }
        if a.key != b.key { return "key" }
        if a.tempo != b.tempo { return "tempo \(a.tempo) vs \(b.tempo)" }
        if a.volume != b.volume { return "volume" }
        if a.playbackTranspose != b.playbackTranspose { return "playback-transpose" }
        if a.chordFontSize != b.chordFontSize { return "chord-font-size" }
        if a.bassInstrument != b.bassInstrument { return "bass-instrument" }
        if a.bassVolume != b.bassVolume || a.drumVolume != b.drumVolume
            || a.chordVolume != b.chordVolume || a.melodyVolume != b.melodyVolume { return "volumes" }
        if a.breakpoint != b.breakpoint { return "breakpoint" }
        if a.layout != b.layout { return "layout \(a.layout) vs \(b.layout)" }
        if a.roadmapLayout != b.roadmapLayout { return "roadmap-layout" }
        if a.styleName != b.styleName { return "style \(a.styleName) vs \(b.styleName)" }
        if a.styleOverride != b.styleOverride { return "style override \(String(describing: a.styleOverride)) vs \(String(describing: b.styleOverride))" }
        if a.unknownForms != b.unknownForms { return "unknown forms" }
        if a.sections != b.sections { return "sections \(a.sections.records) vs \(b.sections.records)" }
        if a.chordPart.info != b.chordPart.info { return "chord part info" }
        if a.chordPart.size != b.chordPart.size { return "chord size \(a.chordPart.size) vs \(b.chordPart.size)" }
        for (x, y) in zip(a.chordPart.entries, b.chordPart.entries) where x != y {
            return "chord \(x.symbol.name)@\(x.start)+\(x.duration) vs \(y.symbol.name)@\(y.start)+\(y.duration)"
        }
        if a.chordPart.count != b.chordPart.count { return "chord count \(a.chordPart.count) vs \(b.chordPart.count)" }
        if a.melodyParts.count != b.melodyParts.count { return "melody part count \(a.melodyParts.count) vs \(b.melodyParts.count)" }
        for (i, (p, q)) in zip(a.melodyParts, b.melodyParts).enumerated() where p != q {
            if p.info != q.info { return "melody \(i) info \(p.info) vs \(q.info)" }
            for (j, (e, f)) in zip(p.events, q.events).enumerated() where e != f {
                return "melody \(i) event \(j): \(e) vs \(f)"
            }
            return "melody \(i) count \(p.count) vs \(q.count)"
        }
        return a == b ? nil : "unknown difference"
    }

    func testCorpusRoundTrip() throws {
        let files = TestData.files(under: "leadsheets", ext: "ls")
        XCTAssertGreaterThan(files.count, 3000)
        var failures: [String] = []
        var melodyNotes = 0
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            let first = LeadsheetParser.parse(text, vocabulary: vocab)
            let written = LeadsheetWriter.leadsheet(score: first)
            let second = LeadsheetParser.parse(written, vocabulary: vocab)
            melodyNotes += first.melodyParts.reduce(0) { $0 + $1.noteCount }
            if let diff = RoundTripTests.firstDifference(first, second) {
                failures.append("\(url.lastPathComponent): \(diff)")
            }
        }
        XCTAssertGreaterThan(melodyNotes, 100_000)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) files differ:\n" + failures.prefix(15).joined(separator: "\n"))
    }

    func testWrittenLeadsheetIsStableOnSecondWrite() throws {
        let score = try LeadsheetParser.parse(contentsOf: TestData.url("leadsheets/_test.ls"), vocabulary: vocab)
        let once = LeadsheetWriter.leadsheet(score: score)
        let twice = LeadsheetWriter.leadsheet(score: LeadsheetParser.parse(once, vocabulary: vocab))
        XCTAssertEqual(once, twice)
    }

    func testTestLeadsheetMetadataAndSections() throws {
        let score = try LeadsheetParser.parse(contentsOf: TestData.url("leadsheets/_test.ls"), vocabulary: vocab)
        XCTAssertEqual(score.title, "The Night Has a Thousand Eyes")
        XCTAssertEqual(score.showTitle, "Night Has a Thousand Eyes (film)")
        XCTAssertEqual(score.year, "1948")
        XCTAssertEqual(score.key.index, 1)
        XCTAssertEqual(score.tempo, 200)
        XCTAssertEqual(score.volume, 80)
        XCTAssertEqual(score.playbackTranspose, Transposition(bass: 0, chords: 0, melody: 0))
        XCTAssertEqual(score.chordFontSize, 16)
        XCTAssertEqual(score.bassInstrument, 33)
        XCTAssertEqual(score.bassVolume, 100)
        XCTAssertEqual(score.breakpoint, 54)
        XCTAssertEqual(score.layout, [4])
        XCTAssertEqual(score.roadmapLayout, 8)
        XCTAssertEqual(score.melodyVolume, 127)
        XCTAssertEqual(score.styleName, "latin-pedal-bass-1")
        XCTAssertEqual(score.styleOverride?.assoc("swing")?.secondOrNil()?.doubleValue, 0.55)
        XCTAssertEqual(score.styleOverride?.assoc("voicing-name")?.secondOrNil()?.symbolValue, "default.fv")

        XCTAssertEqual(score.chordPart.info.volume, 100)
        XCTAssertEqual(score.chordPart.info.key, 1)
        XCTAssertEqual(score.measureCount, 48)
        XCTAssertEqual(score.sections.records.map(\.measure), [0, 8, 16, 24])
        XCTAssertEqual(score.sections.records.map(\.styleName),
                       ["latin-pedal-bass-1", "swing-SonnyClark", "latin-pedal-bass-1", "swing-BarryHarris"])
        XCTAssertTrue(score.sections.records.allSatisfy { !$0.isPhrase })

        let melody = try XCTUnwrap(score.melodyParts.first)
        XCTAssertEqual(melody.info.title, "Chorus 1")
        XCTAssertEqual(melody.info.composer, "Bob Keller")
        XCTAssertEqual(melody.info.instrument, 11)
        XCTAssertEqual(melody.info.volume, 85)
        XCTAssertEqual(melody.info.stave, .treble)
        // First notes: d+4+8 b8 a8 g8 f#8 c#8
        XCTAssertEqual(melody.events.first, .note(Note(pitch: 74, duration: 180, volume: 127)))
        XCTAssertEqual(melody.events[4], .note(Note(pitch: 66, duration: 60, volume: 127, spelling: .sharp)))
    }

    func testPhraseMarkersAndUsePreviousStyle() {
        let text = """
        (title T)(meter 4 4)(key 0)(tempo 120.0)(style swing)
        (part (type chords))
        (section (style swing))
        C | F |
        (phrase (style))
        G7 | C |
        (section (style ballad))
        Dm7 G7 | C |
        """
        let score = LeadsheetParser.parse(text, vocabulary: vocab)
        XCTAssertEqual(score.sections.records, [
            SectionRecord(measure: 0, styleName: "swing", isPhrase: false),
            SectionRecord(measure: 2, styleName: "", isPhrase: true),
            SectionRecord(measure: 4, styleName: "ballad", isPhrase: false)
        ])
        XCTAssertEqual(score.sections.styleName(atMeasure: 3, default: "x"), "swing")
        XCTAssertEqual(score.sections.styleName(atMeasure: 5, default: "x"), "ballad")

        let written = LeadsheetWriter.leadsheet(score: score)
        XCTAssertTrue(written.contains("(phrase (style)) "))
        XCTAssertTrue(written.contains("(section (style ballad)) "))
        XCTAssertEqual(LeadsheetParser.parse(written, vocabulary: vocab), score)
    }

    func testHeaderOrderMatchesJava() {
        let written = LeadsheetWriter.leadsheet(score: Score(title: "X"))
        let heads = written.split(separator: "\n").prefix(20).map { $0.split(separator: " ").first.map(String.init) ?? String($0) }
        XCTAssertEqual(heads, ["(title", "(composer", "(show", "(year", "(comments", "(meter", "(key", "(tempo",
                               "(volume", "(playback-transpose", "(chord-font-size", "(bass-instrument",
                               "(bass-volume", "(drum-volume", "(chord-volume", "(breakpoint", "(layout)",
                               "(roadmap-layout", "(melody-volume", "(style"])
        // Tempo is written as a Double so the Java reader accepts it.
        XCTAssertTrue(written.contains("(tempo 160.0)"))
    }

    func testChordCellsUseFewestSubdivisions() {
        var part = ChordPart()
        let c = ChordSymbol.parse("C", vocabulary: vocab)!, g = ChordSymbol.parse("G7", vocabulary: vocab)!
        part.append(c, duration: 360)          // three beats
        part.append(g, duration: 120 + 480)    // last beat, then a whole bar
        XCTAssertEqual(LeadsheetWriter.chordCells(part, measure: 0, slotsPerBar: 480), ["C", "/", "/", "G7"])
        XCTAssertEqual(LeadsheetWriter.chordCells(part, measure: 1, slotsPerBar: 480), ["/"])
        XCTAssertEqual(LeadsheetWriter.progressionText(part, meter: .fourFour), "C / / G7 | / |")
    }

    func testPartialFinalBarIsFleshedOut() {
        let score = LeadsheetParser.parse("(meter 4 4)(part (type chords))\nC | F G7", vocabulary: vocab)
        XCTAssertEqual(score.chordPart.size, 960)
        XCTAssertEqual(score.chordPart.entries.map(\.duration), [480, 240, 240])
    }

    func testUnknownFormsSurvive() {
        let text = "(title T)(meter 4 4)(mystery 1 (nested x))(style swing)(part (type chords))\nC |"
        let score = LeadsheetParser.parse(text, vocabulary: vocab)
        XCTAssertEqual(score.unknownForms.count, 1)
        let written = LeadsheetWriter.leadsheet(score: score)
        XCTAssertTrue(written.contains("(mystery 1 (nested x))"), written)
        XCTAssertEqual(LeadsheetParser.parse(written, vocabulary: vocab), score)
    }
}
