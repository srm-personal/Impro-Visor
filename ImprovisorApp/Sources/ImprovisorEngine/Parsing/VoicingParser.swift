//
//  VoicingParser.swift
//  ImprovisorEngine
//
//  Parses a `.fv` voicing preset into `VoicingSettings`. Ports
//  imp/voicing/AutomaticVoicingSettings (the parameter set + defaults) and
//  imp/voicing/AVPFileCreator.fileToSettings (the file decoding). A `.fv` file is
//  a flat list of `(key value)` forms; `value` is an integer or, for the three
//  boolean flags, the symbol `on`/`off`.
//
//  The seven multiplier parameters are stored in the file as `int(value * 10)`
//  (e.g. `(prev-voicing-multiplier 40)` means 4.0) and decoded by dividing by ten,
//  matching AVPFileCreator. These settings drive the algorithmic voicing generator
//  (`Voicing/VoicingGenerator`, `Voicing/HandManager`).
//

import Foundation

/// The full parameter set of an automatic-voicing preset, mirroring Java's
/// `AutomaticVoicingSettings` field-for-field. Defaults are that class's
/// `setDefaults()` values, used when a key is absent from the file.
public struct VoicingSettings: Equatable, Sendable {
    // Hand geometry.
    public var leftHandLowerLimit = 46
    public var rightHandLowerLimit = 60
    public var leftHandUpperLimit = 67
    public var rightHandUpperLimit = 81
    public var leftHandSpread = 9
    public var rightHandSpread = 9
    public var leftHandMinNotes = 1
    public var leftHandMaxNotes = 2
    public var rightHandMinNotes = 1
    public var rightHandMaxNotes = 4

    // Voice-leading controls.
    public var preferredMotion = 0
    public var preferredMotionRange = 3
    public var previousVoicingMultiplier = 4.0
    public var halfStepAwayMultiplier = 3.0
    public var fullStepAwayMultiplier = 2.0

    // Voicing controls.
    public var leftColorPriority = 0
    public var rightColorPriority = 0
    public var maxPriority = 6
    public var priorityMultiplier = 0.667
    public var repeatMultiplier = 0.3
    public var halfStepReducer = 0.0
    public var fullStepReducer = 0.7
    public var invertM9 = false
    public var voiceAll = false
    public var rootless = false
    public var leftMinInterval = 0
    public var rightMinInterval = 0

    /// The raw integer value of each key as it appeared in the file (multiplier
    /// keys keep their `*10` encoding), retained for diagnostics/back-compat.
    public var raw: [String: Int] = [:]

    public init() {}

    /// Raw integer lookup by file key (e.g. `settings["LH-lower-limit"]`).
    public subscript(_ key: String) -> Int? { raw[key] }

    // Back-compat accessors (the Step 3 API exposed just these four).
    public var lhLowerLimit: Int { leftHandLowerLimit }
    public var lhUpperLimit: Int { leftHandUpperLimit }
    public var rhLowerLimit: Int { rightHandLowerLimit }
    public var rhUpperLimit: Int { rightHandUpperLimit }
}

public enum VoicingParser {

    /// Parse voicing-preset text into `VoicingSettings`.
    public static func parse(_ content: String) -> VoicingSettings {
        var s = VoicingSettings()
        for form in PolyaParser.parseAll(content) {
            guard case let .list(list) = form,
                  case let .symbol(key)? = list.firstOrNil(),
                  let valueTok = list.secondOrNil()
            else { continue }

            let int = valueTok.intValue
            if let int { s.raw[key] = int }
            let tenths = int.map { Double($0) / 10.0 }
            let flag = valueTok.symbolValue == "on"

            switch key {
            case "LH-lower-limit": int.map { s.leftHandLowerLimit = $0 }
            case "RH-lower-limit": int.map { s.rightHandLowerLimit = $0 }
            case "LH-upper-limit": int.map { s.leftHandUpperLimit = $0 }
            case "RH-upper-limit": int.map { s.rightHandUpperLimit = $0 }
            case "LH-spread": int.map { s.leftHandSpread = $0 }
            case "RH-spread": int.map { s.rightHandSpread = $0 }
            case "LH-min-notes": int.map { s.leftHandMinNotes = $0 }
            case "LH-max-notes": int.map { s.leftHandMaxNotes = $0 }
            case "RH-min-notes": int.map { s.rightHandMinNotes = $0 }
            case "RH-max-notes": int.map { s.rightHandMaxNotes = $0 }
            case "pref-motion": int.map { s.preferredMotion = $0 }
            case "pref-motion-range": int.map { s.preferredMotionRange = $0 }
            case "prev-voicing-multiplier": tenths.map { s.previousVoicingMultiplier = $0 }
            case "half-step-multiplier": tenths.map { s.halfStepAwayMultiplier = $0 }
            case "full-step-multiplier": tenths.map { s.fullStepAwayMultiplier = $0 }
            case "LH-color-priority": int.map { s.leftColorPriority = $0 }
            case "RH-color-priority": int.map { s.rightColorPriority = $0 }
            case "max-priority": int.map { s.maxPriority = $0 }
            case "priority-multiplier": tenths.map { s.priorityMultiplier = $0 }
            case "repeat-multiplier": tenths.map { s.repeatMultiplier = $0 }
            case "half-step-reducer": tenths.map { s.halfStepReducer = $0 }
            case "full-step-reducer": tenths.map { s.fullStepReducer = $0 }
            case "left-min-interval": int.map { s.leftMinInterval = $0 }
            case "right-min-interval": int.map { s.rightMinInterval = $0 }
            case "invert-9th": s.invertM9 = flag
            case "voice-all": s.voiceAll = flag
            case "rootless": s.rootless = flag
            default: break
            }
        }
        return s
    }

    /// Convenience: parse a `.fv` file from disk.
    public static func parse(contentsOf url: URL) throws -> VoicingSettings {
        try parse(String(contentsOf: url, encoding: .utf8))
    }
}
