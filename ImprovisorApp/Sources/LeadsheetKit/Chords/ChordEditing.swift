//
//  ChordEditing.swift
//  LeadsheetKit
//
//  Bar-level chord editing for the chord row: a measure's chords as shorthand
//  text (`Dm7 G7`, `/`, `C / A7 /`) and back, plus transposition commands.
//

import Foundation
import ImprovisorEngine

@MainActor
public extension EditorController {

    /// The chord cells of a measure as text (`Dm7 G7`).
    func chordText(forMeasure measure: Int) -> String {
        let spm = max(1, meter.slotsPerMeasure)
        guard score.chordPart.size > 0 else { return "" }
        let cells = LeadsheetWriter.chordCells(score.chordPart, measure: measure, slotsPerBar: spm)
        return cells.joined(separator: " ")
    }

    /// Unknown chord tokens in a bar's text (for validation highlighting).
    func unknownChordTokens(in text: String) -> [String] {
        text.split(separator: " ").map(String.init).filter { !ChordCompleter.isKnown($0, vocabulary: DataLibrary.shared.vocabulary) }
    }

    /// Replace a measure's chords with the chords in `text`. A leading `/`
    /// (or empty text) holds the previous bar's chord.
    func commitChordText(_ rawText: String, forMeasure measure: Int) {
        let spm = max(1, meter.slotsPerMeasure)
        let vocabulary = DataLibrary.shared.vocabulary
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "|", with: " ").trimmingCharacters(in: .whitespaces)
        let start = measure * spm
        let previous = score.chordPart.chord(at: max(0, start - 1))?.name ?? ChordSymbol.noChordName
        if text.isEmpty { text = previous }
        else if text.hasPrefix("/") { text = previous + text.dropFirst() }

        var part = LeadsheetParser.chordPart(fromText: text + " |", meter: meter, vocabulary: vocabulary)
        guard part.size > 0 else { return }
        part.truncate(to: spm)
        let range = start..<(start + spm)
        document.perform("Change Chords", undoManager: undoManager) { s in
            var chords = s.chordPart
            chords.extendToCover(range.upperBound)
            s.chordPart = chords.replacing(range: range, with: part)
        }
    }

    /// Transpose chords, melody, or both by `semitones` over the selection
    /// (or the whole tune when nothing is selected).
    func transpose(_ scope: ClipboardScope, by semitones: Int) {
        guard semitones != 0 else { return }
        let range = selection ?? 0..<formSlots
        let vocabulary = DataLibrary.shared.vocabulary
        let index = partIndex
        document.perform("Transpose", undoManager: undoManager) { s in
            if scope != .melody {
                s.chordPart = s.chordPart.transposed(range: range, by: semitones, key: s.key, vocabulary: vocabulary)
            }
            if scope != .chords, index < s.melodyParts.count {
                s.melodyParts[index].transpose(range: range, by: semitones)
            }
        }
    }
}

public extension ChordPart {
    /// Pad with the last chord (or NC) so the part reaches `total` slots.
    mutating func extendToCover(_ total: Int) {
        guard total > size else { return }
        if entries.isEmpty { append(.noChord, duration: total) } else { extendLast(by: total - size) }
    }

    /// Cut to `total` slots.
    mutating func truncate(to total: Int) {
        guard total < size else { return }
        self = slice(0..<total)
    }
}
