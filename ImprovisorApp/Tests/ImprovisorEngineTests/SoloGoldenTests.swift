//
//  SoloGoldenTests.swift
//  ImprovisorEngineTests
//
//  Differential harness for grammar solos: generate each case in
//  Testing/goldens/solo-cases.tsv with the Swift solo generator and compare
//  with what the Java original produced for the same tune, grammar and seed
//  (Testing/goldens/solo/<id>.solo.txt, from `GoldenDriver solo`).
//
//  The golden holds three stages (see GoldenDriver.solo):
//    # abstract …   the abstract melody from the grammar expansion
//    lick …         the notes after LickGen.fillMelody
//    rectified …    the chorus after pasting and rectifying — what the user gets
//
//  The comparison is on the final stage and is exact (slot, pitch or rest,
//  duration). The Swift generator is not yet a port of Java's (BUG_LOG O-06),
//  so this test is expected to fail until that port is done; it measures the gap.
//

import XCTest
@testable import ImprovisorEngine

final class SoloGoldenTests: XCTestCase {

    struct Unit: Equatable, CustomStringConvertible {
        var slot: Int
        var pitch: Int      // -1 = rest
        var duration: Int
        var description: String { "slot \(slot) \(pitch < 0 ? "rest" : "pitch \(pitch)") dur \(duration)" }
    }

    static func golden(_ id: String) throws -> (final: [Unit], lick: [Unit], abstract: String, threw: Bool) {
        let text = try TestData.contents("ImprovisorApp/Testing/goldens/solo/\(id).solo.txt")
        var final: [Unit] = [], lick: [Unit] = []
        var abstract = ""
        var threw = false
        for line in text.split(separator: "\n") {
            if line.hasPrefix("# abstract ") { abstract = String(line.dropFirst(11)) }
            if line.hasPrefix("# threw") || line.hasPrefix("# timeout") { threw = true }
            let f = line.split(separator: " ")
            guard f.count >= 4, let slot = Int(f[1]), let pitch = Int(f[2]), let dur = Int(f[3]) else { continue }
            if f[0] == "rectified" { final.append(Unit(slot: slot, pitch: pitch, duration: dur)) }
            if f[0] == "lick" { lick.append(Unit(slot: slot, pitch: pitch, duration: dur)) }
        }
        return (final, lick, abstract, threw)
    }

    static func units(_ part: MelodyPart) -> [Unit] {
        var out: [Unit] = []
        var slot = 0
        for event in part.events {
            switch event {
            case let .note(n): out.append(Unit(slot: slot, pitch: n.pitch, duration: n.duration))
            case let .rest(r): out.append(Unit(slot: slot, pitch: -1, duration: r.duration))
            }
            slot += event.duration
        }
        return out
    }

    static func cases() throws -> [[String]] {
        try TestData.contents("ImprovisorApp/Testing/goldens/solo-cases.tsv")
            .split(separator: "\n").filter { !$0.hasPrefix("#") }
            .map { $0.split(separator: "\t").map(String.init) }
    }

