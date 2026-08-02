//
//  ContentView.swift
//  improvisor-app
//
//  The window: choose a progression (inline or an opened leadsheet), a style and
//  feel, then Generate / Play / Stop / Export, with the resulting chord grid.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Impro-Visor").font(.largeTitle.bold())

            progressionSection
            Divider()
            settingsSection
            Divider()
            transport
            chordGrid

            Spacer(minLength: 0)
            Text(model.status).font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 560)
    }

    // MARK: Progression

    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progression").font(.headline)
                Spacer()
                if let name = model.loadedLeadsheet?.lastPathComponent {
                    Label(name, systemImage: "doc.text")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Use inline chords") { model.clearLeadsheet() }
                        .buttonStyle(.link)
                }
                Button("Open leadsheet…") { openLeadsheet() }
            }
            TextField("Dm7 | G7 | Cmaj7 | Cmaj7", text: $model.chordText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .disabled(model.loadedLeadsheet != nil)
                .help("Bars separated by | , '/' repeats the previous chord.")
        }
    }

    // MARK: Settings

    private var settingsSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                Text("Style")
                Picker("", selection: $model.styleName) {
                    ForEach(model.styleNames, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: 220)

                Text("Solo")
                Picker("", selection: $model.soloGrammar) {
                    ForEach(model.grammarNames, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: 220)
            }
            GridRow {
                Text("Tempo")
                HStack {
                    Slider(value: $model.tempo, in: 60...300)
                    Text("\(Int(model.tempo)) bpm").monospacedDigit().frame(width: 70, alignment: .trailing)
                }.gridCellColumns(3)
            }
            GridRow {
                Text("Choruses")
                Stepper("\(model.loops)", value: $model.loops, in: 1...16).frame(maxWidth: 120)
                Text("Seed")
                Stepper("\(model.seed)", value: $model.seed, in: 0...9999).frame(maxWidth: 120)
            }
            GridRow {
                Text("Output")
                Picker("", selection: $model.backendKind) {
                    ForEach(BackendKind.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().gridCellColumns(3)
            }
            if model.backendKind == .coreMIDI {
                GridRow {
                    Text("Destination")
                    TextField("first available (name contains…)", text: $model.midiDestinationHint)
                        .textFieldStyle(.roundedBorder).gridCellColumns(3)
                }
            }
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 12) {
            Button { model.generate() } label: {
                Label("Generate", systemImage: "wand.and.stars")
            }
            Button { model.play() } label: {
                Label("Play", systemImage: "play.fill")
            }.disabled(model.isPlaying)
            Button { model.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
            }.disabled(!model.isPlaying)
            Spacer()
            Button { exportMIDI() } label: {
                Label("Export MIDI…", systemImage: "square.and.arrow.up")
            }
        }
        .controlSize(.large)
    }

    // MARK: Chord grid

    private var chordGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.trackSummary.isEmpty {
                Text(model.trackSummary).font(.caption).foregroundStyle(.secondary)
            }
            if !model.chordSummary.isEmpty {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(model.chordSummary.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: Panels

    private func openLeadsheet() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ls") ?? .plainText]
        panel.directoryURL = model.library.url("leadsheets")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.openLeadsheet(url) }
    }

    private func exportMIDI() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mid") ?? .data]
        panel.nameFieldStringValue = (model.loadedLeadsheet?.deletingPathExtension().lastPathComponent ?? "improvisor") + ".mid"
        if panel.runModal() == .OK, let url = panel.url { model.export(to: url) }
    }
}
