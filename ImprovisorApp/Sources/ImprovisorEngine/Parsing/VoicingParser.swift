//
//  VoicingParser.swift
//  ImprovisorEngine
//
//  Parses a `.fv` voicing preset into `VoicingSettings`. Ports the loading of
//  imp/voicing/AutomaticVoicingSettings. A `.fv` file is a flat list of
//  `(key value)` integer settings that bound and bias voice-leading choices.
//  The settings are consumed by the voicing engine (Step 6).
//

import Foundation

/// The integer parameters of an automatic-voicing preset. Unknown keys are kept
/// in `raw` so nothing is lost.
public struct VoicingSettings: Equatable, Sendable {
    public var raw: [String: Int]

    public init(raw: [String: Int] = [:]) {
        self.raw = raw
    }

    public subscript(_ key: String) -> Int? { raw[key] }

    public var lhLowerLimit: Int { raw["LH-lower-limit"] ?? 46 }
    public var lhUpperLimit: Int { raw["LH-upper-limit"] ?? 55 }
    public var rhLowerLimit: Int { raw["RH-lower-limit"] ?? 60 }
    public var rhUpperLimit: Int { raw["RH-upper-limit"] ?? 81 }
}

public enum VoicingParser {

    /// Parse voicing-preset text into `VoicingSettings`.
    public static func parse(_ content: String) -> VoicingSettings {
        var raw: [String: Int] = [:]
        for form in PolyaParser.parseAll(content) {
            guard case let .list(list) = form,
                  case let .symbol(key) = list.firstOrNil(),
                  let value = list.secondOrNil()?.intValue
            else { continue }
            raw[key] = value
        }
        return VoicingSettings(raw: raw)
    }

    /// Convenience: parse a `.fv` file from disk.
    public static func parse(contentsOf url: URL) throws -> VoicingSettings {
        try parse(String(contentsOf: url, encoding: .utf8))
    }
}
