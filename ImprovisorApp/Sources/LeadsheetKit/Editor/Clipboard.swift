//
//  Clipboard.swift
//  LeadsheetKit
//
//  Melody and chord clipboard contents, serialized as leadsheet text so they
//  also paste as plain text (and can be pasted from text).
//

import AppKit
import ImprovisorEngine

public struct Clip: Equatable, Sendable {
    public var melody: [MusicEvent]?
    public var chords: ChordPart?
    public var meter: Meter

    public init(melody: [MusicEvent]? = nil, chords: ChordPart? = nil, meter: Meter = .fourFour) {
        self.melody = melody
        self.chords = chords
        self.meter = meter
    }

    public var isEmpty: Bool { melody == nil && chords == nil }

    /// Plain-text form: chord text on the first line(s), melody tokens after `;`.
    public var text: String {
        var parts: [String] = []
        if let chords, chords.size > 0 { parts.append(LeadsheetWriter.progressionText(chords, meter: meter)) }
        if let melody { parts.append(melody.map(NoteSerializer.token).joined(separator: " ")) }
        return parts.joined(separator: "\n;\n")
    }

    /// Parse the plain-text form.
    public static func parse(_ text: String, meter: Meter, vocabulary: Vocabulary) -> Clip {
        let sections = text.components(separatedBy: "\n;\n")
        var clip = Clip(meter: meter)
        for section in sections {
            let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let first = trimmed.first, first.isLowercase {
                clip.melody = NoteSymbol.parseMelody(trimmed)
            } else {
                let part = LeadsheetParser.chordPart(fromText: trimmed, meter: meter, vocabulary: vocabulary)
                if part.size > 0 { clip.chords = part }
            }
        }
        return clip
    }
}

@MainActor
public enum Clipboard {
    public static let pasteboardType = NSPasteboard.PasteboardType("com.srmorin.leadsheetstudio.clip")

    /// In-process copy (tests, and a fallback when the pasteboard is unavailable).
    public static var local: Clip?

    public static func write(_ clip: Clip, to pasteboard: NSPasteboard? = .general) {
        local = clip
        guard let pasteboard else { return }
        pasteboard.clearContents()
        pasteboard.setString(clip.text, forType: pasteboardType)
        pasteboard.setString(clip.text, forType: .string)
    }

    public static func read(meter: Meter, vocabulary: Vocabulary, from pasteboard: NSPasteboard? = .general) -> Clip? {
        if let pasteboard, let text = pasteboard.string(forType: pasteboardType) ?? pasteboard.string(forType: .string) {
            // Our own copy: use the exact in-process clip (text loses sub-bar chord durations).
            if let local, local.text == text { return local }
            let clip = Clip.parse(text, meter: meter, vocabulary: vocabulary)
            if !clip.isEmpty { return clip }
        }
        return local
    }
}
