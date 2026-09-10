//
//  LeadsheetWriter.swift
//  ImprovisorEngine
//
//  Serializes a `Score` back into Impro-Visor `.ls` leadsheet text — the inverse
//  of LeadsheetParser and a port of Java's `Leadsheet.saveLeadSheet` +
//  `Part.saveLeadsheet`: header fields in the same order, the style block, the
//  chords part with `(section …)` / `(phrase …)` markers at their measures, and
//  one `(part (type melody) …)` block per chorus. Parsing the output yields an
//  equal `Score` (verified over the whole shipped corpus).
//

import Foundation

public enum LeadsheetWriter {

    // MARK: Whole document

    /// A complete `.ls` document for `score`.
    public static func leadsheet(score: Score) -> String {
        var out = ""
        func line(_ s: String) { out += s + "\n" }

        line("(title \(score.title))")
        line("(composer \(score.composer))")
        line("(show \(score.showTitle))")
        line("(year \(score.year))")
        line("(comments \(score.comments))")
        line("(meter \(score.meter.numerator) \(score.meter.denominator))")
        line("(key \(score.key.index))")
        line("(tempo \(PolyValue.formatDouble(score.tempo)))")
        line("(volume \(score.volume))")
        let t = score.playbackTranspose
        line("(playback-transpose \(t.bass) \(t.chords) \(t.melody))")
        line("(chord-font-size \(score.chordFontSize))")
        line("(bass-instrument \(score.bassInstrument))")
        line("(bass-volume \(score.bassVolume))")
        line("(drum-volume \(score.drumVolume))")
        line("(chord-volume \(score.chordVolume))")
        line("(breakpoint \(score.breakpoint))")
        line(score.layout.isEmpty ? "(layout)" : "(layout \(score.layout.map(String.init).joined(separator: " ")))")
        line("(roadmap-layout \(score.roadmapLayout))")
        line("(melody-volume \(score.melodyVolume))")
        for form in score.unknownForms { line(form.description) }

        if let override = score.styleOverride, override.nonEmpty {
            line("(style \(score.styleName)")
            for param in override { line("    \(param.description)") }
            line(")")
        } else {
            line("(style \(score.styleName))")
        }

        // Chords part.
        out += partHeader(type: "chords", info: score.chordPart.info)
        out += chordsBody(score)

        // Melody parts.
        for part in score.melodyParts {
            line("")
            out += partHeader(type: "melody", info: part.info)
            let text = NoteSerializer.melodyText(part, slotsPerMeasure: score.meter.slotsPerMeasure)
            if !text.isEmpty { line(text) }
        }
        return out
    }

    /// `(part (type X) (title …) (composer …) (instrument n) (volume n) (key k) [(stave s)])`
    static func partHeader(type: String, info: PartInfo) -> String {
        var out = "(part\n"
        out += "    (type \(type))\n"
        out += "    (title \(info.title))\n"
        out += "    (composer \(info.composer))\n"
        out += "    (instrument \(info.instrument))\n"
        out += "    (volume \(info.volume))\n"
        out += "    (key \(info.key))\n"
        if type == "melody" { out += "    (stave \(info.stave.rawValue))\n" }
        out += ")\n"
        return out
    }

    /// Section markers interleaved with the bar-delimited chord text.
    static func chordsBody(_ score: Score) -> String {
        let measures = score.measureCount
        let records = score.sections.records
        var out = ""
        if records.isEmpty {
            let text = progressionText(score.chordPart, meter: score.meter)
            if !text.isEmpty { out += text + "\n" }
            return out
        }
        for (i, record) in records.enumerated() {
            let next = i + 1 < records.count ? records[i + 1].measure : max(measures, record.measure)
            let style = record.usesPreviousStyle ? "" : " \(record.styleName)"
            if record.isPhrase {
                out += "\n(phrase (style\(style))) \n"
            } else {
                out += "\n\n(section (style\(style))) \n\n"
            }
            if record.measure < next {
                let text = progressionText(score.chordPart, meter: score.meter,
                                           measures: record.measure..<next)
                if !text.isEmpty { out += text + "\n" }
            }
        }
        return out
    }

    // MARK: Chord text

    /// The chord cells of one measure (`["Dm7", "/", "G7", "/"]`): the fewest
    /// even subdivisions that put every chord start on a cell boundary. `/`
    /// holds the previous chord.
    public static func chordCells(_ part: ChordPart, measure: Int, slotsPerBar: Int) -> [String] {
        let start = measure * slotsPerBar
        let end = start + slotsPerBar
        let starts = part.entries.filter { $0.start >= start && $0.start < end }
        guard !starts.isEmpty else { return ["/"] }

        let offsets = starts.map { $0.start - start }
        var cellCount = slotsPerBar
        for n in 1...slotsPerBar where slotsPerBar % n == 0 {
            let width = slotsPerBar / n
            if offsets.allSatisfy({ $0 % width == 0 }) { cellCount = n; break }
        }
        let width = slotsPerBar / cellCount
        var byOffset: [Int: String] = [:]
        for entry in starts { byOffset[entry.start - start] = entry.symbol.name }
        return (0..<cellCount).map { byOffset[$0 * width] ?? "/" }
    }

    /// Bar-delimited chord text (e.g. `Dm7 | / | G7 C7 | / |`) for a range of
    /// measures (default: all), wrapped `barsPerLine` bars per line. Each bar's
    /// cells are space-separated so the parser re-splits the bar evenly.
    public static func progressionText(_ part: ChordPart, meter: Meter,
                                       measures: Range<Int>? = nil,
                                       barsPerLine: Int = 4) -> String {
        let slotsPerBar = meter.slotsPerMeasure
        guard slotsPerBar > 0, part.size > 0 else { return "" }
        let total = Int((Double(part.size) / Double(slotsPerBar)).rounded(.up))
        let range = measures ?? 0..<total
        guard !range.isEmpty else { return "" }

        let bars = range.map { chordCells(part, measure: $0, slotsPerBar: slotsPerBar).joined(separator: " ") }
        return stride(from: 0, to: bars.count, by: max(1, barsPerLine)).map { i in
            bars[i..<min(i + barsPerLine, bars.count)].map { $0 + " |" }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    // MARK: Convenience (authoring from chord text)

    /// A minimal `.ls` document from user-entered chord text (`|` bars, `/`
    /// repeats). Kept for callers that author a tune before it is parsed into a
    /// `Score`; `leadsheet(score:)` is the full writer.
    public static func leadsheet(title: String, composer: String, meter: Meter,
                                 key: Int, tempo: Double, style: String,
                                 chords: String) -> String {
        var out = ""
        out += "(title \(title))\n"
        out += "(composer \(composer))\n"
        out += "(meter \(meter.numerator) \(meter.denominator))\n"
        out += "(key \(key))\n"
        out += "(tempo \(PolyValue.formatDouble(tempo)))\n"
        out += "(style \(style))\n"
        out += "(part\n    (type chords)\n)\n"
        out += chords
        if !chords.hasSuffix("\n") { out += "\n" }
        return out
    }
}
