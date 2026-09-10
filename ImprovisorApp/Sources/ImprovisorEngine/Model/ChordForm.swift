//
//  ChordForm.swift
//  ImprovisorEngine
//
//  Port of imp/data/ChordForm plus the vocabulary loader that reads chord
//  definitions from vocab/My.voc. Each definition is C-rooted, e.g.
//
//    (chord (name CM7) (key c) (family major)
//           (spell c8 e8 g8 b8) (color a8 d8 f#8) (priority e8 g8 c8)
//           (approach ...) (voicings ...))
//
//  and alias entries reference a canonical form:
//
//    (chord (name Cmaj7) (pronounce) (same CM7))
//
//  A ChordSymbol like "Dm7" is resolved by looking up "C"+type ("Cm7") and
//  transposing the C-rooted spelling to the actual root.
//

import Foundation

/// The interval content of a chord *type* (C-rooted), as loaded from the vocab.
public struct ChordForm: Equatable, Sendable {
    /// Canonical C-rooted name, e.g. `CM7`.
    public let name: String
    /// Family/quality label, e.g. `major`, `minor`, `dominant`.
    public let family: String
    /// Chord tones as pitch classes (C-rooted), from `spell`.
    public let spell: [PitchClass]
    /// Color tones as pitch classes (C-rooted), from `color`.
    public let color: [PitchClass]
    /// Priority tones as pitch classes (C-rooted), from `priority`, in the order
    /// listed (most important first). Used by both voicers.
    public let priority: [PitchClass]
    /// The named voicings (C-rooted absolute MIDI), from `voicings`.
    public let voicings: [Voicing]
    /// Scales usable over this chord, as `(root type)` pairs relative to the
    /// C-rooted form (e.g. `(G major pentatonic)` over CM7), first = preferred.
    public let scales: [ScaleReference]

    public init(name: String, family: String, spell: [PitchClass], color: [PitchClass],
                priority: [PitchClass] = [], voicings: [Voicing] = [], scales: [ScaleReference] = []) {
        self.name = name
        self.family = family
        self.spell = spell
        self.color = color
        self.priority = priority
        self.voicings = voicings
        self.scales = scales
    }

    /// The chord tones transposed so the chord's root is `root`.
    public func chordTones(root: PitchClass) -> [PitchClass] {
        spell.map { $0.transposed(by: root.semitones) }
    }

    /// The color tones transposed to the given root.
    public func colorTones(root: PitchClass) -> [PitchClass] {
        color.map { $0.transposed(by: root.semitones) }
    }

    /// The priority tones transposed to the given root, in priority order.
    public func priorityTones(root: PitchClass) -> [PitchClass] {
        priority.map { $0.transposed(by: root.semitones) }
    }

    /// The named voicings transposed so the chord's root is `root`.
    public func voicings(root: PitchClass) -> [Voicing] {
        voicings.map { $0.transposed(by: root.semitones) }
    }

    /// Pitch classes of the preferred (first-listed) scale for this chord at
    /// `root`, resolved through `vocabulary`; empty if none is known.
    public func firstScaleTones(root: PitchClass, vocabulary: Vocabulary) -> [PitchClass] {
        guard let ref = scales.first else { return [] }
        return vocabulary.scaleTones(ref, chordRoot: root)
    }
}

/// A scale named in a chord form's `(scales …)` list: `(G major pentatonic)`
/// → root G (relative to the C-rooted form), type `major pentatonic`.
public struct ScaleReference: Equatable, Hashable, Sendable {
    public let root: PitchClass
    public let type: String

    public init(root: PitchClass, type: String) {
        self.root = root
        self.type = type
    }
}

/// Loads and indexes the chord (and, later, scale) definitions from a vocabulary
/// file. Resolves alias (`same`) chains to their canonical spelled form.
/// Immutable after construction, hence safely `Sendable`.
public final class Vocabulary: Sendable {
    private let forms: [String: ChordForm]
    private let aliases: [String: String]
    /// Scale spellings at root C, keyed by type (`major`, `bebop dominant`, …).
    private let scales: [String: [PitchClass]]

