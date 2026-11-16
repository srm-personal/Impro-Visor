//
//  GoldenComparisonTests.swift
//  ImprovisorEngineTests
//
//  Differential harness, Step 2: render every case in Testing/goldens/cases.tsv
//  with the Swift engine and compare, event by event, with what the original
//  Java engine produced for the same leadsheet, style and seed
//  (Testing/goldens/accompaniment/<id>.events.txt).
//
//  Matching is EXACT: same channel, tick, pitch, velocity and duration for
//  every note. There are no tolerances.
//
//  A failing case reports its first divergent event with musical context (bar,
//  beat, chord). Failures are grouped by track and kind of divergence; the
//  full list goes to Testing/.build/reports/golden-diff.txt.
//

import XCTest
@testable import ImprovisorEngine

struct GoldenEvent: Equatable, Comparable, CustomStringConvertible {
    var channel: Int
    var tick: Int
    var pitch: Int
    var velocity: Int
    var duration: Int

    static func < (a: GoldenEvent, b: GoldenEvent) -> Bool {
        (a.tick, a.channel, a.pitch, a.velocity, a.duration) < (b.tick, b.channel, b.pitch, b.velocity, b.duration)
    }

    static let roles = [0: "melody", 3: "chords", 6: "bass", 9: "drums"]
    var role: String { Self.roles[channel] ?? "ch\(channel)" }
    var description: String { "\(role) tick \(tick) pitch \(pitch) vel \(velocity) dur \(duration)" }
}

struct GoldenCase {
    var id: String
    var leadsheet: String
    var style: String
    var seed: Int64
}

enum GoldenSupport {
    static let vocabulary: Vocabulary = {
        Vocabulary(source: try! TestData.contents("vocab/My.voc"))
    }()

    /// Every shipped style, keyed by its `(name …)` like Java's registry.
    static let styles: StyleCatalog = {
        var all: [Style] = []
        var voicings: [String: VoicingSettings] = [:]
        for url in TestData.files(under: "styles", ext: "sty").sorted(by: { $0.path < $1.path }) {
            if let s = try? StyleParser.parse(contentsOf: url) { all.append(s) }
        }
        for url in TestData.files(under: "voicings", ext: "fv") {
            if let v = try? VoicingParser.parse(contentsOf: url) { voicings[url.lastPathComponent] = v }
        }
        var seen = Set<String>()
        return StyleCatalog(styles: all.filter { seen.insert($0.name).inserted }, voicings: voicings,
                            vocabulary: vocabulary)
    }()

    static func cases() throws -> [GoldenCase] {
        try TestData.contents("ImprovisorApp/Testing/goldens/cases.tsv")
            .split(separator: "\n").filter { !$0.hasPrefix("#") }
            .map { line in
                let f = line.split(separator: "\t").map(String.init)
                return GoldenCase(id: f[0], leadsheet: f[1], style: f[2], seed: Int64(f[3])!)
            }
    }

    static func golden(_ id: String) throws -> (events: [GoldenEvent], header: [String: String]) {
        let text = try TestData.contents("ImprovisorApp/Testing/goldens/accompaniment/\(id).events.txt")
        var events: [GoldenEvent] = []
        var header: [String: String] = [:]
        for line in text.split(separator: "\n") {
            if line.hasPrefix("#") {
                let parts = line.dropFirst(2).split(separator: " ", maxSplits: 1).map(String.init)
                if parts.count == 2 { header[parts[0]] = parts[1] }
                continue
            }
            let f = line.split(separator: " ").compactMap { Int($0) }
            if f.count == 5 {
                events.append(GoldenEvent(channel: f[0], tick: f[1], pitch: f[2], velocity: f[3], duration: f[4]))
            }
        }
        return (events, header)
    }

    /// The Swift score for a case, set up the way the Java driver sets up its
    /// Score: an explicit style replaces all sections with one section in that
    /// style (ChordPart.setStyle).
    static func score(for c: GoldenCase) throws -> Score {
        var score = LeadsheetParser.parse(try TestData.contents(c.leadsheet), vocabulary: vocabulary)
        if c.style != "-" {
            // The leadsheet header's inline style parameters mutate that named
            // style in Java, so they still apply iff the same style is chosen.
            if score.styleName != c.style { score.styleOverride = nil }
            score.styleName = c.style
            score.sections = SectionInfo(records: [SectionRecord(measure: 0, styleName: c.style)])
        }
        return score
    }

    /// Swift render → events in Java's coordinates: 480 ticks per beat
    /// (4 ticks per slot) and Java's default channels.
    static func render(_ c: GoldenCase) throws -> (events: [GoldenEvent], score: Score) {
        let score = try score(for: c)
        var options = ArrangementOptions()
        options.javaSeed = c.seed
        // Java plays the progression once per melody part (Score.render).
        options.choruses = max(1, score.melodyParts.count)
        let arrangement = ArrangementBuilder.build(score: score, styles: styles, options: options)
        let channelFor = [ArrangementBuilder.melodyTrackName: 0, ArrangementBuilder.chordTrackName: 3,
                          ArrangementBuilder.bassTrackName: 6, ArrangementBuilder.drumTrackName: 9]
        var events: [GoldenEvent] = []
        for track in arrangement.tracks {
            let channel = channelFor[track.name] ?? Int(track.channel)
            for n in track.notes {
                events.append(GoldenEvent(channel: channel, tick: n.startTick * 4, pitch: n.pitch,
                                          velocity: n.velocity, duration: n.duration * 4))
            }
        }
        return (events.sorted(), score)
    }

