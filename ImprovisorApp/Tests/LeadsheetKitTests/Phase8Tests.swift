//
//  Phase8Tests.swift
//  LeadsheetKitTests
//
//  Generators spliced into the melody, section editing, playback transitions
//  through a recording backend, and the library index.
//

import XCTest
@testable import LeadsheetKit
@testable import ImprovisorEngine

final class RecordingBackend: InstrumentBackend, @unchecked Sendable {
    let lock = NSLock()
    private(set) var events: [String] = []
    var started = false
    func start() throws { started = true }
    func stop() { started = false }
    func programChange(_ program: UInt8, channel: UInt8) { record("prog \(program) ch\(channel)") }
    func noteOn(_ pitch: UInt8, velocity: UInt8, channel: UInt8) { record("on \(pitch) v\(velocity) ch\(channel)") }
    func noteOff(_ pitch: UInt8, channel: UInt8) { record("off \(pitch) ch\(channel)") }
    func allNotesOff() { record("allOff") }
    private func record(_ s: String) { lock.lock(); events.append(s); lock.unlock() }
    var noteOns: [String] { lock.lock(); defer { lock.unlock() }; return events.filter { $0.hasPrefix("on") } }
}

@MainActor
final class Phase8Tests: XCTestCase {

    let library = DataLibrary(root: LeadsheetDocumentTests.repoRoot)

    private func makeEditor(_ chords: String = "Dm7 | G7 | Cmaj7 | Cmaj7 |") -> EditorController {
        var score = LeadsheetParser.parse("(meter 4 4)(key 0)(style swing)(part (type chords))\n\(chords)", vocabulary: library.vocabulary)
        score.melodyParts = [MelodyPart(events: [.note(Note(pitch: 60, duration: 480, volume: 127)), .rest(Rest(duration: 3 * 480))])]
        let editor = EditorController(document: LeadsheetDocument(score: score))
        editor.auditions = false
        return editor
    }

    func testGenerateSoloOverSelectionPreservesTheRest() throws {
        let editor = makeEditor()
        let grammar = try XCTUnwrap(library.grammar(library.grammarNames.first { $0.lowercased().hasPrefix("bebop") } ?? library.grammarNames[0]))
        editor.select(range: 480..<1440)
        editor.generateSolo(grammar: grammar, seed: 7)
        XCTAssertEqual(editor.melody.size, 4 * 480)
        XCTAssertEqual(editor.melody.events(in: 0..<480), [.note(Note(pitch: 60, duration: 480, volume: 127))])
        XCTAssertEqual(editor.melody.events(in: 1440..<1920), [.rest(Rest(duration: 480))])
        XCTAssertGreaterThan(editor.melody.events(in: 480..<1440).filter { !$0.isRest }.count, 3)
        // Deterministic for a seed.
        let again = makeEditor(); again.select(range: 480..<1440); again.generateSolo(grammar: grammar, seed: 7)
        XCTAssertEqual(again.melody, editor.melody)
    }

    func testGenerateSoloChorusAndChorusManagement() throws {
        let editor = makeEditor()
        let grammar = try XCTUnwrap(library.grammar(library.grammarNames.first { $0.lowercased().hasPrefix("bebop") } ?? library.grammarNames[0]))
        editor.generateSoloChorus(grammar: grammar, seed: 3)
        XCTAssertEqual(editor.score.melodyParts.count, 2)
        XCTAssertEqual(editor.partIndex, 1)
        XCTAssertEqual(editor.melody.size, 4 * 480)
        XCTAssertEqual(editor.melody.info.title, "Chorus 2")
        editor.addChorus()
        XCTAssertEqual(editor.score.melodyParts.count, 3)
        XCTAssertEqual(editor.partIndex, 2)
        editor.removeChorus()
        XCTAssertEqual(editor.score.melodyParts.count, 2)
        // Round trips through the file.
        let text = LeadsheetWriter.leadsheet(score: editor.score)
        let back = LeadsheetParser.parse(text, vocabulary: library.vocabulary)
        for (i, (a, b)) in zip(editor.score.melodyParts, back.melodyParts).enumerated() {
            XCTAssertEqual(a.info, b.info, "part \(i) info")
            if let j = (0..<min(a.events.count, b.events.count)).first(where: { a.events[$0] != b.events[$0] }) {
                XCTFail("part \(i) event \(j): \(a.events[j]) vs \(b.events[j])")
            }
            XCTAssertEqual(a.events.count, b.events.count, "part \(i) count")
        }
        XCTAssertEqual(back.melodyParts.count, editor.score.melodyParts.count)
        XCTAssertEqual(back.chordPart, editor.score.chordPart)
        XCTAssertEqual(back.sections, editor.score.sections)
    }

