//
//  Duration.swift
//  ImprovisorEngine
//
//  Port of imp/data/Duration.getDuration. Parses leadsheet duration strings
//  into slot counts. A duration is a sum (joined by `+`) of terms; each term is
//  a note-value denominator, optionally tuplet-divided (`/n`) and/or dotted.
//
//  Examples (WHOLE = 480 slots):
//    "4"      -> 120   (quarter)
//    "8"      -> 60    (eighth)
//    "2."     -> 360   (dotted half)
//    "8/3"    -> 40    (eighth triplet: three of them fill a quarter)
//    "1+1+2"  -> 480+480+240
//

import Foundation

public enum Duration {
    /// Default note value when a duration is absent/garbage: an eighth note.
    public static let defaultNumerator = 8
    public static let defaultDuration = Constants.EIGHTH

    /// Parse a duration string to slots, following Duration.getDuration exactly.
    public static func slots(_ item: String) -> Int {
        let chars = Array(item)
        let len = chars.count
        var index = 0

        guard len > 0, chars[0].isNumber else {
            return defaultDuration
        }

        // Whole-string "0" (or leading value 0) means zero duration.
        if let value = Int(item), value == 0 {
            return 0
        }

        var duration = 0
        var firsttime = true

        while index < len && (chars[index] == "+" || firsttime || chars[index] == "u") {
            if firsttime {
                firsttime = false // no leading '+'
            } else {
                index += 1 // skip infix '+'
            }

            // Numerator (the note-value denominator, e.g. 4 for a quarter).
            var digits = ""
            while index < len && chars[index].isNumber {
                digits.append(chars[index])
                index += 1
            }
            let numerator = digits.isEmpty ? defaultNumerator : (Int(digits) ?? defaultNumerator)

            var slots = Constants.WHOLE
            var denominator = 1

            // Tuplet: `/n`.
            if index < len && chars[index] == "/" {
                index += 1
                guard index < len && chars[index].isNumber else {
                    return defaultDuration
                }
                var tup = ""
                while index < len && chars[index].isNumber {
                    tup.append(chars[index])
                    index += 1
                }
                denominator = Int(tup) ?? 1
            }

            if denominator > 1 {
                slots *= (denominator - 1)
            }

            var thisDuration = slots / (numerator * denominator)

            // Dots each add half of the running increment.
            var increment = thisDuration
            while index < len && chars[index] == "." {
                increment /= 2
                thisDuration += increment
                index += 1
            }

            duration += thisDuration
        }

        return duration <= 0 ? defaultDuration : duration
    }

    /// Like `slots`, but an empty/whitespace string yields 0 (Duration.getDuration0).
    public static func slots0(_ item: String) -> Int {
        item.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : slots(item)
    }
}
