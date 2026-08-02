//
//  LeadsheetWriter.swift
//  ImprovisorEngine
//
//  Serializes a chord progression back into Impro-Visor `.ls` leadsheet text —
//  the inverse of the chord side of LeadsheetParser. This lets the app author and
//  save leadsheets, not just read them. Melody serialization is intentionally out
//  of scope here (part of the notation-editor work).
//

import Foundation

public enum LeadsheetWriter {

    /// Reconstruct the bar-delimited chord text (e.g. `Dm7 | / | G7 | / |`) from a
    /// parsed `ChordPart`. Each measure emits the chords that *start* within it
    /// (space-separated, so the parser re-splits the bar evenly), or `/` to hold
    /// the previous chord through an otherwise-empty measure. Wrapped four bars
    /// per line for readability.
    public static func progressionText(_ part: ChordPart, meter: Meter) -> String {
        let slotsPerBar = meter.slotsPerMeasure
        guard slotsPerBar > 0, part.size > 0 else { return "" }
        let bars = Int((Double(part.size) / Double(slotsPerBar)).rounded(.up))

        var tokens: [String] = []
        for bar in 0..<bars {
            let start = bar * slotsPerBar
            let end = start + slotsPerBar
            let starting = part.entries.filter { $0.start >= start && $0.start < end }
            tokens.append(starting.isEmpty ? "/" : starting.map { $0.symbol.name }.joined(separator: " "))
        }

        return stride(from: 0, to: tokens.count, by: 4).map { i in
            tokens[i..<min(i + 4, tokens.count)].joined(separator: " | ") + " |"
        }.joined(separator: "\n")
    }

    /// A complete `.ls` document: metadata header + a chords part + the
    /// progression text. `chords` is bar-delimited chord text (`|` bars, `/`
    /// repeats), such as `progressionText(_:meter:)` or user input produces.
    public static func leadsheet(title: String, composer: String, meter: Meter,
                                 key: Int, tempo: Double, style: String,
                                 chords: String) -> String {
        var out = ""
        out += "(title \(title))\n"
        out += "(composer \(composer))\n"
        out += "(meter \(meter.numerator) \(meter.denominator))\n"
        out += "(key \(key))\n"
        out += "(tempo \(formatTempo(tempo)))\n"
        out += "(style \(style))\n"
        out += "(part\n    (type chords)\n)\n"
        out += chords
        if !chords.hasSuffix("\n") { out += "\n" }
        return out
    }

    private static func formatTempo(_ tempo: Double) -> String {
        tempo == tempo.rounded() ? String(Int(tempo)) : String(tempo)
    }
}
