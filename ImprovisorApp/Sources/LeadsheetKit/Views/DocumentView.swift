//
//  DocumentView.swift
//  LeadsheetKit
//
//  The document window: transport bar, notation editor with chord row, and a
//  settings inspector.
//

import SwiftUI
import UniformTypeIdentifiers
import ImprovisorEngine

public struct DocumentView: View {
    @ObservedObject var document: LeadsheetDocument
    @StateObject private var playback: PlaybackController
    @StateObject private var editor: EditorController
    @Environment(\.undoManager) private var undoManager
    @AppStorage("showInspector") private var showInspector = true

    public init(document: LeadsheetDocument, library: DataLibrary = .shared) {
        self.document = document
        let playback = PlaybackController(library: library)
        _playback = StateObject(wrappedValue: playback)
        _editor = StateObject(wrappedValue: EditorController(document: document, playback: playback))
    }

    public var body: some View {
        VStack(spacing: 8) {
            TransportBar(playback: playback, editor: editor)
            EditorView(editor: editor)
            HStack {
                Text(playback.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("status")
                Spacer()
            }
        }
        .padding(12)
        .frame(minWidth: 820, minHeight: 600)
        .inspector(isPresented: $showInspector) {
            LeadsheetInspector(editor: editor, playback: playback)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .help("Show or hide the tune settings")
            }
            ToolbarItem(placement: .automatic) {
                Button { exportMIDI() } label: { Label("Export MIDI", systemImage: "square.and.arrow.up") }
                    .help("Export the arrangement as a MIDI file")
            }
        }
        .onAppear {
            editor.playback = playback
            if document.score.tempo > 0 { playback.tempo = min(300, max(30, document.score.tempo)) }
        }
        .onDisappear { playback.shutdown() }
        .focusedSceneValue(\.playbackController, playback)
    }

    private func exportMIDI() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mid") ?? .data]
        let base = document.score.title.trimmingCharacters(in: .whitespaces)
        panel.nameFieldStringValue = (base.isEmpty ? "leadsheet" : base.replacingOccurrences(of: " ", with: "")) + ".mid"
        if panel.runModal() == .OK, let url = panel.url { playback.exportMIDI(score: document.score, to: url) }
    }
}

private struct PlaybackControllerKey: FocusedValueKey {
    typealias Value = PlaybackController
}

public extension FocusedValues {
    var playbackController: PlaybackController? {
        get { self[PlaybackControllerKey.self] }
        set { self[PlaybackControllerKey.self] = newValue }
    }
}
