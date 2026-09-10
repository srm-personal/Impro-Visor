//
//  DataLibrary.swift
//  LeadsheetKit
//
//  Locates and loads the Impro-Visor data corpus (vocab/, styles/, grammars/,
//  voicings/, leadsheets/). In the shipped app the corpus is copied into the
//  bundle's Resources; during development (swift run / swift test) it is read
//  in place from the repository checkout.
//

import Foundation
import ImprovisorEngine

public final class DataLibrary: StyleProvider, @unchecked Sendable {
    public let root: URL
    public let vocabulary: Vocabulary

    private let lock = NSLock()
    private var styleCache: [String: Style] = [:]
    private var voicingCache: [String: VoicingSettings] = [:]
    private var grammarCache: [String: Grammar] = [:]

    /// The library for the running process: the app bundle's corpus, else the
    /// repository checkout, else an empty library rooted at the working directory.
    public static let shared: DataLibrary = {
        let root = DataLibrary.locate() ?? URL(filePath: FileManager.default.currentDirectoryPath)
        return DataLibrary(root: root)
    }()

    public init(root: URL) {
        self.root = root
        let voc = (try? String(contentsOf: root.appending(path: "vocab/My.voc"), encoding: .utf8)) ?? ""
        self.vocabulary = Vocabulary(source: voc)
    }

    public func url(_ relative: String) -> URL { root.appending(path: relative) }

    /// Whether the corpus was actually found at `root`.
    public var hasCorpus: Bool { DataLibrary.hasCorpus(root) }

    // MARK: Listings

    private func names(inDirectory dir: String, ext: String) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url(dir), includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == ext }
            .map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    public var styleNames: [String] { names(inDirectory: "styles", ext: "sty") }
    public var grammarNames: [String] { names(inDirectory: "grammars", ext: "grammar") }

    /// Every bundled leadsheet, recursively (for the library browser).
    public func leadsheetURLs() -> [URL] {
        guard let e = FileManager.default.enumerator(at: url("leadsheets"), includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let u as URL in e where u.pathExtension == "ls" { out.append(u) }
        return out.sorted { $0.path < $1.path }
    }

    // MARK: Loading

    public func style(named name: String) -> Style? {
        lock.lock(); defer { lock.unlock() }
        if let cached = styleCache[name] { return cached }
        guard let style = try? StyleParser.parse(contentsOf: url("styles/\(name).sty")) else { return nil }
        styleCache[name] = style
        return style
    }

    /// The style by name, or a bare fallback style with that name.
    public func style(_ name: String) -> Style {
        style(named: name) ?? Style(name: name)
    }

    public func voicingSettings(for style: Style) -> VoicingSettings {
        lock.lock(); defer { lock.unlock() }
        let file = style.voicingFileName
        if let cached = voicingCache[file] { return cached }
        let settings = (try? VoicingParser.parse(contentsOf: url("voicings/\(file)"))) ?? VoicingSettings()
        voicingCache[file] = settings
        return settings
    }

    public func grammar(_ name: String) -> Grammar? {
        lock.lock(); defer { lock.unlock() }
        if let cached = grammarCache[name] { return cached }
        guard let g = try? GrammarParser.parse(contentsOf: url("grammars/\(name).grammar")),
              !g.rules.isEmpty else { return nil }
        grammarCache[name] = g
        return g
    }

    public func score(atLeadsheet url: URL) -> Score? {
        try? LeadsheetParser.parse(contentsOf: url, vocabulary: vocabulary)
    }

    // MARK: Locating the corpus

    static func hasCorpus(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appending(path: "vocab/My.voc").path)
    }

    /// The app bundle's Resources (when the corpus is bundled), else the
    /// repository checkout containing this source file, else an ancestor of the
    /// working directory.
    public static func locate() -> URL? {
        if let resources = Bundle.main.resourceURL, hasCorpus(resources) { return resources }
        var dir = URL(filePath: #filePath)
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            if hasCorpus(dir) { return dir }
        }
        dir = URL(filePath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            if hasCorpus(dir) { return dir }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}
