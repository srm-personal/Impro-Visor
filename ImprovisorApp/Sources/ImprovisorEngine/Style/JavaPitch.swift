//
//  JavaPitch.swift
//  ImprovisorEngine
//
//  The handful of imp.data.PitchClass / NoteSymbol operations the
//  accompaniment engine depends on, expressed on MIDI numbers. A Java
//  NoteSymbol is (pitch class, octave); everything the engine does with one —
//  enharmonic tests, transposition, semitone distances, MIDI value — is a
//  function of semitone and octave, i.e. of its MIDI number.
//

import Foundation

enum JavaPitch {
    /// Pitch classes with Java `sharpPreference == true` (PitchClass.java:125-131).
    private static let sharpPreference: Set<String> = ["g", "d", "a", "e", "b", "f#", "c#"]

    /// `PitchClass.findRise(to)`: semitones from C to `to`, made NEGATIVE for
    /// pitch classes that prefer flats (F, Bb, Eb, Ab, Db, Gb …) so that
    /// transposing a C-rooted spelling moves DOWN for those roots.
    static func rise(_ to: PitchClass) -> Int {
        let rise = to.semitones
        if rise > 0 && !sharpPreference.contains(to.name) { return rise - 12 }
        return rise
    }

    static func pc(_ midi: Int) -> Int { ((midi % 12) + 12) % 12 }

    /// `NoteSymbol.enharmonic`.
    static func enharmonic(_ a: Int, _ b: Int) -> Bool { pc(a) == pc(b) }

    /// `this.getSemitonesAbove(other)`: (other − this) by pitch class, in 1…12.
    static func semitonesAbove(_ this: Int, _ other: Int) -> Int {
        var distance = pc(other) - pc(this)
        while distance <= 0 { distance += 12 }
        return distance
    }

    /// `NoteSymbol.enhDrop`: remove notes enharmonic to `toDrop`, keeping order.
    static func enhDrop(_ notes: [Int], _ toDrop: Int) -> [Int] {
        notes.filter { !enharmonic($0, toDrop) }
    }
}
