//
//  DurationPalette.swift
//  LeadsheetKit
//
//  Toolbar for the entry state: note value, dot, triplet, rest, tie, entry mode.
//

import SwiftUI
import ImprovisorEngine

public struct DurationPalette: View {
    @ObservedObject var editor: EditorController

    public init(editor: EditorController) { self.editor = editor }

    private let bases: [(NoteValue.Base, String, String)] = [
        (.whole, "𝅝", "1"), (.half, "𝅗𝅥", "2"), (.quarter, "𝅘𝅥", "4"), (.eighth, "𝅘𝅥𝅮", "8"), (.sixteenth, "𝅘𝅥𝅯", "6")
    ]

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(bases, id: \.0) { base, glyph, key in
                Button {
                    editor.entry.base = base
                } label: {
                    Text(glyph).font(.system(size: 20)).frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .tint(editor.entry.base == base ? .accentColor : .secondary)
                .help("\(base) note (key \(key))")
                .accessibilityIdentifier("duration-\(key)")
            }
            Divider().frame(height: 22)
            Toggle(isOn: $editor.entry.dotted) { Text("•").font(.title3) }
                .toggleStyle(.button).help("Dotted (.)").accessibilityIdentifier("dot")
            Toggle(isOn: $editor.entry.triplet) { Text("3").font(.body.italic()) }
                .toggleStyle(.button).help("Triplet (3)").accessibilityIdentifier("triplet")
            Divider().frame(height: 22)
            Button { editor.perform(.rest) } label: { Text("𝄽").font(.system(size: 18)).frame(width: 26, height: 26) }
                .buttonStyle(.bordered).help("Rest (R)").accessibilityIdentifier("rest")
            Button { editor.perform(.tie) } label: { Image(systemName: "arrow.right.to.line").frame(width: 26, height: 26) }
                .buttonStyle(.bordered).help("Extend previous note (-)").accessibilityIdentifier("tie")
            Divider().frame(height: 22)
            Toggle(isOn: $editor.entry.harmonic) {
                Label("Harmonic", systemImage: editor.entry.harmonic ? "music.note.list" : "music.note")
            }
            .toggleStyle(.button).help("Snap clicked notes to chord tones (H)").accessibilityIdentifier("harmonic")
            if editor.entry.harmonic {
                Picker("", selection: $editor.entry.mode) {
                    Text("Chord").tag(ToneMode.chordTones)
                    Text("Chord+Color").tag(ToneMode.chordAndColor)
                    Text("Scale").tag(ToneMode.scale)
                }.labelsHidden().frame(width: 120)
            }
            Spacer()
            Text(editor.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .controlSize(.small)
    }
}
