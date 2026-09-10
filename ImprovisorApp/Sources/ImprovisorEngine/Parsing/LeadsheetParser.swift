//
//  LeadsheetParser.swift
//  ImprovisorEngine
//
//  Parses a `.ls` lead sheet into a `Score`. Ports the reading logic of
//  imp/data/Leadsheet.readLeadSheet + addToChordPart. A leadsheet is a stream
//  of S-expression directives followed by bare tokens:
//
//    (title So What?) (meter 4 4) (key 0) (tempo 160.0) (style swing …)
//    (part (type chords) (title …) (instrument 0) …)
//    (section (style swing))          <- section/phrase markers sit in the
//    Dm7 | / | Dm7 | / |                 chord stream and mark a measure
//    (part (type melody) (stave treble) …)
//    r8 a-8 r1+1+…                    <- melody note tokens
//
//  Token classification follows Java: bars (`|`, `,`) and `/` and names that
//  start with an upper-case letter are chords; lower-case names are melody
//  notes for the current melody part.
//
//  Chord shorthand (addToChordPart): within a bar the bar's slots are split
//  evenly across its chord/slash tokens; `/` holds the previous chord; an empty
//  bar holds the previous chord for a full measure. A leading bar means "no
//  pickup" and is dropped. The final chord is fleshed out to the bar line.
//

import Foundation

public enum LeadsheetParser {

    /// Parse leadsheet text into a `Score`, resolving chords with `vocabulary`.
    public static func parse(_ content: String, vocabulary: Vocabulary) -> Score {
        var score = Score()
        var chordStream: [ChordToken] = []
        var melodyBuckets: [MelodyBucket] = []
        var chordInfo = PartInfo.defaultChords
        var seenStyle = false
        var rise = 0

        func currentBucket() -> Int {
            if melodyBuckets.isEmpty { melodyBuckets.append(MelodyBucket(info: .defaultMelody)) }
            return melodyBuckets.count - 1
        }

        for form in PolyaParser.parseAll(content) {
            switch form {
            case let .list(list):
                guard case let .symbol(head) = list.firstOrNil() else { continue }
                let rest = list.rest()
                switch head {
                case "title": score.title = concatElements(rest)
                case "composer": score.composer = concatElements(rest)
                case "show": score.showTitle = concatElements(rest)
                case "year": score.year = concatElements(rest)
                case "comments": score.comments = concatElements(rest)
                case "meter":
                    if let n = rest.firstOrNil()?.intValue {
                        let d = rest.secondOrNil()?.intValue ?? 4
                        score.meter = Meter(n, d > 0 ? d : 4)
                    }
                case "key":
                    if let k = rest.firstOrNil()?.intValue { score.key = Key(index: k) }
                case "tempo":
                    if let t = rest.firstOrNil()?.doubleValue { score.tempo = t }
                case "volume":
                    if let v = rest.firstOrNil()?.intValue { score.volume = v }
                case "playback-transpose":
                    let values = rest.toArray().compactMap(\.intValue)
                    if values.count >= 3 {
                        score.playbackTranspose = Transposition(bass: values[0], chords: values[1], melody: values[2])
                    } else if values.count == 1 {
                        score.playbackTranspose = Transposition(bass: values[0], chords: values[0], melody: 0)
                    }
                case "chord-font-size": if let v = rest.firstOrNil()?.intValue { score.chordFontSize = v }
                case "bass-instrument": if let v = rest.firstOrNil()?.intValue { score.bassInstrument = v }
                case "bass-volume": if let v = rest.firstOrNil()?.intValue { score.bassVolume = v }
                case "drum-volume": if let v = rest.firstOrNil()?.intValue { score.drumVolume = v }
                case "chord-volume": if let v = rest.firstOrNil()?.intValue { score.chordVolume = v }
                case "melody-volume": if let v = rest.firstOrNil()?.intValue { score.melodyVolume = v }
                case "breakpoint": if let v = rest.firstOrNil()?.intValue { score.breakpoint = v }
                case "roadmap-layout": if let v = rest.firstOrNil()?.intValue { score.roadmapLayout = v }
                case "layout": score.layout = rest.toArray().compactMap(\.intValue)
                case "transpose":
                    if let r = rest.firstOrNil()?.intValue { rise = r }
                case "bars":
                    break // ignored by Java as well
                case "style":
                    // (style name (param …)*) — the header style. Java also
                    // treats it as a section marker at the current measure.
                    if let name = rest.firstOrNil()?.symbolValue {
                        if !seenStyle {
                            seenStyle = true
                            score.styleName = name
                            let params = rest.rest()
                            score.styleOverride = params.nonEmpty ? params : nil
                        }
                        chordStream.append(.marker(SectionMarker(styleName: name, isPhrase: false)))
                    }
                case "section", "phrase":
                    let style = rest.assoc("style")?.secondOrNil()?.symbolValue ?? ""
                    chordStream.append(.marker(SectionMarker(styleName: style, isPhrase: head == "phrase")))
                case "part":
                    let (type, info) = parsePart(rest)
                    switch type {
                    case "chords":
                        chordInfo = info
                    case "melody":
                        var melodyInfo = info
                        if rest.assoc("stave") == nil { melodyInfo.stave = .treble }
                        melodyBuckets.append(MelodyBucket(info: melodyInfo))
                    default:
                        break
                    }
                default:
                    score.unknownForms.append(list)
                }

            case let .symbol(token):
                guard let first = token.first else { continue }
                if first == "|" || first == "," {
                    chordStream.append(.bar)
                } else if first == "/" {
                    chordStream.append(.slash)
                } else if first.isLetter {
                    if first.isLowercase {
                        melodyBuckets[currentBucket()].tokens.append(token)
                    } else {
                        chordStream.append(.chord(token))
                    }
                }

            default:
                break // stray numbers are ignored
            }
        }

        // Chords + sections.
        var sections = SectionInfo()
        score.chordPart = buildChordPart(stream: chordStream,
                                         slotsPerBar: score.meter.slotsPerMeasure,
                                         vocabulary: vocabulary,
                                         sections: &sections)
        score.chordPart.info = chordInfo
        if sections.record(atMeasure: 0) == nil || sections.records.first?.measure != 0 {
            sections.add(SectionRecord(measure: 0, styleName: score.styleName, isPhrase: false))
        }
        score.sections = sections

        // Melody parts: one per (part (type melody)) header (plus an implicit
        // first part if notes appeared before any header).
        score.melodyParts = melodyBuckets.map { bucket in
            MelodyPart(events: parseMelodyTokens(bucket.tokens, rise: rise), info: bucket.info)
        }
        return score
    }

