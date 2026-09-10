//
//  LibraryBrowser.swift
//  LeadsheetKit
//
//  Browse the bundled corpus (3,280 leadsheets) by folder and search, preview
//  the changes, and open a tune as a new untitled document.
//

import SwiftUI
import AppKit
import ImprovisorEngine

@MainActor
public final class LibraryModel: ObservableObject {
    @Published public private(set) var entries: [LibraryEntry] = []
    @Published public var search = ""
    @Published public var folder: String? = nil
    @Published public var selection: LibraryEntry.ID?
    @Published public private(set) var preview: Score?
    @Published public var status = ""
    public let library: DataLibrary

    public init(library: DataLibrary = .shared) {
        self.library = library
    }

    public func load() {
        guard entries.isEmpty else { return }
        entries = library.libraryIndex()
    }

    public var folders: [String] {
        Array(Set(entries.map(\.folder))).sorted { a, b in
            if a == "imaginary-book" { return true }
            if b == "imaginary-book" { return false }
            return a < b
        }
    }

    public var filtered: [LibraryEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { e in
            (folder == nil || e.folder == folder!) &&
            (q.isEmpty || e.title.lowercased().contains(q) || e.composer.lowercased().contains(q) || e.fileName.lowercased().contains(q))
        }
    }

    public var selectedEntry: LibraryEntry? { entries.first { $0.id == selection } }

    public func updatePreview() {
        preview = selectedEntry.flatMap { library.score(atLeadsheet: $0.url) }
    }

    /// Open the selected tune as a new untitled document.
    public func openSelected() {
        guard let entry = selectedEntry else { return }
        do {
            _ = try NSDocumentController.shared.duplicateDocument(withContentsOf: entry.url, copying: true, displayName: entry.title)
            status = "Opened \(entry.title)"
        } catch {
            status = "Could not open: \(error.localizedDescription)"
        }
    }
}

public struct LibraryBrowser: View {
    @StateObject private var model: LibraryModel

    public init(library: DataLibrary = .shared) {
        _model = StateObject(wrappedValue: LibraryModel(library: library))
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $model.folder) {
                Text("All tunes").tag(String?.none)
                ForEach(model.folders, id: \.self) { f in
                    Text(f.isEmpty ? "(top level)" : f).tag(String?.some(f))
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                Table(model.filtered, selection: $model.selection) {
                    TableColumn("Title", value: \.title)
                    TableColumn("Composer", value: \.composer)
                    TableColumn("Folder", value: \.folder).width(min: 90, ideal: 120)
                }
                .contextMenu(forSelectionType: LibraryEntry.ID.self) { _ in
                    Button("Open as New Document") { model.openSelected() }
                } primaryAction: { _ in
                    model.openSelected()
                }
                Divider()
                previewPane.frame(height: 150)
            }
            .searchable(text: $model.search, placement: .toolbar, prompt: "Title, composer or file name")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Open") { model.openSelected() }.disabled(model.selection == nil)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .navigationTitle("Library")
        .onAppear { model.load() }
        .onChange(of: model.selection) { _, _ in model.updatePreview() }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var previewPane: some View {
        Group {
            if let score = model.preview {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(score.title).font(.headline)
                        if !score.composer.isEmpty { Text("— \(score.composer)").foregroundStyle(.secondary) }
                        Spacer()
                        Text("\(score.measureCount) bars · \(score.meter.numerator)/\(score.meter.denominator) · key \(score.key.index) · \(score.styleName) · \(Int(score.tempo)) bpm")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        Text(LeadsheetWriter.progressionText(score.chordPart, meter: score.meter))
                            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
            } else {
                Text("Select a tune to preview its changes. Double-click to open it as a new document.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
