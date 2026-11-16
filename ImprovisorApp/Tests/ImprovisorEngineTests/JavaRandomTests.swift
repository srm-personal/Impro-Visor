//
//  JavaRandomTests.swift
//  ImprovisorEngineTests
//
//  Checks the JavaRandom port against values produced by the real
//  java.util.Random (Testing/goldens/java-random-vectors.tsv, written by
//  `GoldenDriver rng`): 9 seeds × every method the engine uses.
//

import XCTest
@testable import ImprovisorEngine

final class JavaRandomTests: XCTestCase {

    func testMatchesRealJavaForEverySeedAndMethod() throws {
        let text = try TestData.contents("ImprovisorApp/Testing/goldens/java-random-vectors.tsv")
        var checked = 0
        for line in text.split(separator: "\n") {
            let f = line.split(separator: "\t").map(String.init)
            guard f.count > 2, let seed = Int64(f[0]) else { continue }
            let method = f[1]
            let expected = Array(f[2...])
            var r = JavaRandom(seed: seed)
            var got: [String] = []
            switch method {
            case "nextInt":
                got = expected.map { _ in String(r.nextInt()) }
            case "nextLong":
                got = expected.map { _ in String(r.nextLong()) }
            case "nextDouble":
                got = expected.map { _ in String(Int64(bitPattern: r.nextDouble().bitPattern)) }
            case "nextFloat":
                got = expected.map { _ in String(Int32(bitPattern: r.nextFloat().bitPattern)) }
            case "nextBoolean":
                got = expected.map { _ in r.nextBoolean() ? "1" : "0" }
            case "nextGaussian":
                continue // not ported: unused by the engine (see JavaRandom.swift)
            case "mixed":
                for _ in 0..<(expected.count / 3) {
                    got.append(String(r.nextInt(3)))
                    got.append(String(Int64(bitPattern: r.nextDouble().bitPattern)))
                    got.append(String(r.nextInt(100)))
                }
            default:
                guard method.hasPrefix("nextInt:"), let bound = Int(method.dropFirst(8)) else {
                    XCTFail("unknown method \(method)"); continue
                }
                got = expected.map { _ in String(r.nextInt(bound)) }
            }
            XCTAssertEqual(got, expected, "seed \(seed) \(method)")
            checked += 1
        }
        XCTAssertEqual(checked, 9 * 17, "expected 9 seeds × 17 method rows (nextGaussian skipped)")
    }

    func testSetSeedRestartsTheStream() {
        var a = JavaRandom(seed: 42)
        let first = (0..<5).map { _ in a.nextInt(1000) }
        _ = a.nextDouble()
        a.setSeed(42)
        XCTAssertEqual((0..<5).map { _ in a.nextInt(1000) }, first)
    }
}
