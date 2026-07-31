//
//  VoicingTests.swift
//  ImprovisorEngineTests
//
//  Step 6 coverage: the .fv parser, the vocabulary voicer, the algorithmic
//  generator, and their integration into the accompaniment engine.
//

import XCTest
@testable import ImprovisorEngine

final class VoicingTests: XCTestCase {

    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()
    var vocab: Vocabulary { VoicingTests.vocabulary }

    private func chord(_ name: String) -> ChordSymbol {
        ChordSymbol.parse(name, vocabulary: vocab)!
    }

    // MARK: - .fv parser

    func testParsesFullPresetWithMultipliersAndFlags() throws {
        let s = try VoicingParser.parse(contentsOf: TestData.url("voicings/default.fv"))
        // Plain integers.
        XCTAssertEqual(s.leftHandLowerLimit, 46)
        XCTAssertEqual(s.rightHandUpperLimit, 81)
        XCTAssertEqual(s.leftHandUpperLimit, 55)   // default.fv, not the struct default (67)
        // Multipliers are stored *10 in the file and decoded /10.
        XCTAssertEqual(s.previousVoicingMultiplier, 4.0, accuracy: 1e-9)   // (… 40)
        XCTAssertEqual(s.halfStepAwayMultiplier, 3.0, accuracy: 1e-9)      // (… 30)
        XCTAssertEqual(s.fullStepReducer, 0.7, accuracy: 1e-9)            // (… 7)
        // Booleans.
        XCTAssertFalse(s.invertM9)
        XCTAssertFalse(s.voiceAll)
        // Back-compat raw subscript still works.
        XCTAssertEqual(s["LH-lower-limit"], 46)
    }

    func testParsesRootlessFlag() throws {
        let s = try VoicingParser.parse(contentsOf: TestData.url("voicings/Shell.fv"))
        XCTAssertTrue(s.rootless)
        XCTAssertEqual(s.leftHandMinNotes, 0)
        XCTAssertEqual(s.rightMinInterval, 6)
    }

    // MARK: - Vocabulary voicings / priority

    func testVocabularyParsesVoicingsAndPriority() {
        let cm = vocab.chordForm(named: "CM")!
        XCTAssertEqual(cm.voicings.count, 7)
        let lhA = cm.voicings.first { $0.name == "left-hand-A" }!
        XCTAssertEqual(lhA.type, "closed")
        XCTAssertEqual(lhA.notes, [52, 55, 60])       // e-8 g-8 c8
        XCTAssertEqual(cm.priority.map(\.semitones), [4, 7, 0])  // e g c
    }

    func testVoicingsTransposeToRoot() {
        // Dm7 left-hand voicing = CM7-family voicing transposed up 2 semitones.
        let dm7 = vocab.chordForm(named: "Cm7")!
        let rooted = dm7.voicings(root: PitchClass.named("d")!)
        for (orig, moved) in zip(dm7.voicings, rooted) {
            XCTAssertEqual(moved.notes, orig.notes.map { $0 + 2 })
        }
    }

    // MARK: - VoicingDistanceCalculator

    func testDistanceIsSymmetricMaxOfDirectedSums() {
        XCTAssertEqual(VoicingDistanceCalculator.distance([60, 64, 67], [60, 64, 67]), 0)
        // Each note of [61,65,68] is 1 semitone from [60,64,67]: directed sum 3.
        XCTAssertEqual(VoicingDistanceCalculator.distance([60, 64, 67], [61, 65, 68]), 3)
        XCTAssertEqual(VoicingDistanceCalculator.notesChanged([60, 64, 67], [60, 64, 70]), 1)
        XCTAssertEqual(VoicingDistanceCalculator.distance([], [60]), 0)
    }

    // MARK: - Vocabulary voicer voice-leading

