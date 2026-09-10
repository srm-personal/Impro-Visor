//
//  LeadsheetDocument.swift
//  LeadsheetKit
//
//  The document: a Score read from / written to `.ls` text. Being a
//  ReferenceFileDocument gives the app Open / Save / Save As / Revert /
//  autosave / Recent Items / multi-window for free, and lets edits register
//  with the window's UndoManager (see ScoreEditing).
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ImprovisorEngine

public final class LeadsheetDocument: ReferenceFileDocument, @unchecked Sendable {
    public typealias Snapshot = Score

    /// The tune. Mutate only through `perform(_:undoManager:_:)` on the main
    /// actor so changes are undoable and observers are notified.
    @Published public var score: Score

    public static let readableContentTypes: [UTType] = [.leadsheet, .plainText]
    public static let writableContentTypes: [UTType] = [.leadsheet]

    public init(score: Score = .blank()) {
        self.score = score
    }

    /// Parse leadsheet text (the vocabulary comes from the shared library).
    public convenience init(data: Data, vocabulary: Vocabulary = DataLibrary.shared.vocabulary) throws {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.init(score: LeadsheetParser.parse(text, vocabulary: vocabulary))
    }

    public convenience init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    public func snapshot(contentType: UTType) throws -> Score { score }

    /// The document's `.ls` text.
    public static func data(for score: Score) -> Data {
        Data(LeadsheetWriter.leadsheet(score: score).utf8)
    }

    public func fileWrapper(snapshot: Score, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: LeadsheetDocument.data(for: snapshot))
    }
}
