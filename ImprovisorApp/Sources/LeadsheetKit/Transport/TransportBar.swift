//
//  TransportBar.swift
//  LeadsheetKit
//
//  Play/pause/stop, live tempo, count-in, loop, choruses, mixer, output.
//

import SwiftUI
import UniformTypeIdentifiers
import ImprovisorEngine

public struct TransportBar: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var editor: EditorController
    @State private var showMixer = false
    @State private var tempoText = ""

    public init(playback: PlaybackController, editor: EditorController) {
        self.playback = playback
        self.editor = editor
    }

    private var score: Score { editor.document.score }

    public var body: some View {
        HStack(spacing: 10) {
            Button {
                playback.togglePlayPause(score: score)
            } label: {
                Image(systemName: playback.isPlaying && !playback.isPaused ? "pause.fill" : "play.fill").frame(width: 18)
            }
            .help(playback.isPlaying && !playback.isPaused ? "Pause (Space)" : "Play (Space)")
            .accessibilityIdentifier("play")
            Button { playback.stop() } label: { Image(systemName: "stop.fill").frame(width: 18) }
                .disabled(!playback.isPlaying).help("Stop (K)").accessibilityIdentifier("stop")
            Button {
                if let sel = editor.selection { playback.play(score: score, range: sel, loop: true) }
                else { playback.play(score: score, from: editor.cursorSlot) }
            } label: { Image(systemName: "play.circle").frame(width: 18) }
                .help("Play from the cursor, or loop the selection (Return)")

            Divider().frame(height: 20)

            Toggle(isOn: $playback.countIn) { Image(systemName: "metronome") }
                .toggleStyle(.button).help("Two-bar count-in")
            Toggle(isOn: Binding(get: { playback.loopWholeForm }, set: { playback.loopWholeForm = $0; editor.loopEnabled = $0 })) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button).help("Loop the form (⌘L)")

            Divider().frame(height: 20)

            Image(systemName: "speedometer").foregroundStyle(.secondary)
            Slider(value: $playback.tempo, in: 30...300).frame(width: 140)
                .help("Tempo — adjustable while playing")
            TextField("bpm", text: $tempoText)
                .frame(width: 44).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .onSubmit { if let v = Double(tempoText) { playback.tempo = max(30, min(300, v)) } }
                .onChange(of: playback.tempo, initial: true) { _, t in tempoText = String(Int(t.rounded())) }
            Text("bpm").foregroundStyle(.secondary)

            Divider().frame(height: 20)

            Stepper(value: $playback.choruses, in: 1...16) {
                Text("\(playback.choruses) chorus\(playback.choruses == 1 ? "" : "es")").monospacedDigit()
            }.help("Times through the form")
            Button { playback.regenerate() } label: { Image(systemName: "shuffle") }
                .help("New accompaniment on the next play")

            Spacer()

            Picker("", selection: outputSelection) {
                Text("Built-in synth").tag("builtin")
                ForEach(playback.midiDestinationNames, id: \.self) { Text($0).tag("midi:" + $0) }
            }
            .labelsHidden().frame(maxWidth: 200).help("Sound output")

            Button { showMixer.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                .help("Mixer")
                .popover(isPresented: $showMixer, arrowEdge: .bottom) { MixerView(playback: playback).padding().frame(width: 320) }

            if playback.isPlaying {
                Text("bar \(playback.positionSlot / max(1, score.meter.slotsPerMeasure) % max(1, score.measureCount) + 1)")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
            }
        }
        .controlSize(.regular)
    }

    private var outputSelection: Binding<String> {
        Binding(
            get: { playback.output == .builtIn ? "builtin" : "midi:" + playback.midiDestinationHint },
            set: { value in
                if value == "builtin" { playback.output = .builtIn; playback.midiDestinationHint = "" }
                else { playback.output = .coreMIDI; playback.midiDestinationHint = String(value.dropFirst(5)) }
                playback.shutdown()
            })
    }
}
