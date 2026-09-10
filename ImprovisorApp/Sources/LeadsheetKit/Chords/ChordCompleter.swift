//
//  ChordCompleter.swift
//  LeadsheetKit
//
//  Autocomplete for chord symbols: given what the user has typed so far, the
//  most likely chord names from the vocabulary — the typed root first, then
//  common types, then everything else matching the prefix.
//

import Foundation
import ImprovisorEngine

public enum ChordCompleter {
    /// Types offered first (in order) when the type is still empty or short.
    static let commonTypes = ["", "7", "m7", "M7", "maj7", "6", "m", "9", "m6", "13", "7b9", "7#9", "m9", "M9", "sus4", "7sus4", "dim7", "m7b5", "7#11", "7alt", "M6", "69", "m69", "7b13", "+", "o7"]
    static let roots = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]

    /// Suggestions for `prefix` (a single chord token being typed).
    public static func suggest(_ prefix: String, vocabulary: Vocabulary, limit: Int = 12) -> [String] {
        let text = prefix.trimmingCharacters(in: .whitespaces)
        guard let first = text.first else { return roots.filter { $0.count == 1 } + ["NC"] }
        if text.uppercased() == "N" || text.uppercased() == "NC" { return ["NC"] }
        guard first.isLetter, ("A"..."G").contains(first.uppercased()) else { return [] }

        // Split the root (letter + optional accidental) from the type prefix.
        var root = String(first).uppercased()
        var rest = text.dropFirst()
        if let acc = rest.first, acc == "#" || acc == "b" {
            root.append(acc)
            rest = rest.dropFirst()
        }
        let typePrefix = String(rest)
        let types = vocabulary.chordTypes
        var out: [String] = []
        func add(_ type: String) {
            let name = root + type
            if !out.contains(name) { out.append(name) }
        }
        // Exact match first.
        if types.contains(typePrefix) { add(typePrefix) }
        for t in commonTypes where t.hasPrefix(typePrefix) && types.contains(t) { add(t) }
        for t in types where t.hasPrefix(typePrefix) { add(t) }
        // Case-insensitive fallback (m vs M).
        if out.count < 3 {
            for t in types where t.lowercased().hasPrefix(typePrefix.lowercased()) { add(t) }
        }
        return Array(out.prefix(limit))
    }

    /// Whether a typed chord name resolves to a known chord form.
    public static func isKnown(_ name: String, vocabulary: Vocabulary) -> Bool {
        if name == ChordSymbol.noChordName || name == "/" { return true }
        guard let symbol = ChordSymbol.parse(name, vocabulary: vocabulary) else { return false }
        return symbol.form != nil
    }
}
