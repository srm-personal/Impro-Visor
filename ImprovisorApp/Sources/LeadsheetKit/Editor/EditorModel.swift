//
//  EditorModel.swift
//  LeadsheetKit
//
//  Value types for the notation editor: the entry state (what the next typed
//  note will be), key events, the actions they map to, and the key map itself.
//

import Foundation
import ImprovisorEngine

/// What the next entered note/rest looks like.
public struct EntryState: Equatable, Sendable {
    public var base: NoteValue.Base = .eighth
    public var dotted = false
    public var triplet = false
    /// Harmonic (snap mouse pitches to chord tones) vs. simple (chromatic) entry.
    public var mode: ToneMode = .chordAndColor
    public var harmonic = true
    /// The next entered/clicked note is snapped to an approach tone.
    public var approachNext = false

    public init() {}

    public var value: NoteValue { NoteValue(base, dots: dotted ? 1 : 0, tuplet: triplet ? 3 : 1) }
    public var slots: Int { value.slots }
}

public struct KeyEvent: Equatable, Sendable {
    public enum Special: Equatable, Sendable { case up, down, left, right, delete, forwardDelete, escape, `return`, space, tab }
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let command = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }
    /// Typed character (lower-cased for letters), or empty for special keys.
    public var character: String
    public var special: Special?
    public var modifiers: Modifiers

    public init(_ character: String, modifiers: Modifiers = []) {
        self.character = character.lowercased()
        self.special = nil
        self.modifiers = modifiers
    }

    public init(special: Special, modifiers: Modifiers = []) {
        self.character = ""
        self.special = special
        self.modifiers = modifiers
    }
}

public enum EditorAction: Equatable, Sendable {
    case enterPitch(letter: Int, octaveShift: Int)
    case setBase(NoteValue.Base)
    case toggleDot
    case toggleTriplet
    case tie
    case rest
    case eraseSelection
    case removeSelection
    case moveCursor(Int)
    case extendSelection(Int)
    case nudgeSelection(Int)          // move selected notes in time by ± current duration
    case stepPitch(Int)               // diatonic steps
    case transpose(Int)               // semitones
    case toggleHarmonic
    case approachNext
    case toggleEnharmonic
    case playPause
    case playSelection
    case stop
    case toggleLoop
    case tempoDelta(Double)
    case undo
    case redo
    case cut(ClipboardScope)
    case copy(ClipboardScope)
    case paste(ClipboardScope)
    case selectAll
    case escape
    case focusChords
    case generateSolo
}

public enum ClipboardScope: Equatable, Sendable { case melody, chords, both }

/// The keyboard layout of the editor (see the plan's key table).
public enum KeyMap {
    public static func action(for key: KeyEvent) -> EditorAction? {
        let m = key.modifiers
        if let special = key.special {
            switch special {
            case .up: return m.contains(.command) ? .transpose(12) : (m.contains(.option) ? .transpose(1) : .stepPitch(1))
            case .down: return m.contains(.command) ? .transpose(-12) : (m.contains(.option) ? .transpose(-1) : .stepPitch(-1))
            case .left: return m.contains(.shift) ? .extendSelection(-1) : (m.contains(.option) ? .nudgeSelection(-1) : .moveCursor(-1))
            case .right: return m.contains(.shift) ? .extendSelection(1) : (m.contains(.option) ? .nudgeSelection(1) : .moveCursor(1))
            case .delete, .forwardDelete: return m.contains(.option) ? .removeSelection : .eraseSelection
            case .escape: return .escape
            case .return: return .playSelection
            case .space: return .playPause
            case .tab: return nil
            }
        }
        let scope: ClipboardScope = m.contains(.option) ? .both : (m.contains(.shift) ? .chords : .melody)
        if m.contains(.command) {
            switch key.character {
            case "z": return m.contains(.shift) ? .redo : .undo
            case "x": return .cut(scope)
            case "c": return .copy(scope)
            case "v": return .paste(scope)
            case "a": return .selectAll
            case "l": return .toggleLoop
            case "k": return m.contains(.shift) ? .focusChords : nil
            case "g": return m.contains(.shift) ? .generateSolo : nil
            case ".": return .stop
            default: return nil
            }
        }
        switch key.character {
        case "a", "b", "c", "d", "e", "f", "g":
            let letter = ["c": 0, "d": 1, "e": 2, "f": 3, "g": 4, "a": 5, "b": 6][key.character]!
            if key.character == "a", m.contains(.shift), !m.contains(.option) { return .approachNext }
            let octave = m.contains(.shift) ? 1 : (m.contains(.option) ? -1 : 0)
            return .enterPitch(letter: letter, octaveShift: octave)
        case "1": return .setBase(.whole)
        case "2": return .setBase(.half)
        case "4": return .setBase(.quarter)
        case "8": return .setBase(.eighth)
        case "6": return .setBase(.sixteenth)
        case "3": return .toggleTriplet
        case ".": return .toggleDot
        case "-": return .tie
        case "r": return .rest
        case "h": return .toggleHarmonic
        case "=": return .toggleEnharmonic
        case "k": return .stop
        case "[": return .tempoDelta(-5)
        case "]": return .tempoDelta(5)
        default: return nil
        }
    }
}
