//
//  EditorCommands.swift
//  LeadsheetKit
//
//  Menu bar commands that act on the focused window's editor.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct EditorCommands: Commands {
    @FocusedObject private var editor: EditorController?
    @FocusedValue(\.playbackController) private var playback: PlaybackController?
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Leadsheet Studio") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .help) {
            Button("Leadsheet Studio Help") { openWindow(id: "welcome") }
            Link("Impro-Visor Documentation", destination: URL(string: "https://www.cs.hmc.edu/~keller/jazz/improvisor/")!)
        }
        CommandGroup(after: .newItem) {
            Button("Open from Library…") { openWindow(id: "library") }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { if let e = editor { PDFExporter.print(score: e.document.score, window: NSApp.keyWindow) } }
                .keyboardShortcut("p", modifiers: [.command]).disabled(editor == nil)
            Button("Print Current Chorus…") { if let e = editor { PDFExporter.print(score: e.document.score, parts: [e.partIndex], window: NSApp.keyWindow) } }
                .disabled(editor == nil)
            Button("Export PDF…") { if let e = editor { exportPDF(e) } }.disabled(editor == nil)
        }
        CommandMenu("Playback") {
            Button("Play / Pause") { if let e = editor { playback?.togglePlayPause(score: e.document.score) } }
                .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(editor == nil)
            Button("Stop") { playback?.stop() }.keyboardShortcut(".", modifiers: [.command]).disabled(editor == nil)
            Button("Play Selection (Loop)") { editor?.perform(.playSelection) }.disabled(editor == nil)
            Toggle("Loop Form", isOn: Binding(get: { playback?.loopWholeForm ?? false }, set: { playback?.loopWholeForm = $0 }))
                .keyboardShortcut("l", modifiers: [.command]).disabled(editor == nil)
            Toggle("Count-in", isOn: Binding(get: { playback?.countIn ?? false }, set: { playback?.countIn = $0 })).disabled(editor == nil)
            Divider()
            Button("New Accompaniment") { playback?.regenerate() }.disabled(editor == nil)
        }
        CommandMenu("Transpose") {
            Group {
                Button("Melody Up a Semitone") { editor?.transpose(.melody, by: 1) }.keyboardShortcut("e", modifiers: [.command])
                Button("Melody Down a Semitone") { editor?.transpose(.melody, by: -1) }.keyboardShortcut("d", modifiers: [.command])
                Button("Melody Up an Octave") { editor?.transpose(.melody, by: 12) }.keyboardShortcut("t", modifiers: [.command])
                Button("Melody Down an Octave") { editor?.transpose(.melody, by: -12) }.keyboardShortcut("g", modifiers: [.command])
                Divider()
                Button("Chords Up a Semitone") { editor?.transpose(.chords, by: 1) }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Chords Down a Semitone") { editor?.transpose(.chords, by: -1) }.keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Both Up a Semitone") { editor?.transpose(.both, by: 1) }.keyboardShortcut("e", modifiers: [.command, .option])
                Button("Both Down a Semitone") { editor?.transpose(.both, by: -1) }.keyboardShortcut("d", modifiers: [.command, .option])
            }
            .disabled(editor == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Edit Chords of Current Bar") { editor?.perform(.focusChords) }
                .keyboardShortcut("k", modifiers: [.command, .shift]).disabled(editor == nil)
            Button("Toggle Harmonic Entry") { editor?.perform(.toggleHarmonic) }.disabled(editor == nil)
            Button("Toggle Enharmonic Spelling") { editor?.perform(.toggleEnharmonic) }.disabled(editor == nil)
        }
    }
}

@MainActor
private func exportPDF(_ editor: EditorController) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    let base = editor.document.score.title.trimmingCharacters(in: .whitespaces)
    panel.nameFieldStringValue = (base.isEmpty ? "leadsheet" : base.replacingOccurrences(of: " ", with: "")) + ".pdf"
    if panel.runModal() == .OK, let url = panel.url {
        do { try PDFExporter.export(score: editor.document.score, to: url); editor.status = "Exported \(url.lastPathComponent)" }
        catch { editor.status = "PDF export failed: \(error.localizedDescription)" }
    }
}
