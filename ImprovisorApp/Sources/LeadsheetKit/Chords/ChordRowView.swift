//
//  ChordRowView.swift
//  LeadsheetKit
//
//  Editable chord cells laid over the stave's chord row, one per measure.
//  A cell is an invisible click target until edited; then it shows a text
//  field with autocomplete. Return commits and moves to the next bar,
//  Tab accepts the first suggestion, ⌥↩ splits the bar into four cells,
//  Esc returns focus to the stave.
//

import SwiftUI
import ImprovisorEngine

public struct ChordRowView: View {
    @ObservedObject var editor: EditorController
    var layout: LayoutDocument
    @Binding var editingMeasure: Int?
    var onDone: () -> Void

    @State private var text = ""
    @State private var suggestions: [String] = []
    @FocusState private var focused: Bool

    public init(editor: EditorController, layout: LayoutDocument, editingMeasure: Binding<Int?>, onDone: @escaping () -> Void) {
        self.editor = editor
        self.layout = layout
        self._editingMeasure = editingMeasure
        self.onDone = onDone
    }

    private var rowHeight: CGFloat { layout.geometry.spaceHeight * 2.6 }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.measures, id: \.index) { box in
                let system = layout.systems[box.system]
                let frame = CGRect(x: box.frame.minX, y: system.chordY - rowHeight * 0.7, width: box.frame.width, height: rowHeight)
                if editingMeasure == box.index {
                    cellEditor(for: box.index)
                        .frame(width: max(140, frame.width), height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .onTapGesture { begin(measure: box.index) }
                        .help("Click to edit the chords of bar \(box.index + 1)")
                        .accessibilityIdentifier("chordCell-\(box.index + 1)")
                }
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .onChange(of: editingMeasure) { _, new in
            if let new { load(measure: new) }
        }
    }

    private func cellEditor(for measure: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Chords for bar \(measure + 1)", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .semibold))
                .focused($focused)
                .onChange(of: text) { _, new in refreshSuggestions(new) }
                .onSubmit { commit(advance: true) }
                .onExitCommand { cancel() }
                .onKeyPress(.tab) { acceptSuggestion(); return .handled }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.option) { splitBar(); return .handled }
                    return .ignored
                }
                .accessibilityIdentifier("chordField")
            if !suggestions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(suggestions.prefix(8), id: \.self) { s in
                        Button(s) { replaceLastToken(with: s) }
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                }
                .padding(4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .onAppear { focused = true }
    }

    // MARK: Actions

    private func begin(measure: Int) {
        editingMeasure = measure
        load(measure: measure)
    }

    private func load(measure: Int) {
        text = editor.chordText(forMeasure: measure)
        if text == "/" { text = "" }
        refreshSuggestions(text)
        focused = true
    }

    private var lastToken: String {
        text.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    }

    private func refreshSuggestions(_ current: String) {
        let token = lastToken
        if token.isEmpty && !current.isEmpty { suggestions = []; return }
        suggestions = ChordCompleter.suggest(token, vocabulary: DataLibrary.shared.vocabulary)
            .filter { $0 != token }
    }

    private func replaceLastToken(with s: String) {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if tokens.isEmpty { tokens = [s] } else { tokens[tokens.count - 1] = s }
        text = tokens.joined(separator: " ")
        suggestions = []
        focused = true
    }

    private func acceptSuggestion() {
        if let first = suggestions.first { replaceLastToken(with: first) }
    }

    private func splitBar() {
        let tokens = text.split(separator: " ").map(String.init)
        let first = tokens.first ?? (editor.chordText(forMeasure: editingMeasure ?? 0).split(separator: " ").first.map(String.init) ?? "C")
        text = tokens.count >= 4 ? text : ([first] + Array(repeating: "/", count: 3)).joined(separator: " ")
    }

    private func commit(advance: Bool) {
        guard let measure = editingMeasure else { return }
        editor.commitChordText(text, forMeasure: measure)
        if advance, measure + 1 < editor.score.measureCount {
            editingMeasure = measure + 1
            load(measure: measure + 1)
        } else {
            finish()
        }
    }

    private func cancel() { finish() }

    private func finish() {
        editingMeasure = nil
        suggestions = []
        onDone()
    }
}