    /// Voice a progression with the vocabulary voicer, threading each chord's
    /// voicing into the next as the previous voicing.
    private func voiceProgression(_ names: [String], type: String,
                                  low: Int, high: Int, seed: UInt64) -> [[Int]] {
        var rng = SeededGenerator(seed: seed)
        var previous: [Int] = []
        var result: [[Int]] = []
        for name in names {
            let v = VocabularyVoicer.findVoicing(chord: chord(name), previous: previous,
                                                 low: low, high: high, type: type, rng: &rng) ?? []
            result.append(v)
            if !v.isEmpty { previous = v }
        }
        return result
    }

    private func totalMotion(_ voicings: [[Int]]) -> Int {
        zip(voicings, voicings.dropFirst())
            .reduce(0) { $0 + VoicingDistanceCalculator.distance($1.0, $1.1) }
    }

    func testVocabularyVoicerStaysInRegister() {
        let voicings = voiceProgression(["Dm7", "G7", "Cmaj7", "Cmaj7"],
                                        type: "open", low: 49, high: 69, seed: 7)
        for v in voicings {
            XCTAssertFalse(v.isEmpty)
            XCTAssertTrue(v.allSatisfy { $0 >= 49 && $0 <= 69 }, "voicing out of register: \(v)")
        }
    }

    /// Voice a progression with voice-leading disabled: each chord is chosen
    /// without reference to the previous one (`previous` reset to empty), so the
    /// leap-minimizing selection has nothing to minimize against.
    private func voiceProgressionNoLeading(_ names: [String], type: String,
                                           low: Int, high: Int, seed: UInt64) -> [[Int]] {
        var rng = SeededGenerator(seed: seed)
        return names.map { name in
            VocabularyVoicer.findVoicing(chord: chord(name), previous: [],
                                         low: low, high: high, type: type, rng: &rng) ?? []
        }
    }

    func testVoiceLeadingReducesMotionVersusNoLeading() {
        // Within the same (open) vocabulary candidate set, threading the previous
        // voicing should, on average across seeds, move less than choosing each
        // chord independently. (Java's chooser is only a loose minimizer, so we
        // compare means rather than any single seed.)
        let names = ["Dm7", "G7", "Cmaj7", "Am7", "Dm7", "G7", "Cmaj7"]
        let seeds: [UInt64] = Array(1...60)
        func mean(_ leading: Bool) -> Double {
            let total = seeds.reduce(0) { sum, s in
                let v = leading
                    ? voiceProgression(names, type: "open", low: 49, high: 69, seed: s)
                    : voiceProgressionNoLeading(names, type: "open", low: 49, high: 69, seed: s)
                return sum + totalMotion(v)
            }
            return Double(total) / Double(seeds.count)
        }
        XCTAssertLessThan(mean(true), mean(false),
                          "voice-leading should reduce average motion vs. no leading")
    }

    // MARK: - Algorithmic generator

    private func generatorVoicing(root: Int, priority: [Int], color: [Int],
                                  previous: [Int]?, settings: VoicingSettings,
                                  seed: UInt64) -> [Int] {
        var rng = SeededGenerator(seed: seed)
        var hand = HandManager(settings: settings)
        var vgen = VoicingGenerator()
        vgen.apply(settings: settings)
        hand.repositionHands(rng: &rng)
        vgen.apply(hand: &hand, rng: &rng)
        vgen.root = root
        vgen.priority = priority
        vgen.color = color
        vgen.previousVoicing = previous
        vgen.calculate(rng: &rng)
        return vgen.chord.sorted()
    }

