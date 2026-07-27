//
//  TestSupport.swift
//  ImprovisorEngineTests
//
//  Shared helpers for locating the bundled Impro-Visor data files. The Swift
//  package lives at <repo>/ImprovisorApp, so the data directories
//  (leadsheets/, styles/, grammars/, voicings/) are two levels up.
//

import Foundation

enum TestData {
    /// The Impro-Visor repository root, derived from this source file's path.
    /// <repo>/ImprovisorApp/Tests/ImprovisorEngineTests/TestSupport.swift
    static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ImprovisorEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // ImprovisorApp
            .deletingLastPathComponent()   // repo root
    }()

    /// Absolute path for a data file relative to the repo root.
    static func path(_ relative: String) -> String {
        repoRoot.appendingPathComponent(relative).path
    }

    /// Absolute URL for a data file relative to the repo root.
    static func url(_ relative: String) -> URL {
        repoRoot.appendingPathComponent(relative)
    }

    /// Read a data file's contents as a string.
    static func contents(_ relative: String) throws -> String {
        try String(contentsOf: url(relative), encoding: .utf8)
    }

    /// Recursively find all files under `relative` with the given extension.
    static func files(under relative: String, ext: String) -> [URL] {
        let base = url(relative)
        guard let enumerator = FileManager.default.enumerator(
            at: base,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var result: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == ext {
            result.append(fileURL)
        }
        return result
    }
}
