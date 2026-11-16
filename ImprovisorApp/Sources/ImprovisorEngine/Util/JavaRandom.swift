//
//  JavaRandom.swift
//  ImprovisorEngine
//
//  An exact port of java.util.Random (the 48-bit linear congruential generator
//  specified in the JDK documentation), so that the Swift engine draws the same
//  numbers as the Java engine from the same seed. The differential harness
//  (ImprovisorApp/Testing) depends on this being bit-for-bit identical;
//  JavaRandomTests checks it against values produced by a real JVM.
//
//      seed      = (seed ^ 0x5DEECE66D) & ((1 << 48) - 1)
//      next(bits): seed = (seed * 0x5DEECE66D + 0xB) & ((1 << 48) - 1)
//                  return (int)(seed >>> (48 - bits))
//

import Foundation

public struct JavaRandom: Sendable {
    private static let multiplier: UInt64 = 0x5DEECE66D
    private static let addend: UInt64 = 0xB
    private static let mask: UInt64 = (1 << 48) - 1

    private var seed: UInt64

    /// `new Random(seed)`.
    public init(seed: Int64) {
        self.seed = (UInt64(bitPattern: seed) ^ Self.multiplier) & Self.mask
    }

    /// `setSeed(seed)`.
    public mutating func setSeed(_ seed: Int64) {
        self.seed = (UInt64(bitPattern: seed) ^ Self.multiplier) & Self.mask
    }

    /// `next(bits)`: the top `bits` bits of the advanced seed, as a signed 32-bit int.
    public mutating func next(_ bits: Int) -> Int32 {
        seed = (seed &* Self.multiplier &+ Self.addend) & Self.mask
        // (int)(seed >>> (48 - bits)): truncate to the low 32 bits.
        return Int32(truncatingIfNeeded: seed >> UInt64(48 - bits))
    }

    /// `nextInt()`.
    public mutating func nextInt() -> Int32 { next(32) }

    /// `nextInt(bound)`, including the power-of-two shortcut and the rejection
    /// loop. `bound` must be positive (Java throws IllegalArgumentException).
    public mutating func nextInt(_ bound: Int) -> Int {
        precondition(bound > 0 && bound <= Int(Int32.max), "bound must be positive")
        let b = Int32(bound)
        var r = next(31)
        let m = b &- 1
        if b & m == 0 {
            // bound is a power of two: (int)((bound * (long)r) >> 31)
            return Int(Int32(truncatingIfNeeded: (Int64(b) &* Int64(r)) >> 31))
        }
        var u = r
        while true {
            r = u % b
            // Java: while (u - (r = u % bound) + m < 0) — relies on int overflow.
            if (u &- r &+ m) >= 0 { break }
            u = next(31)
        }
        return Int(r)
    }

    /// `nextLong()`: `((long)next(32) << 32) + next(32)`.
    public mutating func nextLong() -> Int64 {
        let hi = Int64(next(32))
        let lo = Int64(next(32))
        return (hi << 32) &+ lo
    }

    /// `nextBoolean()`.
    public mutating func nextBoolean() -> Bool { next(1) != 0 }

    /// `nextFloat()`: `next(24) / (float)(1 << 24)`.
    public mutating func nextFloat() -> Float { Float(next(24)) / Float(1 << 24) }

    /// `nextDouble()`: `(((long)next(26) << 27) + next(27)) * 0x1.0p-53`.
    /// This is also what `Math.random()` returns from its shared generator.
    public mutating func nextDouble() -> Double {
        let hi = Int64(next(26))
        let lo = Int64(next(27))
        return Double((hi << 27) &+ lo) * 0x1.0p-53
    }

    // nextGaussian() is deliberately NOT ported: nothing under src/imp calls it,
    // and an exact port needs fdlibm's StrictMath.log (Foundation's log differs
    // from it by 1–2 ulp on some inputs, measured against a real JVM).
}
