//
//  Constants.swift
//  ImprovisorEngine
//
//  Timing (slot) and MIDI constants ported from imp/Constants.java.
//
//  The slot system: durations and positions are integers measured in "slots".
//  There are 120 slots per beat / quarter note, so a whole note is 480 slots.
//  Using integers avoids floating-point drift and matches every data file.
//

import Foundation

public enum Constants {
    // MARK: Slot durations (imp/Constants.java)

    /// Slots per beat (a quarter note in 4/4). The fundamental unit.
    public static let BEAT = 120
    /// Slots in a whole note (4 beats).
    public static let WHOLE = 480
    public static let HALF = WHOLE / 2        // 240
    public static let QUARTER = WHOLE / 4     // 120
    public static let EIGHTH = WHOLE / 8      // 60
    public static let SIXTEENTH = WHOLE / 16  // 30
    public static let THIRTYSECOND = WHOLE / 32 // 15

    // MARK: MIDI

    /// MIDI note number of middle C (C in octave 0 of the NoteSymbol system).
    public static let CMIDI = 60
    /// Semitones per octave.
    public static let OCTAVE = 12

    /// Sentinel pitch used to mark a rest in some Java code paths.
    public static let REST = -1

    /// General MIDI drum channel (0-based channel 9 == "channel 10").
    public static let DRUM_CHANNEL: UInt8 = 9

    // MARK: Default instruments (General MIDI program numbers)

    public static let DEFAULT_PIANO_PROGRAM: UInt8 = 0   // Acoustic Grand
    public static let DEFAULT_BASS_PROGRAM: UInt8 = 33   // Electric Bass (finger)
}
