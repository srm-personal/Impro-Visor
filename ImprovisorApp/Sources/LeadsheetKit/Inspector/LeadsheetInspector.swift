//
//  LeadsheetInspector.swift
//  LeadsheetKit
//
//  Sidebar with the tune's settings: identity, key/meter/tempo, style, parts,
//  instruments and volumes, layout, sections, and the generator.
//

import SwiftUI
import ImprovisorEngine

public struct LeadsheetInspector: View {
    @ObservedObject var editor: EditorController
    @ObservedObject var document: LeadsheetDocument
    @ObservedObject var playback: PlaybackController
    @Environment(\.undoManager) private var undoManager

    public init(editor: EditorController, playback: PlaybackController) {
        self.editor = editor
        self.document = editor.document
        self.playback = playback
    }

    private var score: Score { document.score }
    private var library: DataLibrary { playback.library }

    public var body: some View {
        Form {
            Section("Tune") {
                TextField("Title", text: text(\.title, "Change Title"))
                TextField("Composer", text: text(\.composer, "Change Composer"))
                TextField("Show", text: text(\.showTitle, "Change Show"))
                TextField("Year", text: text(\.year, "Change Year"))
                TextField("Comments", text: text(\.comments, "Change Comments"), axis: .vertical).lineLimit(1...3)
            }
            Section("Music") {
                Stepper(value: int(\.key.index, "Change Key", set: { $0.key = Key(index: $1) }), in: -7...7) {
                    HStack { Text("Key"); Spacer(); Text(keyName).foregroundStyle(.secondary) }
                }
                HStack {
                    Text("Meter")
                    Spacer()
                    Stepper("\(score.meter.numerator)", value: int(\.meter.numerator, "Change Meter", set: { $0.meter.numerator = $1 }), in: 1...12).fixedSize()
                    Text("/")
                    Picker("", selection: int(\.meter.denominator, "Change Meter", set: { $0.meter.denominator = $1 })) {
                        ForEach([2, 4, 8], id: \.self) { Text("\($0)").tag($0) }
                    }.labelsHidden().frame(width: 60)
                }
                HStack {
                    Text("Tempo")
                    Slider(value: tempoBinding, in: 30...300)
                    Text("\(Int(score.tempo))").monospacedDigit().frame(width: 34)
                }
                Picker("Style", selection: styleBinding) {
                    ForEach(library.styleNames, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: int(\.layout, "Change Layout", get: { $0.layout.first ?? 4 }, set: { $0.layout = [$1] }), in: 1...8) {
                    HStack { Text("Bars per line"); Spacer(); Text("\(score.layout.first ?? 4)").foregroundStyle(.secondary) }
                }
            }
            Section("Chorus \(editor.partIndex + 1) of \(max(1, score.melodyParts.count))") {
                if score.melodyParts.count > 1 {
                    Picker("Chorus", selection: $editor.partIndex) {
                        ForEach(0..<score.melodyParts.count, id: \.self) { i in
                            Text(score.melodyParts[i].info.title.isEmpty ? "Chorus \(i + 1)" : score.melodyParts[i].info.title).tag(i)
                        }
                    }
                }
                HStack {
                    Button("Add Chorus") { editor.addChorus() }
                    Button("Remove") { editor.removeChorus() }.disabled(score.melodyParts.count < 2)
                }.controlSize(.small)
                if editor.partIndex < score.melodyParts.count {
                    TextField("Chorus title", text: partText(\.title))
                    Picker("Melody instrument", selection: partInt(\.instrument)) { instrumentOptions }
                    Slider(value: partVolume, in: 0...127) { Text("Melody volume") }
                    Picker("Stave", selection: partStave) {
                        ForEach(StaveType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
            }
            Section("Accompaniment") {
                Picker("Chord instrument", selection: chordInstrument) { instrumentOptions }
                Picker("Bass instrument", selection: int(\.bassInstrument, "Change Bass Instrument", set: { $0.bassInstrument = $1 })) { instrumentOptions }
                Slider(value: dbl(\.chordVolume, "Chord Volume", set: { $0.chordVolume = Int($1) }), in: 0...127) { Text("Chords") }
                Slider(value: dbl(\.bassVolume, "Bass Volume", set: { $0.bassVolume = Int($1) }), in: 0...127) { Text("Bass") }
                Slider(value: dbl(\.drumVolume, "Drum Volume", set: { $0.drumVolume = Int($1) }), in: 0...127) { Text("Drums") }
                Slider(value: dbl(\.volume, "Master Volume", set: { $0.volume = Int($1) }), in: 0...127) { Text("Master") }
            }
            Section { SectionEditor(editor: editor) }
            Section { GeneratePanel(editor: editor) }
        }
        .formStyle(.grouped)
        .frame(minWidth: 280)
    }

    private var instrumentOptions: some View {
        ForEach(0..<128, id: \.self) { i in Text("\(i): \(GeneralMIDI.name(i))").tag(i) }
    }

    private var keyName: String {
        let n = score.key.index
        let tonic = PitchClass.chordSpelling(semitones: score.key.tonic.semitones, preferSharp: n > 0)
        return n == 0 ? "C" : "\(tonic) (\(abs(n))\(n > 0 ? "♯" : "♭"))"
    }

    // MARK: Bindings

    private func text(_ keyPath: WritableKeyPath<Score, String>, _ name: String) -> Binding<String> {
        Binding(get: { score[keyPath: keyPath] },
                set: { v in document.perform(name, undoManager: undoManager) { $0[keyPath: keyPath] = v } })
    }

    private func int<T>(_ keyPath: KeyPath<Score, T>, _ name: String, get: ((Score) -> Int)? = nil, set: @escaping (inout Score, Int) -> Void) -> Binding<Int> {
        Binding(get: { get?(score) ?? (score[keyPath: keyPath] as? Int ?? 0) },
                set: { v in document.perform(name, undoManager: undoManager) { set(&$0, v) } })
    }

    private func dbl(_ keyPath: KeyPath<Score, Int>, _ name: String, set: @escaping (inout Score, Double) -> Void) -> Binding<Double> {
        Binding(get: { Double(score[keyPath: keyPath]) },
                set: { v in document.perform(name, undoManager: undoManager) { set(&$0, v) } })
    }

    private var tempoBinding: Binding<Double> {
        Binding(get: { score.tempo },
                set: { v in
                    document.perform("Change Tempo", undoManager: undoManager) { $0.tempo = v.rounded() }
                    playback.tempo = v.rounded()
                })
    }

    private var styleBinding: Binding<String> {
        Binding(get: { score.styleName },
                set: { name in
                    document.perform("Change Style", undoManager: undoManager) { s in
                        s.styleName = name
                        s.styleOverride = nil
                        if let first = s.sections.records.first, first.measure == 0 {
                            s.sections.add(SectionRecord(measure: 0, styleName: name, isPhrase: first.isPhrase))
                        } else {
                            s.sections.add(SectionRecord(measure: 0, styleName: name))
                        }
                    }
                })
    }

    private var chordInstrument: Binding<Int> {
        Binding(get: { score.chordPart.info.instrument },
                set: { v in document.perform("Change Chord Instrument", undoManager: undoManager) { $0.chordPart.info.instrument = v } })
    }

    private func partText(_ keyPath: WritableKeyPath<PartInfo, String>) -> Binding<String> {
        let i = editor.partIndex
        return Binding(get: { i < score.melodyParts.count ? score.melodyParts[i].info[keyPath: keyPath] : "" },
                       set: { v in document.perform("Change Chorus", undoManager: undoManager) { s in if i < s.melodyParts.count { s.melodyParts[i].info[keyPath: keyPath] = v } } })
    }

    private func partInt(_ keyPath: WritableKeyPath<PartInfo, Int>) -> Binding<Int> {
        let i = editor.partIndex
        return Binding(get: { i < score.melodyParts.count ? score.melodyParts[i].info[keyPath: keyPath] : 0 },
                       set: { v in document.perform("Change Instrument", undoManager: undoManager) { s in if i < s.melodyParts.count { s.melodyParts[i].info[keyPath: keyPath] = v } } })
    }

    private var partVolume: Binding<Double> {
        let i = editor.partIndex
        return Binding(get: { i < score.melodyParts.count ? Double(score.melodyParts[i].info.volume) : 85 },
                       set: { v in document.perform("Change Volume", undoManager: undoManager) { s in if i < s.melodyParts.count { s.melodyParts[i].info.volume = Int(v) } } })
    }

    private var partStave: Binding<StaveType> {
        let i = editor.partIndex
        return Binding(get: { i < score.melodyParts.count ? score.melodyParts[i].info.stave : .treble },
                       set: { v in document.perform("Change Stave", undoManager: undoManager) { s in if i < s.melodyParts.count { s.melodyParts[i].info.stave = v } } })
    }
}
