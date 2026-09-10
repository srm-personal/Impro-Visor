//
//  EditorView.swift
//  LeadsheetKit
//
//  The notation editor: duration palette, the interactive stave (keyboard focus
//  through KeyEventHost, mouse through StaveInteraction), and the on-screen piano.
//

import SwiftUI
import ImprovisorEngine

public struct EditorView: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var document: LeadsheetDocument
    @Environment(\.undoManager) private var undoManager
    @State private var focusToken = 0
    @State private var showPiano = true

    public init(editor: EditorController) {
        self.editor = editor
        self.document = editor.document
    }

    private var staveOptions: StaveOptions {
        var o = StaveOptions()
        o.measuresPerLine = document.score.layout.first ?? 4
        return o
    }

    public var body: some View {
        VStack(spacing: 8) {
            DurationPalette(editor: editor)
            StaveView(score: document.score, part: editor.partIndex, options: staveOptions,
                      overlay: editor.overlay,
                      onLayout: { editor.layout = $0 },
                      interaction: StaveInteraction(
                        onClick: { point, mods in focusToken += 1; editor.click(at: point, modifiers: mods) },
                        onDragBegan: { point in focusToken += 1; editor.beginDrag(at: point) },
                        onDragChanged: { point in editor.drag(to: point) },
                        onDragEnded: { editor.endDrag() }))
                .background(KeyEventHost(controller: editor, focusToken: focusToken))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .accessibilityIdentifier("stave")
                .accessibilityValue(NoteSerializer.tokens(editor.melody).joined(separator: " "))
            HStack {
                Toggle("Piano", isOn: $showPiano).toggleStyle(.checkbox).font(.caption)
                Spacer()
                Text(cursorDescription).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            if showPiano {
                PianoKeyboardView(editor: editor).frame(height: 76)
            }
        }
        .onAppear { editor.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in editor.undoManager = new }
    }

    private var cursorDescription: String {
        let spm = max(1, document.score.meter.slotsPerMeasure)
        let bar = editor.cursorSlot / spm + 1
        let beat = (editor.cursorSlot % spm) / max(1, document.score.meter.slotsPerBeat) + 1
        let chord = editor.chord(atSlot: editor.cursorSlot)?.name ?? "—"
        return "bar \(bar) · beat \(beat) · \(chord) · \(editor.entry.harmonic ? "harmonic" : "simple") entry"
    }
}