    func testGeneratorIsDeterministicForSeed() throws {
        let s = try VoicingParser.parse(contentsOf: TestData.url("voicings/default.fv"))
        let dm7 = [62, 65, 69, 72]  // D F A C
        let a = generatorVoicing(root: 2, priority: dm7, color: [], previous: nil, settings: s, seed: 99)
        let b = generatorVoicing(root: 2, priority: dm7, color: [], previous: nil, settings: s, seed: 99)
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isEmpty)
    }

    func testGeneratorNotesWithinHandLimits() throws {
        let s = try VoicingParser.parse(contentsOf: TestData.url("voicings/default.fv"))
        let dm7 = [62, 65, 69, 72]
        let v = generatorVoicing(root: 2, priority: dm7, color: [50, 55], previous: nil, settings: s, seed: 5)
        // default.fv: LH-lower 46, RH-upper 81.
        XCTAssertTrue(v.allSatisfy { $0 >= 46 && $0 <= 81 }, "out of hand range: \(v)")
    }

    func testGeneratorUsesChordTones() throws {
        let s = try VoicingParser.parse(contentsOf: TestData.url("voicings/default.fv"))
        let dm7Pcs: Set<Int> = [2, 5, 9, 0]  // D F A C
        let v = generatorVoicing(root: 2, priority: [62, 65, 69, 72], color: [],
                                 previous: nil, settings: s, seed: 11)
        XCTAssertTrue(v.allSatisfy { dm7Pcs.contains(($0 % 12 + 12) % 12) },
                      "generator produced non-chord tones: \(v)")
    }

    // MARK: - Accompaniment integration

    private func iiVI() -> ChordPart {
        var part = ChordPart()
        let m = Meter.fourFour.slotsPerMeasure
        for name in ["Dm7", "G7", "Cmaj7", "Cmaj7"] {
            part.append(chord(name), duration: m)
        }
        return part
    }

    func testCustomVoicingStyleUsesGeneratorWithinPresetRange() throws {
        var style = try StyleParser.parse(contentsOf: TestData.url("styles/swing.sty"))
        style.voicingType = "custom"
        let settings = try VoicingParser.parse(contentsOf: TestData.url("voicings/default.fv"))
        let gen = AccompanimentGenerator(style: style, voicingSettings: settings)
        let acc = gen.generate(chordPart: iiVI(), seed: 21)
        XCTAssertGreaterThan(acc.chords.count, 0)
        // Every chord note within the preset's overall hand range [46, 81].
        for note in acc.chords {
            XCTAssertGreaterThanOrEqual(note.pitch, 46)
            XCTAssertLessThanOrEqual(note.pitch, 81)
            XCTAssertEqual(note.channel, AccompanimentGenerator.chordChannel)
        }
    }

    func testAccompanimentChordVoicingIsDeterministic() throws {
        let style = try StyleParser.parse(contentsOf: TestData.url("styles/swing.sty"))
        let gen = AccompanimentGenerator(style: style)
        let a = gen.generate(chordPart: iiVI(), seed: 2024)
        let b = gen.generate(chordPart: iiVI(), seed: 2024)
        XCTAssertEqual(a.chords, b.chords)
    }

    /// Voice a spread of real leadsheets end-to-end: nothing crashes and every
    /// generated note is a valid MIDI value. Guards the voicer against corpus
    /// edge cases (unusual chords, forms without authored voicings, etc.).
    func testVoicesCorpusLeadsheetsWithoutCrashingOrInvalidMidi() throws {
        let swing = try StyleParser.parse(contentsOf: TestData.url("styles/swing.sty"))
        let gen = AccompanimentGenerator(style: swing)
        let leadsheets = TestData.files(under: "leadsheets/imaginary-book", ext: "ls")
            .sorted { $0.path < $1.path }
            .prefix(25)
        XCTAssertGreaterThan(leadsheets.count, 0)

        for url in leadsheets {
            let score = try LeadsheetParser.parse(contentsOf: url, vocabulary: vocab)
            guard score.chordPart.size > 0 else { continue }
            let acc = gen.generate(chordPart: score.chordPart, seed: 42)
            for note in acc.chords {
                XCTAssertTrue((0...127).contains(note.pitch),
                              "invalid MIDI \(note.pitch) in \(url.lastPathComponent)")
            }
        }
    }
}
