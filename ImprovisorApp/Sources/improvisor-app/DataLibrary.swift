//
//  DataLibrary.swift
//  improvisor-app
//
//  Locates the Impro-Visor data corpus (vocab/, styles/, grammars/, voicings/,
//  leadsheets/) and loads pieces of it for the app. For this first app cut it
//  reads the corpus in place from the repo checkout (found via #filePath, or by
//  walking up from the working directory). Bundling a curated subset into a
//  standalone .app is the follow-on when we ship a signed app.
//

import Foundation
import ImprovisorEngine

@MainActor
final class DataLibrary {
    let root: URL
    let vocabulary: Vocabulary

    init(root: URL) {
        self.root = root
        let voc = (try? String(contentsOf: root.appending(path: "vocab/My.voc"), encoding: .utf8)) ?? ""
        self.vocabulary = Vocabulary(source: voc)
    }

    func url(_ relative: String) -> URL { root.appending(path: relative) }

    private func names(inDirectory dir: String, ext: String) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url(dir), includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == ext }
            .map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }

    var styleNames: [String] { names(inDirectory: "styles", ext: "sty") }
    var grammarNames: [String] { names(inDirectory: "grammars", ext: "grammar") }

    func style(_ name: String) -> Style {
        (try? StyleParser.parse(contentsOf: url("styles/\(name).sty"))) ?? Style(name: name)
    }

    func voicingSettings(for style: Style) -> VoicingSettings {
        (try? VoicingParser.parse(contentsOf: url("voicings/\(style.voicingFileName)"))) ?? VoicingSettings()
    }

    func grammar(_ name: String) -> Grammar? {
        guard let g = try? GrammarParser.parse(contentsOf: url("grammars/\(name).grammar")),
              !g.rules.isEmpty else { return nil }
        return g
    }

    func score(atLeadsheet url: URL) -> Score? {
        try? LeadsheetParser.parse(contentsOf: url, vocabulary: vocabulary)
    }

    /// Parse an inline chord progression (e.g. "Dm7 | G7 | Cmaj7 | Cmaj7").
    func score(chords: String, styleName: String, tempo: Int) -> Score {
        let leadsheet = "(meter 4 4)(key 0)(tempo \(tempo))(style \(styleName))\n(part (type chords))\n\(chords)"
        return LeadsheetParser.parse(leadsheet, vocabulary: vocabulary)
    }

    /// Find the corpus root: the repo checkout that contains this source file, or
    /// failing that, an ancestor of the current working directory.
    static func locate() -> URL? {
        let fm = FileManager.default
        func hasCorpus(_ dir: URL) -> Bool {
            fm.fileExists(atPath: dir.appending(path: "vocab/My.voc").path)
        }
        // Repo root = up 4 from Sources/improvisor-app/DataLibrary.swift.
        var fromSource = URL(filePath: #filePath)
        for _ in 0..<4 { fromSource.deleteLastPathComponent() }
        if hasCorpus(fromSource) { return fromSource }

        var dir = URL(filePath: fm.currentDirectoryPath)
        for _ in 0..<8 {
            if hasCorpus(dir) { return dir }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}
