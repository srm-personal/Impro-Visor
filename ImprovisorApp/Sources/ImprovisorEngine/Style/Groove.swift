//
//  Groove.swift
//  ImprovisorEngine
//
//  Applies swing feel to a stream of ScheduledNotes. Port of imp/data/Part
//  .makeSwing: within each beat, the offbeat eighth (the "and", at slot
//  beatValue/2) is delayed to `int(beatValue * swing)` — e.g. slot 60 → 80 at
//  swing 0.67 — producing the classic long-short triplet feel. Straight time
//  (swing 0.5) is a no-op.
//
//  The generators emit straight slot positions on purpose (their output is
//  golden-tested); this is a separate pass applied before MIDI export/playback.
//  It stays entirely in the integer slot/tick model — MIDI has no swing of its
//  own, so swing is just a matter of where each onset's tick is placed.
//
//  Faithful details ported from makeSwing:
//   - Only the offbeat eighth moves, and only if the beat is NOT subdivided into
//     sixteenths (no onset at slot beatValue/4) — you don't swing a run of 16ths.
//   - It moves only if that offbeat is rhythmically at least an eighth long
//     (the gap to the next onset ≥ beatValue/2).
//   - The moved note keeps its end tick (its duration shrinks by the shift), and
//     any note that ended exactly at the old onset is extended to the new onset
//     (the long-short shape; equivalent to makeSwing's rhythm-from-gaps recompute).
//
//  Polyphony: a chord strike is several notes sharing one onset; they move as a
//  group, matching how makeSwing treats one Unit per slot.
//

import Foundation

public enum Groove {

    /// Swing one track's notes. `swing` is the offbeat ratio (0.5 straight,
    /// 0.67 triplet). Order is preserved.
    public static func swung(_ notes: [ScheduledNote], swing: Double,
                             beatValue: Int = Constants.BEAT) -> [ScheduledNote] {
        let offset = Int(Double(beatValue) * swing)   // new offbeat slot within the beat
        let half = beatValue / 2                        // straight offbeat slot
        let shift = offset - half
        guard shift != 0, !notes.isEmpty else { return notes }

        let onsets = Set(notes.map(\.startTick))
        let sortedOnsets = onsets.sorted()
        let maxTick = sortedOnsets.last ?? 0

        var result = notes
        var beat = 0
        while beat <= maxTick {
            let sixteenth = beat + beatValue / 4   // second sixteenth position
            let offbeat = beat + half              // the "and" of the beat

            // Swing only an un-subdivided beat that has an offbeat onset.
            if !onsets.contains(sixteenth), onsets.contains(offbeat) {
                // Rhythmic length of the offbeat = gap to the next onset.
                let nextOnset = sortedOnsets.first { $0 > offbeat }
                let group = result.indices.filter { result[$0].startTick == offbeat }
                let rhythm = nextOnset.map { $0 - offbeat }
                    ?? (group.map { result[$0].startTick + result[$0].duration }.max() ?? 0) - offbeat

                if rhythm >= half {
                    // Delay the offbeat group, keeping each note's end fixed.
                    for i in group {
                        result[i].startTick += shift
                        result[i].duration = max(1, result[i].duration - shift)
                    }
                    // Extend notes that ended at the old onset up to the new one.
                    for i in result.indices where result[i].startTick + result[i].duration == offbeat {
                        result[i].duration += shift
                    }
                }
            }
            beat += beatValue
        }
        return result
    }
}
