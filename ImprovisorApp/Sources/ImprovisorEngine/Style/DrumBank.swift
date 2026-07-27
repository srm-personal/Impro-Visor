//
//  DrumBank.swift
//  ImprovisorEngine
//
//  Maps the spaceless General MIDI percussion names used in style files
//  (`Ride_Cymbal_1`, `Closed_Hi-Hat`, `Acoustic_Snare`, …) to their MIDI note
//  numbers. Ported from imp/midi/MIDIBeast.spacelessDrumName, where the array
//  index + 35 is the GM percussion number.
//

import Foundation

public enum DrumBank {
    /// GM percussion names in order; index + 35 == MIDI note number.
    static let names: [String] = [
        "Acoustic_Bass_Drum", "Bass_Drum_1", "Side_Stick", "Acoustic_Snare",
        "Hand_Clap", "Electric_Snare", "Low_Floor_Tom", "Closed_Hi-Hat",
        "High_Floor_Tom", "Pedal_Hi-Hat", "Low_Tom", "Open_Hi-Hat",
        "Low-Mid_Tom", "Hi-Mid_Tom", "Crash_Cymbal_1", "High_Tom",
        "Ride_Cymbal_1", "Chinese_Cymbal", "Ride_Bell", "Tambourine",
        "Splash_Cymbal", "Cowbell", "Crash_Cymbal_2", "Vibraslap",
        "Ride_Cymbal_2", "Hi_Bongo", "Low_Bongo", "Mute_Hi_Conga",
        "Open_Hi_Conga", "Low_Conga", "High_Timbale", "Low_Timbale",
        "High_Agogo", "Low_Agogo", "Cabasa", "Maracas",
        "Short_Whistle", "Long_Whistle", "Short_Guiro", "Long_Guiro",
        "Claves", "Hi_Wood_Block", "Low_Wood_Block", "Mute_Cuica",
        "Open_Cuica", "Mute_Triangle", "Open_Triangle"
    ]

    private static let baseNumber = 35

    private static let byName: [String: Int] = {
        var map: [String: Int] = [:]
        for (index, name) in names.enumerated() {
            map[name] = index + baseNumber
        }
        return map
    }()

    /// MIDI note number for a drum instrument name, or `nil` if unknown.
    public static func midi(for name: String) -> Int? {
        byName[name]
    }
}
