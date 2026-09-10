//
//  DocumentView.swift
//  LeadsheetKit
//
//  The document window. In Phase 4 this is a deliberately plain form — title,
//  composer, chord text, style, tempo, transport — that proves the document /
//  undo / playback plumbing end to end. Phases 5–8 replace the body with the
//  notation editor, chord row, transport bar and inspector.
//

import SwiftUI
import UniformTypeIdentifiers
import ImprovisorEngine

public struct DocumentView: View {
    @ObservedObject var document: LeadsheetDocument
    @StateObject private var playback: PlaybackController
    @Environment(\.undoManager) private var undoManager
    @State private var chordText = ""
    @State private var showChordText = false

    private var staveOptions: StaveOptions {
        var o = StaveOptions()
        o.measuresPerLine = document.score.layout.first ?? 4
        return o
    }

    public init(document: LeadsheetDocument, library: DataLibrary = .shared) {
        self.document = document
        _playback = StateObject(wrappedValue: PlaybackController(library: library))
    }

    private var library: DataLibrary { playback.library }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            StaveView(score: document.score, part: 0, options: staveOptions,
                      overlay: StaveRenderer.Overlay(playheadSlot: playback.isPlaying ? playback.positionSlot % max(1, document.score.chordPart.size) : nil))
                .frame(minHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .accessibilityIdentifier("stave")
            DisclosureGroup("Chords as text", isExpanded: $showChordText) { chordsSection }
            settings
            Divider()
            transport
            Text(playback.status).font(.callout).foregroundStyle(.secondary)
                .accessibilityIdentifier("status")
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 600)
        .onAppear {
            chordText = LeadsheetWriter.progressionText(document.score.chordPart, meter: document.score.meter)
            if document.score.tempo > 0 { playback.tempo = min(300, max(30, document.score.tempo)) }
        }
        .onDisappear { playback.stop() }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            TextField("Title", text: binding(\.title, name: "Change Title"))
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("title")
            TextField("Composer", text: binding(\.composer, name: "Change Composer"))
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("composer")
        }
    }

    private var chordsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Chords").font(.headline)
                Spacer()
                Text("\(document.score.measureCount) bars").foregroundStyle(.secondary)
                Button("Apply") { applyChords() }.accessibilityIdentifier("applyChords")
            }
            TextEditor(text: $chordText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90, maxHeight: 160)
                .accessibilityIdentifier("chordText")
            Text("Bars separated by |, '/' holds the previous chord.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var settings: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("Style")
                Picker("", selection: styleBinding) {
                    ForEach(library.styleNames, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: 240).accessibilityIdentifier("style")
                Text("Choruses")
                Stepper("\(playback.choruses)", value: $playback.choruses, in: 1...16).frame(maxWidth: 120)
            }
            GridRow {
                Text("Tempo")
                HStack {
                    Slider(value: $playback.tempo, in: 30...300)
                    Text("\(Int(playback.tempo)) bpm").monospacedDigit().frame(width: 70, alignment: .trailing)
                }.gridCellColumns(3)
            }
            GridRow {
                Text("Output")
                Picker("", selection: $playback.output) {
                    ForEach(OutputKind.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(maxWidth: 240)
                if playback.output == .coreMIDI {
                    Text("Destination")
                    TextField("first available", text: $playback.midiDestinationHint).textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button { playback.play(score: document.score) } label: { Label("Play", systemImage: "play.fill") }
                .disabled(playback.isPlaying).keyboardShortcut(.space, modifiers: []).accessibilityIdentifier("play")
            Button { playback.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .disabled(!playback.isPlaying).accessibilityIdentifier("stop")
            if playback.isPlaying {
                Text("bar \(playback.positionSlot / max(1, document.score.meter.slotsPerMeasure) + 1)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            Button { exportMIDI() } label: { Label("Export MIDI…", systemImage: "square.and.arrow.up") }
        }
        .controlSize(.large)
    }

    // MARK: Editing helpers

    private func binding(_ keyPath: WritableKeyPath<Score, String>, name: String) -> Binding<String> {
        Binding(
            get: { document.score[keyPath: keyPath] },
            set: { value in document.perform(name, undoManager: undoManager) { $0[keyPath: keyPath] = value } }
        )
    }

    private var styleBinding: Binding<String> {
        Binding(
            get: { document.score.styleName },
            set: { name in
                document.perform("Change Style", undoManager: undoManager) { score in
                    score.styleName = name
                    score.styleOverride = nil
                    var records = score.sections.records
                    if records.isEmpty { records = [SectionRecord(measure: 0, styleName: name)] }
                    else { records[0].styleName = name }
                    score.sections = SectionInfo(records: records)
                }
            }
        )
    }

    private func applyChords() {
        let part = LeadsheetParser.chordPart(fromText: chordText, meter: document.score.meter,
                                             vocabulary: library.vocabulary)
        guard part.size > 0 else { playback.status = "No chords recognized."; return }
        document.perform("Change Chords", undoManager: undoManager) { score in
            let info = score.chordPart.info
            score.chordPart = part
            score.chordPart.info = info
        }
        playback.status = "Applied \(part.count) chords over \(document.score.measureCount) bars."
    }

    private func exportMIDI() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mid") ?? .data]
        let base = document.score.title.trimmingCharacters(in: .whitespaces)
        panel.nameFieldStringValue = (base.isEmpty ? "leadsheet" : base.replacingOccurrences(of: " ", with: "")) + ".mid"
        if panel.runModal() == .OK, let url = panel.url { playback.exportMIDI(score: document.score, to: url) }
    }
}
