//
//  SectionEditor.swift
//  LeadsheetKit
//
//  Sections and phrases: where the style changes within the form.
//

import SwiftUI
import ImprovisorEngine

public struct SectionEditor: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var document: LeadsheetDocument
    @State private var newStyle = ""

    public init(editor: EditorController) {
        self.editor = editor
        self.document = editor.document
    }

    private var library: DataLibrary { editor.playback?.library ?? .shared }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sections").font(.headline)
            ForEach(document.score.sections.records, id: \.measure) { record in
                HStack {
                    Text("bar \(record.measure + 1)").monospacedDigit().frame(width: 56, alignment: .leading)
                    Picker("", selection: styleBinding(record)) {
                        Text("(previous style)").tag("")
                        ForEach(library.styleNames, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: 180)
                    Toggle("phrase", isOn: phraseBinding(record)).toggleStyle(.checkbox)
                    Spacer()
                    if record.measure > 0 {
                        Button { editor.removeSection(atMeasure: record.measure) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            HStack {
                Button("Start Section at Bar \(editor.cursorMeasure + 1)") {
                    editor.setSection(atMeasure: editor.cursorMeasure, styleName: document.score.styleName, isPhrase: false)
                }
                Button("Phrase Mark") {
                    editor.setSection(atMeasure: editor.cursorMeasure, styleName: "", isPhrase: true)
                }
            }.controlSize(.small)
        }
    }

    private func styleBinding(_ record: SectionRecord) -> Binding<String> {
        Binding(get: { record.styleName },
                set: { editor.setSection(atMeasure: record.measure, styleName: $0, isPhrase: record.isPhrase) })
    }

    private func phraseBinding(_ record: SectionRecord) -> Binding<Bool> {
        Binding(get: { record.isPhrase },
                set: { editor.setSection(atMeasure: record.measure, styleName: record.styleName, isPhrase: $0) })
    }
}
