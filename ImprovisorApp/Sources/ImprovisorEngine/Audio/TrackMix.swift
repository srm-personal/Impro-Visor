//
//  TrackMix.swift
//  ImprovisorEngine
//
//  Per-channel mix settings applied live by Transport at event-delivery time
//  (never baked into the loaded timeline), so muting/volume changes take
//  effect on the very next scheduled event.
//

import Foundation

public struct TrackMix: Equatable, Sendable {
    /// Linear gain, 0…1. Applied to note-on velocity alongside master volume.
    public var volume: Double
    /// When true, note-ons on this channel are dropped (note-offs still pass
    /// through, so a note muted mid-sustain doesn't hang).
    public var muted: Bool

    public init(volume: Double = 1.0, muted: Bool = false) {
        self.volume = min(1, max(0, volume))
        self.muted = muted
    }
}