    /// Convenience: parse a `.ls` file from disk.
    public static func parse(contentsOf url: URL, vocabulary: Vocabulary) throws -> Score {
        try parse(String(contentsOf: url, encoding: .utf8), vocabulary: vocabulary)
    }

    // MARK: Pieces

    enum ChordToken: Equatable {
        case bar
        case slash
        case chord(String)
        case marker(SectionMarker)
    }

    struct SectionMarker: Equatable {
        var styleName: String
        var isPhrase: Bool
    }

    private struct MelodyBucket {
        var info: PartInfo
        var tokens: [String] = []
    }

    /// `(part (type X) (title …) (composer …) (instrument n) (volume n) (key k) (stave s))`
    private static func parsePart(_ items: Polylist) -> (type: String, info: PartInfo) {
        var info = PartInfo()
        var type = ""
        for item in items {
            guard case let .list(sub) = item, case let .symbol(key) = sub.firstOrNil() else { continue }
            let value = sub.rest()
            switch key {
            case "type": type = value.firstOrNil()?.symbolValue ?? ""
            case "title": info.title = concatElements(value)
            case "composer": info.composer = concatElements(value)
            case "instrument": if let v = value.firstOrNil()?.intValue { info.instrument = v }
            case "volume": if let v = value.firstOrNil()?.intValue { info.volume = v }
            case "key": if let v = value.firstOrNil()?.intValue { info.key = v }
            case "stave":
                if let s = value.firstOrNil()?.symbolValue, let stave = StaveType(rawValue: s) {
                    info.stave = stave
                }
            default: break
            }
        }
        if type == "chords" && items.assoc("instrument") == nil { info.instrument = PartInfo.defaultChords.instrument }
        if type == "chords" && items.assoc("volume") == nil { info.volume = PartInfo.defaultChords.volume }
        if type == "melody" && items.assoc("instrument") == nil { info.instrument = PartInfo.defaultMelody.instrument }
        if type == "melody" && items.assoc("volume") == nil { info.volume = PartInfo.defaultMelody.volume }
        return (type, info)
    }

