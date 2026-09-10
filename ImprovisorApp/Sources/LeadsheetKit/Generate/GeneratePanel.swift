//
//  GeneratePanel.swift
//  LeadsheetKit
//
//  Grammar-based solo generation into the selection or a new chorus.
//

import SwiftUI
import ImprovisorEngine

public struct GeneratePanel: View {
    @ObservedObject var editor: EditorController
    @AppStorage("soloGrammar") private var grammarName = "Bebop"
    @State private var seedText = ""

    public init(editor: EditorController) { self.editor = editor }

    private var library: DataLibrary { editor.playback?.library ?? .shared }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generate Solo").font(.headline)
            Picker("Grammar", selection: $grammarName) {
                ForEach(library.grammarNames, id: \.self) { Text($0).tag($0) }
            }
            HStack {
                TextField("random seed", text: $seedText).textFieldStyle(.roundedBorder).frame(width: 110)
                Text("blank = random").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(editor.selection == nil ? "Fill Whole Chorus" : "Fill Selection") {
                    guard let g = library.grammar(grammarName) else { editor.status = "Grammar \(grammarName) failed to load."; return }
                    editor.generateSolo(grammar: g, seed: UInt64(seedText))
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("New Chorus") {
                    guard let g = library.grammar(grammarName) else { return }
                    editor.generateSoloChorus(grammar: g, seed: UInt64(seedText))
                }
            }
            Text("Solos follow the chords of the bars they fill; undo (⌘Z) to try again.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