    /// Stage 1: the abstract melody from the grammar expansion
    /// (`JavaGrammarExpander`, port of Java `Grammar.run`) must equal Java's,
    /// terminal for terminal.
    func testAbstractMelodyMatchesJava() throws {
        var identical = 0, compared = 0
        var byGrammar: [String: (ok: Int, total: Int)] = [:]
        var report: [String] = []
        for c in try Self.cases() {
            let (id, leadsheet, grammarName, seed) = (c[0], c[1], c[2], Int64(c[3])!)
            guard let golden = try? Self.golden(id) else { continue }
            guard !golden.abstract.isEmpty else { continue }      // Java threw or timed out
            compared += 1
            let score = LeadsheetParser.parse(try TestData.contents(leadsheet), vocabulary: GoldenSupport.vocabulary)
            let grammar = try GrammarParser.parse(contentsOf: TestData.url("grammars/\(grammarName)"))
            var rng = JavaRandom(seed: seed)
            _ = rng.nextDouble()        // LickGen's field initializer draws once (prevPitch)
            var expander = JavaGrammarExpander(grammar: grammar, chords: score.chordPart)
            let terminals = expander.run(startSlot: 0, slots: score.chordPart.size + 1, rng: &rng)
            let mine = "(" + terminals.map(\.description).joined(separator: " ") + ")"
            var tally = byGrammar[grammarName] ?? (0, 0)
            tally.total += 1
            if mine == golden.abstract {
                identical += 1
                tally.ok += 1
            } else {
                let a = golden.abstract.split(separator: " "), b = mine.split(separator: " ")
                let i = (0..<min(a.count, b.count)).first { a[$0] != b[$0] } ?? min(a.count, b.count)
                report.append("=== \(id)\n  first difference at token \(i)\n  java : \(a.dropFirst(max(0, i - 3)).prefix(10).joined(separator: " "))\n  swift: \(b.dropFirst(max(0, i - 3)).prefix(10).joined(separator: " "))")
            }
            byGrammar[grammarName] = tally
        }
        CorpusSweepTests.writeReport("solo-abstract-diff.txt", report)
        let summary = byGrammar.sorted { $0.key < $1.key }
            .map { "  \($0.key): \($0.value.ok)/\($0.value.total)" }.joined(separator: "\n")
        print("SOLO STAGE 1 (abstract melody): \(identical)/\(compared) identical to Java\n\(summary)")
        XCTAssertEqual(identical, compared, "abstract melodies differ; see Testing/.build/reports/solo-abstract-diff.txt")
    }

    func testSolosMatchJavaGoldens() throws {
        let cases = try Self.cases().filter {
            FileManager.default.fileExists(atPath: TestData.path("ImprovisorApp/Testing/goldens/solo/\($0[0]).solo.txt"))
        }
        XCTAssertGreaterThanOrEqual(cases.count, 50)

        var identical = 0, javaThrew = 0
        var byGrammar: [String: (ok: Int, total: Int)] = [:]
        var report: [String] = []

        for c in cases {
            let (id, leadsheet, grammarName, seed) = (c[0], c[1], c[2], Int64(c[3])!)
            let golden = try Self.golden(id)
            if golden.threw { javaThrew += 1; continue }
            let score = LeadsheetParser.parse(try TestData.contents(leadsheet), vocabulary: GoldenSupport.vocabulary)
            let grammar = try GrammarParser.parse(contentsOf: TestData.url("grammars/\(grammarName)"))
            var solo = SoloGenerator(grammar: grammar).generate(chords: score.chordPart,
                                                                seed: UInt64(bitPattern: seed))
            solo.truncate(to: score.chordPart.size)
            let mine = Self.units(solo)

            var tally = byGrammar[grammarName] ?? (0, 0)
            tally.total += 1
            if mine == golden.final {
                identical += 1
                tally.ok += 1
            } else {
                let n = min(mine.count, golden.final.count)
                let i = (0..<n).first { mine[$0] != golden.final[$0] } ?? n
                let slot = i < golden.final.count ? golden.final[i].slot : (mine.last?.slot ?? 0)
                let bar = slot / max(1, score.meter.slotsPerMeasure) + 1
                let chord = score.chordPart.chord(at: slot)?.name ?? "?"
                report.append("""
                    === \(id)  (\(leadsheet), \(grammarName), seed \(seed))
                    first divergence at unit #\(i), bar \(bar), chord \(chord)
                      java : \(i < golden.final.count ? golden.final[i].description : "(no more units)")
                      swift: \(i < mine.count ? mine[i].description : "(no more units)")
                      java \(golden.final.count) units, swift \(mine.count) units
                    """)
            }
            byGrammar[grammarName] = tally
        }

        CorpusSweepTests.writeReport("solo-diff.txt", report)
        let compared = cases.count - javaThrew
        let summary = byGrammar.sorted { $0.key < $1.key }
            .map { "  \($0.key): \($0.value.ok)/\($0.value.total)" }.joined(separator: "\n")
        print("SOLO COMPARISON: \(identical)/\(compared) solos identical to Java (\(javaThrew) cases where Java threw)\n\(summary)")
        XCTAssertEqual(identical, compared,
                       "\(compared - identical) solos differ from Java; see Testing/.build/reports/solo-diff.txt")
    }
}
