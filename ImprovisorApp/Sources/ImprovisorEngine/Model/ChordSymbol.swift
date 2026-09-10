//
//  ChordSymbol.swift
//  ImprovisorEngine
//
//  Port of the parsing side of imp/data/ChordSymbol. Splits a chord name like
//  `Dm7`, `Cmaj7#11`, `G7b9`, or the slash chord `C/E` into root, type, and
//  bass, then resolves the type against a `Vocabulary` (looking up `C`+type)
//  and transposes the C-rooted spelling to the actual root.
//

import Foundation

public struct ChordSymbol: Equatable, Sendable {
    /// The literal chord name as written in the leadsheet, e.g. `Dm7`, `C/E`.
    public let name: String
    /// The root pitch class.
    public let root: PitchClass
    /// The chord type suffix, e.g. `m7`, `maj7#11`, `7b9` (empty for a bare root).
    public let type: String
    /// The bass pitch class (equals `root` unless a slash chord).
    public let bass: PitchClass
    /// The resolved chord form, or `nil` for "no chord" / unknown types.
    public let form: ChordForm?
    /// Pitch classes of the chord's preferred scale (first in the vocab's
    /// `(scales …)` list) at this root; empty if unknown.
    public let scaleTones: [PitchClass]

    /// The literal "no chord" symbol.
    public static let noChordName = "NC"

    /// Whether this is the "no chord" (NC) symbol.
    public var isNoChord: Bool { name == ChordSymbol.noChordName }

    // MARK: Derived pitch content

    /// Chord tones (pitch classes) at this chord's root, or `[]` if unresolved.
    public var chordTones: [PitchClass] {
        form?.chordTones(root: root) ?? []
    }

    /// Color tones (pitch classes) at this chord's root, or `[]` if unresolved.
    public var colorTones: [PitchClass] {
        form?.colorTones(root: root) ?? []
    }

    // MARK: Parsing

    /// Parse a chord name using `vocabulary` to resolve its type. Returns `nil`
    /// if the name has no valid root (mirrors `makeChordSymbol` returning null).
    /// Unknown *types* still parse — `form` is simply `nil`.
    public static func parse(_ name: String, vocabulary: Vocabulary) -> ChordSymbol? {
        if name.isEmpty { return nil }

        if name == noChordName {
            let c = PitchClass.named("c")!
            return ChordSymbol(name: name, root: c, type: noChordName, bass: c, form: nil, scaleTones: [])
        }

        let chars = Array(name)
        let len = chars.count

        // (1) Root: first letter + optional accidental.
        guard PitchClass.isValidPitchStart(chars[0]) else { return nil }
        var rootString = String(chars[0])
        var index = 1
        if index < len, chars[1] == "#" || chars[1] == "b" {
            rootString.append(chars[1])
            index += 1
        }
        guard let root = PitchClass.named(rootString) else { return nil }

        // (2) Type: everything up to a slash or backslash.
        var type = ""
        while index < len, chars[index] != "/", chars[index] != "\\" {
            type.append(chars[index])
            index += 1
        }

        // (3) Slash chord (`/bass`) or polychord (`\base`).
        var bass = root
        if index < len {
            if chars[index] == "/" {
                let bassString = String(chars[(index + 1)...])
                guard let b = PitchClass.named(bassString.lowercased()) else { return nil }
                bass = b
            } else {
                // Polychord: bass comes from the upper structure's root.
                let baseName = String(chars[(index + 1)...])
                if let base = parse(baseName, vocabulary: vocabulary) {
                    bass = base.bass
                }
            }
        }

        let form = vocabulary.chordForm(named: "C" + type)
        let scale = form?.firstScaleTones(root: root, vocabulary: vocabulary) ?? []
        return ChordSymbol(name: name, root: root, type: type, bass: bass, form: form, scaleTones: scale)
    }
}