    /// Melody tokens → events. Handles `vNN` volume tokens (Java VolumeSymbol)
    /// and skips anything unparseable, as the Java reader does.
    static func parseMelodyTokens(_ tokens: [String], rise: Int) -> [MusicEvent] {
        var events: [MusicEvent] = []
        var volume = 127
        for token in tokens {
            if token.hasPrefix("v"), let v = Int(token.dropFirst()) {
                volume = max(0, min(127, v))
                continue
            }
            guard var event = NoteSymbol.parse(token, transposition: rise) else { continue }
            if case var .note(n) = event {
                n.volume = volume
                event = .note(n)
            }
            events.append(event)
        }
        return events
    }

    // MARK: Chord shorthand -> ChordPart (Java addToChordPart)

    static func buildChordPart(stream: [ChordToken], slotsPerBar: Int,
                               vocabulary: Vocabulary,
                               sections: inout SectionInfo) -> ChordPart {
        var part = ChordPart()
        guard slotsPerBar > 0 else { return part }

        var tokens = stream[...]
        if tokens.first == .bar { tokens = tokens.dropFirst() } // no pickup

        var previous: ChordSymbol?
        var accumulated = 0
        var measure = 0

        while !tokens.isEmpty {
            // Collect one bar.
            var bar: [ChordToken] = []
            while let t = tokens.first, t != .bar {
                bar.append(t)
                tokens = tokens.dropFirst()
            }
            if tokens.first == .bar { tokens = tokens.dropFirst() }

            let cells = bar.filter { if case .marker = $0 { return false } else { return true } }.count
            let spacing = cells > 0 ? slotsPerBar / cells : slotsPerBar
            let remainder = cells > 0 ? slotsPerBar - spacing * cells : 0
            if cells == 0 { accumulated += slotsPerBar }

            var cellIndex = 0
            var seenFirstChord = false
            for token in bar {
                switch token {
                case let .marker(marker):
                    let index = measure + (seenFirstChord ? 1 : 0)
                    sections.add(SectionRecord(measure: index, styleName: marker.styleName,
                                               isPhrase: marker.isPhrase))
                case .slash, .chord:
                    seenFirstChord = true
                    let width = spacing + (cellIndex == cells - 1 ? remainder : 0)
                    cellIndex += 1
                    if case let .chord(name) = token {
                        if let previous { part.append(previous, duration: accumulated) }
                        // Unrecognized chord names fall back to NC (as Java does).
                        previous = ChordSymbol.parse(name, vocabulary: vocabulary)
                            ?? ChordSymbol.parse(ChordSymbol.noChordName, vocabulary: vocabulary)!
                        accumulated = width
                    } else {
                        accumulated += width
                    }
                case .bar:
                    break
                }
            }
            measure += 1
        }

        if let previous { part.append(previous, duration: accumulated) }
        // Flesh out a partial final bar (Java's Part does this on insertion).
        let tail = part.size % slotsPerBar
        if tail != 0 { part.extendLast(by: slotsPerBar - tail) }
        return part
    }

    // MARK: Helpers

    /// Java `Leadsheet.concatElements`: elements joined by single spaces, except
    /// that no space precedes a comma token.
    static func concatElements(_ list: Polylist) -> String {
        var out = ""
        var first = true
        for item in list {
            let text = item.description
            if !first && text != "," { out += " " }
            out += text
            first = false
        }
        return out
    }
}
