//
//  LeadsheetParser.swift
//  ImprovisorEngine
//
//  Parses a `.ls` lead sheet into a `Score`. Ports the reading logic of
//  imp/data/Leadsheet. A leadsheet is a stream of S-expression metadata forms
//  followed by bare tokens:
//
//    (title So What?) (meter 4 4) (key 0) (tempo 160.0) (style swing)
//    (part (type chords) …)
//    Dm7 | / | Dm7 | / |            <- chord shorthand (not S-expressions)
//    (part (type melody) …)
//    r8 a-8 r1+1+…                  <- melody note tokens
//
//  Chord shorthand rules (from Leadsheet.addToChordPart):
//    * `|` and `,` are bar delimiters.
//    * Within a bar, the bar's slots are split evenly across its tokens; each
//      token is either a chord symbol or `/` (repeat/hold the previous chord).
//    * An empty bar holds the previous chord for a full measure.
//

import Foundation

public enum LeadsheetParser {

    /// Parse leadsheet text into a `Score`, resolving chords with `vocabulary`.
    public static func parse(_ content: String, vocabulary: Vocabulary) -> Score {
        var score = Score()

        // Collected token streams (filled while walking the flat form list).
        var chordTokens: [String] = []
        var melodyTokens: [[String]] = [[]] // one bucket per melody part
        var sectionMarks: [(measure: Int, style: String)] = []

        var mode: StreamMode = .none

        for form in PolyaParser.parseAll(content) {
            switch form {
            case let .list(list):
                dispatch(list, into: &score, mode: &mode,
                         chordTokens: chordTokens, sectionMarks: &sectionMarks,
                         melodyTokens: &melodyTokens)
            default:
                // A bare token belongs to the current stream.
                let token = form.description
                switch mode {
                case .chords: chordTokens.append(token)
                case .melody: melodyTokens[melodyTokens.count - 1].append(token)
                case .none: break
                }
            }
        }

        // Build the chord part now that the meter is known.
        score.chordPart = buildChordPart(
            tokens: chordTokens,
            slotsPerBar: score.meter.slotsPerMeasure,
            vocabulary: vocabulary
        )

        // Build melody parts.
        score.melodyParts = melodyTokens
            .filter { !$0.isEmpty }
            .map { MelodyPart(events: NoteSymbol.parseMelody($0.joined(separator: " "))) }

        // Sections.
        var info = SectionInfo()
        if sectionMarks.isEmpty {
            info.add(SectionRecord(measure: 0, styleName: score.styleName))
        } else {
            for mark in sectionMarks {
                info.add(SectionRecord(measure: mark.measure, styleName: mark.style))
            }
        }
        score.sections = info

        return score
    }

    /// Convenience: parse a `.ls` file from disk.
    public static func parse(contentsOf url: URL, vocabulary: Vocabulary) throws -> Score {
        try parse(String(contentsOf: url, encoding: .utf8), vocabulary: vocabulary)
    }

    // MARK: Metadata / part dispatch

    private static func dispatch(
        _ list: Polylist,
        into score: inout Score,
        mode: inout StreamMode,
        chordTokens: [String],
        sectionMarks: inout [(measure: Int, style: String)],
        melodyTokens: inout [[String]]
    ) {
        guard case let .symbol(head) = list.firstOrNil() else { return }
        let rest = list.rest()

        switch head {
        case "title": score.title = joinedText(rest)
        case "composer": score.composer = joinedText(rest)
        case "comments": score.comments = joinedText(rest)
        case "meter":
            if let n = rest.firstOrNil()?.intValue, let d = rest.secondOrNil()?.intValue {
                score.meter = Meter(n, d)
            }
        case "key":
            if let k = rest.firstOrNil()?.intValue { score.key = Key(index: k) }
        case "tempo":
            if let t = rest.firstOrNil()?.doubleValue { score.tempo = t }
        case "volume":
            if let v = rest.firstOrNil()?.intValue { score.volume = v }
        case "style":
            if let s = rest.firstOrNil()?.symbolValue { score.styleName = s }
        case "section":
            // (section (style X)) — record where the style changes.
            let style = rest.assoc("style")?.secondOrNil()?.symbolValue ?? ""
            let measure = barCount(chordTokens)
            sectionMarks.append((measure: measure, style: style))
        case "part":
            switch rest.assoc("type")?.secondOrNil()?.symbolValue {
            case "chords": mode = .chords
            case "melody":
                mode = .melody
                melodyTokens.append([])
            default: mode = .none
            }
        default:
            break
        }
    }

    private enum StreamMode { case none, chords, melody }

    // MARK: Chord shorthand -> ChordPart

    static func buildChordPart(tokens rawTokens: [String], slotsPerBar: Int,
                               vocabulary: Vocabulary) -> ChordPart {
        var part = ChordPart()
        guard slotsPerBar > 0 else { return part }

        // Trim leading/trailing bar delimiters (formatting, not empty measures).
        var tokens = rawTokens
        while let f = tokens.first, isBar(f) { tokens.removeFirst() }
        while let l = tokens.last, isBar(l) { tokens.removeLast() }

        // Split into bars.
        var bars: [[String]] = []
        var current: [String] = []
        for token in tokens {
            if isBar(token) {
                bars.append(current)
                current = []
            } else {
                current.append(token)
            }
        }
        bars.append(current)

        var previous: ChordSymbol?
        var accumulated = 0

        for bar in bars {
            let n = bar.count
            if n == 0 {
                accumulated += slotsPerBar // empty bar holds previous chord
                continue
            }
            guard slotsPerBar % n == 0 else {
                // Non-conforming bar: fall back to whole-bar spacing.
                accumulated += slotsPerBar
                continue
            }
            let spacing = slotsPerBar / n
            for token in bar {
                if token == "/" {
                    accumulated += spacing
                } else {
                    if let previous {
                        part.append(previous, duration: accumulated)
                    }
                    // Unrecognized chord names fall back to NC (as Java does).
                    previous = ChordSymbol.parse(token, vocabulary: vocabulary)
                        ?? ChordSymbol.parse(ChordSymbol.noChordName, vocabulary: vocabulary)!
                    accumulated = spacing
                }
            }
        }

        if let previous {
            part.append(previous, duration: accumulated)
        }
        return part
    }

    // MARK: Helpers

    private static func isBar(_ token: String) -> Bool { token == "|" || token == "," }

    /// Number of complete bars represented by the tokens so far.
    private static func barCount(_ tokens: [String]) -> Int {
        tokens.filter { isBar($0) }.count
    }

    private static func joinedText(_ list: Polylist) -> String {
        list.map(\.description).joined(separator: " ")
    }
}
