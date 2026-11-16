//
//  CorpusSweepTests.swift
//  ImprovisorEngineTests
//
//  Differential harness, Step 1: run every shipped data file through the Swift
//  parsers and compare what was parsed against what the original Java parser
//  reports for the same file (Testing/goldens/parse/*.tsv, produced by
//  Testing/scripts/generate_goldens.sh).
//
//  Failures are grouped by the FIELD that differs, not by file — hundreds of
//  files failing the same way are one bug. The full per-file list is written to
//  Testing/.build/reports/.
//

import XCTest
@testable import ImprovisorEngine

final class CorpusSweepTests: XCTestCase {

    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()

    static func goldenLines(_ name: String) throws -> [[String]] {
        let text = try TestData.contents("ImprovisorApp/Testing/goldens/parse/\(name)")
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("#") }
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    }

    static func writeReport(_ name: String, _ lines: [String]) {
        let dir = TestData.url("ImprovisorApp/Testing/.build/reports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: dir.appendingPathComponent(name),
                                                 atomically: true, encoding: .utf8)
    }

    /// Java prints doubles like `160.0`; match that for whole numbers.
    static func javaDouble(_ d: Double) -> String {
        d == d.rounded() && abs(d) < 1e15 ? String(format: "%.1f", d) : "\(d)"
    }

    // MARK: Leadsheets vs Java

    func testLeadsheetCountsMatchJava() throws {
        let golden = try Self.goldenLines("leadsheet-counts.tsv")
        XCTAssertGreaterThan(golden.count, 3000)
        // field name -> files that differ on it
        var groups: [String: [String]] = [:]
        var report: [String] = []
        var clean = 0

        for row in golden {
            let path = row[0]
            guard row.count >= 11, row[1] == "ok" else {
                groups["java-did-not-parse", default: []].append(path)
                continue
            }
            guard let content = try? TestData.contents(path) else {
                groups["swift-cannot-read-file (encoding)", default: []].append(path)
                report.append("\(path)\tswift-cannot-read-file")
                continue
            }
            let score = LeadsheetParser.parse(content, vocabulary: Self.vocabulary)
            let chords = score.chordPart
            let parts = score.melodyParts.map { p -> String in
                let rests = p.events.filter(\.isRest).count
                return "\(p.size):\(p.noteCount):\(rests)"
            }.joined(separator: " ")
            let first = chords.entries.prefix(6).map { "\($0.symbol.name)/\($0.duration)" }
                .joined(separator: " ")
            let mine: [(String, String)] = [
                ("metre", "\(score.meter.numerator)/\(score.meter.denominator)"),
                ("tempo", Self.javaDouble(score.tempo)),
                ("key", "\(score.key.index)"),
                ("chordSlots", "\(chords.size)"),
                ("chordUnits", "\(chords.count)"),
                ("sections", "\(score.sections.count)"),
                ("melodyParts", "\(score.melodyParts.count)"),
                ("melodyPartDetail", parts),
                ("firstChords", first),
            ]
            var bad: [String] = []
            for (i, (field, value)) in mine.enumerated() where row[i + 2] != value {
                bad.append(field)
                report.append("\(path)\t\(field)\tjava=\(row[i + 2])\tswift=\(value)")
            }
            if bad.isEmpty { clean += 1 }
            // Attribute the file to its FIRST differing field so the group
            // sizes add up to the number of failing files.
            if let f = bad.first { groups[f, default: []].append(path) }
        }

        Self.writeReport("leadsheet-counts-diff.tsv", report)
        let summary = groups.sorted { $0.value.count > $1.value.count }
            .map { "  \($0.key): \($0.value.count) files, e.g. \($0.value.prefix(3).joined(separator: ", "))" }
            .joined(separator: "\n")
        print("LEADSHEET SWEEP: \(clean)/\(golden.count) match Java\n\(summary)")
        XCTAssertTrue(groups.isEmpty, "leadsheet parse differs from Java in \(golden.count - clean) files:\n\(summary)")
    }

    // MARK: Leadsheet round trip

    func testLeadsheetRoundTripAllFiles() throws {
        var groups: [String: [String]] = [:]
        var total = 0
        for row in try Self.goldenLines("leadsheet-counts.tsv") {
            guard let content = try? TestData.contents(row[0]) else { continue }
            total += 1
            let a = LeadsheetParser.parse(content, vocabulary: Self.vocabulary)
            let b = LeadsheetParser.parse(LeadsheetWriter.leadsheet(score: a), vocabulary: Self.vocabulary)
            if let diff = RoundTripTests.firstDifference(a, b) {
                // Group by the kind of difference (first word or two).
                let kind = diff.split(separator: " ").prefix(2)
                    .filter { $0.allSatisfy { !$0.isNumber } }.joined(separator: " ")
                groups[kind, default: []].append("\(row[0]): \(diff)")
            }
        }
        let summary = groups.sorted { $0.value.count > $1.value.count }
            .map { "  \($0.key): \($0.value.count) files, e.g. \($0.value[0])" }.joined(separator: "\n")
        Self.writeReport("leadsheet-roundtrip-diff.txt", groups.values.flatMap { $0 }.sorted())
        print("ROUND TRIP: \(total - groups.values.map(\.count).reduce(0, +))/\(total) stable\n\(summary)")
        XCTAssertTrue(groups.isEmpty, "load → save → reload changed the model:\n\(summary)")
    }

    // MARK: Styles vs Java

    /// Total slot duration of a rule list the way Java's Pattern.getDuration
    /// computes it: every rule's duration string except volume (`V`) rules.
    static func duration(of rules: [String]) -> Int {
        rules.reduce(0) { sum, token in
            guard let c = token.first, c != "V" else { return sum }
            return sum + Duration.slots(String(token.dropFirst()))
        }
    }

    func testStyleCountsMatchJava() throws {
        let golden = try Self.goldenLines("style-counts.tsv")
        XCTAssertGreaterThan(golden.count, 100)
        var groups: [String: [String]] = [:]
        var report: [String] = []
        var seen = Set<String>()
        for row in golden {
            let name = row[0]
            seen.insert(name)
            let url = TestData.url("styles/\(name).sty")
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                  let style = try? StyleParser.parse(content) else {
                // Java registers styles by their (name …) field; find by scan.
                groups["swift-cannot-load", default: []].append(name)
                continue
            }
            func fmt(_ d: Double) -> String { Self.javaDouble(d) }
            let mine: [(String, String)] = [
                ("bassPatternCount", "\(style.bassPatterns.count)"),
                ("chordPatternCount", "\(style.chordPatterns.count)"),
                ("drumPatternCount", "\(style.drumPatterns.count)"),
                ("swing", fmt(style.swing)),
                ("compSwing", fmt(style.compSwing)),
                ("voicingType", style.voicingType),
                ("bassLow", "\(Register.midi(ofNoteName: style.bassLow, fallback: -1))"),
                ("bassHigh", "\(Register.midi(ofNoteName: style.bassHigh, fallback: -1))"),
                ("chordLow", "\(Register.midi(ofNoteName: style.chordLow, fallback: -1))"),
                ("chordHigh", "\(Register.midi(ofNoteName: style.chordHigh, fallback: -1))"),
                ("bassPatternDurations", style.bassPatterns.map {
                    "\(Self.duration(of: $0.rules)):\(Self.javaDouble($0.weight))" }.joined(separator: " ")),
                ("chordPatternDurations", style.chordPatterns.map {
                    "\(Self.duration(of: $0.rules)):\(Self.javaDouble($0.weight))" }.joined(separator: " ")),
                ("drumPatternDurations", style.drumPatterns.map { p in
                    "\(p.voices.map { Self.duration(of: $0.hits) }.max() ?? 0):\(Self.javaDouble(p.weight))" }
                    .joined(separator: " ")),
            ]
            var first: String?
            for (i, (field, value)) in mine.enumerated() {
                let java = i + 1 < row.count ? row[i + 1] : ""
                if java != value {
                    if first == nil { first = field }
                    report.append("\(name)\t\(field)\tjava=\(java)\tswift=\(value)")
                }
            }
            if let first { groups[first, default: []].append(name) }
        }
        // Style files Java did not register at all.
        for file in TestData.files(under: "styles", ext: "sty") {
            let name = file.deletingPathExtension().lastPathComponent
            if !seen.contains(name) { groups["style-file-not-registered-by-java", default: []].append(name) }
        }
        Self.writeReport("style-counts-diff.tsv", report)
        let summary = groups.sorted { $0.value.count > $1.value.count }
            .map { "  \($0.key): \($0.value.count) styles, e.g. \($0.value.prefix(3).joined(separator: ", "))" }
            .joined(separator: "\n")
        print("STYLE SWEEP: \(golden.count - groups.values.map(\.count).reduce(0, +))/\(golden.count) match Java\n\(summary)")
        XCTAssertTrue(groups.isEmpty, "style parse differs from Java:\n\(summary)")
    }
}