    /// Bar / beat / chord at a tick, for failure messages.
    static func context(tick: Int, score: Score) -> String {
        let slot = tick / 4
        let perBar = max(1, score.meter.slotsPerMeasure)
        let form = max(1, score.chordPart.size)
        let chorus = slot / form
        let inForm = slot % form
        let bar = inForm / perBar + 1
        let beat = Double(inForm % perBar) / Double(score.meter.slotsPerBeat) + 1
        let chord = score.chordPart.chord(at: inForm)?.name ?? "?"
        return "chorus \(chorus + 1) bar \(bar) beat \(String(format: "%.2f", beat)) chord \(chord)"
    }

    struct Divergence {
        var role: String
        var kind: String
        var message: String
    }

    /// First divergent event between sorted event lists, restricted to `channel`
    /// when given.
    static func firstDivergence(expected: [GoldenEvent], actual: [GoldenEvent], score: Score) -> Divergence? {
        let n = min(expected.count, actual.count)
        var i = 0
        while i < n && expected[i] == actual[i] { i += 1 }
        if i == expected.count && i == actual.count { return nil }
        let e = i < expected.count ? expected[i] : nil
        let a = i < actual.count ? actual[i] : nil
        let kind: String
        let role: String
        switch (e, a) {
        case let (e?, a?):
            if e.channel != a.channel || e.tick != a.tick {
                // One side has an event the other lacks at this point.
                if a < e { kind = "extra event"; role = a.role } else { kind = "missing event"; role = e.role }
            } else if e.pitch != a.pitch { kind = "pitch"; role = e.role }
            else if e.velocity != a.velocity { kind = "velocity"; role = e.role }
            else { kind = "duration"; role = e.role }
        case let (e?, nil): kind = "missing event (Swift ends early)"; role = e.role
        case let (nil, a?): kind = "extra event (Swift runs long)"; role = a.role
        default: return nil
        }
        let tick = min(e?.tick ?? Int.max, a?.tick ?? Int.max)
        func window(_ list: [GoldenEvent]) -> String {
            let lo = max(0, i - 2), hi = min(list.count, i + 3)
            return (lo..<hi).map { ($0 == i ? "  >> " : "     ") + list[$0].description }.joined(separator: "\n")
        }
        let message = """
            first divergence at event #\(i), \(context(tick: tick, score: score)): \(kind) on \(role)
              java : \(e?.description ?? "(no more events)")
              swift: \(a?.description ?? "(no more events)")
            java events around it:
            \(window(expected))
            swift events around it:
            \(window(actual))
            """
        return Divergence(role: role, kind: kind, message: message)
    }
}

final class GoldenComparisonTests: XCTestCase {

    func testAccompanimentMatchesJavaGoldens() throws {
        let cases = try GoldenSupport.cases()
        XCTAssertGreaterThanOrEqual(cases.count, 500)

        var passed = 0
        var groups: [String: [String]] = [:]          // "role: kind" -> case ids
        var perRole: [String: (ok: Int, total: Int)] = [:]
        var report: [String] = []

        for c in cases {
            if let only = ProcessInfo.processInfo.environment["IMPRO_ONLY"], c.id != only { continue }
            let (expected, _) = try GoldenSupport.golden(c.id)
            let (actual, score) = try GoldenSupport.render(c)

            // Per-track tally: a track "matches" when its own events are identical.
            for (channel, role) in GoldenEvent.roles {
                let e = expected.filter { $0.channel == channel }
                let a = actual.filter { $0.channel == channel }
                if e.isEmpty && a.isEmpty { continue }
                var t = perRole[role] ?? (0, 0)
                t.total += 1
                if e == a { t.ok += 1 }
                perRole[role] = t
            }

            if let d = GoldenSupport.firstDivergence(expected: expected, actual: actual, score: score) {
                groups["\(d.role): \(d.kind)", default: []].append(c.id)
                // Swift's full event list, for diffing against the golden by hand.
                let dir = TestData.url("ImprovisorApp/Testing/.build/reports/swift-events")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? actual.map { "\($0.channel) \($0.tick) \($0.pitch) \($0.velocity) \($0.duration)" }
                    .joined(separator: "\n")
                    .write(to: dir.appendingPathComponent("\(c.id).events.txt"), atomically: true, encoding: .utf8)
                report.append("=== \(c.id)  (\(c.leadsheet), style \(c.style), seed \(c.seed))\n\(d.message)\n")
            } else {
                passed += 1
            }
        }

        CorpusSweepTests.writeReport("golden-diff.txt", report)
        let roleSummary = perRole.sorted { $0.key < $1.key }
            .map { "  \($0.key): \($0.value.ok)/\($0.value.total) tracks identical" }.joined(separator: "\n")
        let groupSummary = groups.sorted { $0.value.count > $1.value.count }
            .map { "  \($0.key): \($0.value.count) cases, e.g. \($0.value.prefix(2).joined(separator: ", "))" }
            .joined(separator: "\n")
        print("GOLDEN COMPARISON: \(passed)/\(cases.count) cases identical to Java\n\(roleSummary)\nfirst divergence by track and kind:\n\(groupSummary)")
        if let first = report.first { print("example:\n\(first)") }
        XCTAssertEqual(passed, cases.count,
                       "\(cases.count - passed) cases differ from Java; see Testing/.build/reports/golden-diff.txt\n\(groupSummary)")
    }
}
