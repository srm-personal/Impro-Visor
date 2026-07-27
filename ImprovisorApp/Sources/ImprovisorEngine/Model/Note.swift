//
//  Note.swift
//  ImprovisorEngine
//
//  Note / Rest value types and the leadsheet note-string parser (a port of the
//  parsing half of imp/data/NoteSymbol and Note). In the Java model Note and
//  Rest both extend `Unit`; here a `MusicEvent` enum plays that role.
//

import Foundation

/// A sounding note: a MIDI pitch with a slot duration and a MIDI velocity.
public struct Note: Equatable, Hashable {
    /// MIDI note number, 0–127.
    public var pitch: Int
    /// Duration in slots.
    public var duration: Int
    /// MIDI velocity, 0–127.
    public var volume: Int

    public static let defaultVolume = 85

    public init(pitch: Int, duration: Int, volume: Int = Note.defaultVolume) {
        self.pitch = pitch
        self.duration = duration
        self.volume = volume
    }

    /// This note transposed by a number of semitones.
    public func transposed(by semitones: Int) -> Note {
        Note(pitch: pitch + semitones, duration: duration, volume: volume)
    }

    /// The note's pitch class.
    public var pitchClass: PitchClass { PitchClass.forMidi(pitch) }
}

/// A silence of a given slot duration.
public struct Rest: Equatable, Hashable {
    public var duration: Int
    public init(duration: Int) { self.duration = duration }
}

/// One element of a melody: either a note or a rest (the `Unit` role in Java).
public enum MusicEvent: Equatable, Hashable {
    case note(Note)
    case rest(Rest)

    /// Duration in slots, regardless of kind.
    public var duration: Int {
        switch self {
        case let .note(n): return n.duration
        case let .rest(r): return r.duration
        }
    }

    public var isRest: Bool {
        if case .rest = self { return true }
        return false
    }

    public var note: Note? {
        if case let .note(n) = self { return n }
        return nil
    }
}

/// Parsing of leadsheet note tokens such as `a-8`, `r8`, `c+4`, `d#8/3`.
public enum NoteSymbol {

    /// Parse a single leadsheet note/rest token into a `MusicEvent`.
    /// `transposition` shifts the pitch class by that many semitones (used when
    /// a part carries a key transposition). Returns `nil` for an unparseable
    /// token (mirrors `makeNoteSymbol` returning null).
    public static func parse(_ token: String, transposition: Int = 0) -> MusicEvent? {
        let string = token.lowercased()
        let chars = Array(string)
        let len = chars.count
        guard len > 0 else { return nil }

        // Rest: leading 'r'.
        if chars[0] == "r" {
            return .rest(Rest(duration: Duration.slots(String(chars[1...]))))
        }

        guard PitchClass.isValidPitchStart(chars[0]) else { return nil }

        // Note base: letter + optional accidental (#, b, or 's' == sharp).
        var noteBase = String(chars[0])
        var index = 1
        if index < len {
            let second = chars[1]
            if second == "#" || second == "b" || second == "s" {
                index += 1
                noteBase.append(second == "s" ? "#" : second)
            }
        }

        guard var pitchClass = PitchClass.named(noteBase) else { return nil }
        pitchClass = pitchClass.transposed(by: transposition)

        // Octave shifts: '+' / 'u' up, '-' down.
        var octave = 0
        loop: while index < len {
            switch chars[index] {
            case "+", "u": octave += 1; index += 1
            case "-": octave -= 1; index += 1
            default: break loop
            }
        }

        let duration = Duration.slots(String(chars[index...]))
        let midi = Constants.CMIDI + pitchClass.semitones + 12 * octave
        return .note(Note(pitch: midi, duration: duration))
    }

    /// Parse a whitespace-separated run of note tokens into a list of events.
    /// Tokens that fail to parse are skipped (matching the Java reader, which
    /// drops unrecognized melody tokens rather than aborting the file).
    public static func parseMelody(_ text: String, transposition: Int = 0) -> [MusicEvent] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" })
            .compactMap { parse(String($0), transposition: transposition) }
    }
}