    func testSectionEditingRoundTrips() {
        let editor = makeEditor()
        editor.setSection(atMeasure: 2, styleName: "ballad", isPhrase: false)
        editor.setSection(atMeasure: 3, styleName: "", isPhrase: true)
        XCTAssertEqual(editor.score.sections.records.map(\.measure), [0, 2, 3])
        XCTAssertEqual(editor.score.sections.styleName(atMeasure: 3, default: "x"), "ballad")
        editor.removeSection(atMeasure: 0)   // anchored: not removable
        XCTAssertEqual(editor.score.sections.records.count, 3)
        editor.removeSection(atMeasure: 3)
        XCTAssertEqual(editor.score.sections.records.map(\.measure), [0, 2])
        let text = LeadsheetWriter.leadsheet(score: editor.score)
        XCTAssertEqual(LeadsheetParser.parse(text, vocabulary: library.vocabulary).sections, editor.score.sections)
        // The arrangement honours the new section.
        let arr = ArrangementBuilder.build(score: editor.score, styles: library)
        XCTAssertFalse(arr.tracks.isEmpty)
    }

    func testPlaybackTransitionsWithRecordingBackend() {
        let backend = RecordingBackend()
        let playback = PlaybackController(library: library)
        playback.backendFactory = { backend }
        playback.countIn = false
        let score = makeEditor().score
        playback.play(score: score)
        XCTAssertTrue(playback.isPlaying); XCTAssertFalse(playback.isPaused)
        XCTAssertTrue(backend.started)
        XCTAssertEqual(playback.arrangement?.tracks.count, 4)
        let exp = expectation(description: "notes played")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exp.fulfill() }
        wait(for: [exp], timeout: 3)
        XCTAssertGreaterThan(backend.noteOns.count, 0)
        XCTAssertTrue(backend.events.contains { $0.hasPrefix("prog") })
        playback.togglePlayPause(score: score)
        XCTAssertTrue(playback.isPaused)
        playback.togglePlayPause(score: score)
        XCTAssertFalse(playback.isPaused)
        // Mixer: muting drums is applied live.
        playback.mixOverrides[9] = TrackMix(volume: 1, muted: true)
        XCTAssertTrue(playback.mix(forChannel: 9).muted)
        XCTAssertEqual(playback.mix(forChannel: 0).volume, Double(score.bassVolume) / 127, accuracy: 0.001)
        playback.stop()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertTrue(backend.events.contains("allOff"))
        playback.regenerate()
        XCTAssertTrue(playback.status.contains("seed"))
    }

    func testLibraryIndexCoversTheCorpus() {
        let index = library.libraryIndex()
        XCTAssertEqual(index.count, 3280)
        let soWhat = index.first { $0.fileName == "SoWhat" }
        XCTAssertEqual(soWhat?.title, "So What?")
        XCTAssertEqual(soWhat?.folder, "imaginary-book")
        XCTAssertEqual(index.first { $0.fileName == "_test" }?.folder, "")
        XCTAssertEqual(index.first { $0.fileName == "_test" }?.composer, "Jerry Brainin and Buddy Bernier")
        XCTAssertGreaterThan(index.filter { !$0.composer.isEmpty }.count, 2000)
        XCTAssertGreaterThanOrEqual(Set(index.map(\.folder)).count, 13)
        XCTAssertEqual(DataLibrary.headerValue("show", in: "(show Night Has a Thousand Eyes (film))\n(year 1948)"), "Night Has a Thousand Eyes (film)")
    }
}