    public init(source: String) {
        var forms: [String: ChordForm] = [:]
        var aliases: [String: String] = [:]
        var scales: [String: [PitchClass]] = [:]

        for form in PolyaParser.parseAll(source) {
            guard case let .list(list) = form else { continue }

            // (scale (name C major) (spell c d e f g a b c))
            if list.firstOrNil() == .symbol("scale") {
                if let nameList = list.assoc("name") {
                    let words = nameList.rest().toArray().compactMap(\.symbolValue)
                    if words.count >= 2, let root = PitchClass.named(words[0].lowercased()) {
                        let type = words.dropFirst().joined(separator: " ")
                        let spelled = Vocabulary.pitchClasses(list.assoc("spell"))
                            .map { $0.transposed(by: -root.semitones) }
                        // Drop the repeated octave note if present.
                        var tones: [PitchClass] = []
                        for pc in spelled where !tones.contains(where: { $0.semitones == pc.semitones }) { tones.append(pc) }
                        scales[type] = tones
                    }
                }
                continue
            }

            guard list.firstOrNil() == .symbol("chord"),
                  let nameList = list.assoc("name"),
                  case let .symbol(name)? = nameList.secondOrNil()
            else { continue }

            if let sameList = list.assoc("same"),
               case let .symbol(target)? = sameList.secondOrNil() {
                aliases[name] = target
                continue
            }

            let spell = Vocabulary.pitchClasses(list.assoc("spell"))
            let color = Vocabulary.pitchClasses(list.assoc("color"))
            let priority = Vocabulary.pitchClasses(list.assoc("priority"))
            let voicings = Vocabulary.voicings(list.assoc("voicings"))
            let family = list.assoc("family").flatMap { $0.secondOrNil()?.symbolValue } ?? "unknown"
            let scaleRefs = Vocabulary.scaleReferences(list.assoc("scales"))
            forms[name] = ChordForm(name: name, family: family, spell: spell, color: color,
                                    priority: priority, voicings: voicings, scales: scaleRefs)
        }

        self.forms = forms
        self.aliases = aliases
        self.scales = scales
    }

    /// Parse `(scales (C major) (G major pentatonic) …)`.
    private static func scaleReferences(_ list: Polylist?) -> [ScaleReference] {
        guard let list else { return [] }
        return list.rest().toArray().compactMap { entry -> ScaleReference? in
            guard case let .list(pair) = entry else { return nil }
            let words = pair.toArray().compactMap(\.symbolValue)
            guard words.count >= 2, let root = PitchClass.named(words[0].lowercased()) else { return nil }
            return ScaleReference(root: root, type: words.dropFirst().joined(separator: " "))
        }
    }

    /// The C-rooted spelling of a scale type (e.g. `"major"`), or `nil`.
    public func scale(named type: String) -> [PitchClass]? { scales[type] }

    /// Number of scale types loaded.
    public var scaleCount: Int { scales.count }

    /// Pitch classes of `ref` (a scale relative to a C-rooted chord form) when
    /// the chord is played at `chordRoot`.
    public func scaleTones(_ ref: ScaleReference, chordRoot: PitchClass) -> [PitchClass] {
        guard let base = scales[ref.type] else { return [] }
        let shift = ref.root.semitones + chordRoot.semitones
        return base.map { $0.transposed(by: shift) }
    }

    /// Convenience: build a vocabulary from a `.voc` file on disk.
    public convenience init(contentsOf url: URL) throws {
        self.init(source: try String(contentsOf: url, encoding: .utf8))
    }

    /// Extract pitch classes from a `(spell c8 e8 …)` / `(color …)` sub-list,
    /// dropping the leading keyword.
    private static func pitchClasses(_ list: Polylist?) -> [PitchClass] {
        guard let list else { return [] }
        return list.rest().toArray().compactMap { value in
            value.symbolValue.flatMap { PitchClass.parse($0) }
        }
    }

    /// Parse a `(notes e-8 g-8 c8)` / `(extension …)` sub-list into absolute MIDI
    /// pitches, dropping the leading keyword.
    private static func midiNotes(_ list: Polylist?) -> [Int] {
        guard let list else { return [] }
        return list.rest().toArray().compactMap { value in
            value.symbolValue.flatMap { NoteSymbol.parse($0)?.note?.pitch }
        }
    }

    /// Parse a `(voicings (id (type t)(notes …)(extension …)) …)` sub-list.
    private static func voicings(_ list: Polylist?) -> [Voicing] {
        guard let list else { return [] }
        return list.rest().toArray().compactMap { entry -> Voicing? in
            guard case let .list(v) = entry,
                  case let .symbol(name)? = v.firstOrNil()
            else { return nil }
            let type = v.assoc("type").flatMap { $0.secondOrNil()?.symbolValue } ?? ""
            let notes = midiNotes(v.assoc("notes"))
            let ext = midiNotes(v.assoc("extension"))
            return Voicing(name: name, type: type, notes: notes, ext: ext)
        }
    }

    /// Resolve a C-rooted chord type name (e.g. `Cm7`) to its `ChordForm`,
    /// following alias chains. Returns `nil` if unknown.
    public func chordForm(named name: String) -> ChordForm? {
        var current = name
        var seen = Set<String>()
        while forms[current] == nil, let next = aliases[current], !seen.contains(current) {
            seen.insert(current)
            current = next
        }
        return forms[current]
    }

    /// Every C-rooted chord name known: spelled forms plus aliases.
    public var allChordFormNames: [String] { Array(forms.keys) + Array(aliases.keys) }

    /// Number of spelled chord forms loaded (for diagnostics/tests).
    public var formCount: Int { forms.count }
    /// Number of alias entries loaded (for diagnostics/tests).
    public var aliasCount: Int { aliases.count }
}
