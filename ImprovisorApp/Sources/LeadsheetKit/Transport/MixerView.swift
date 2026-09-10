//
//  MixerView.swift
//  LeadsheetKit
//

import SwiftUI
import ImprovisorEngine

public struct MixerView: View {
    @ObservedObject var playback: PlaybackController

    public init(playback: PlaybackController) { self.playback = playback }

    private let channels: [(String, UInt8)] = [("Melody", 2), ("Chords", 1), ("Bass", 0), ("Drums", 9)]

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mixer").font(.headline)
            ForEach(channels, id: \.1) { name, channel in
                HStack {
                    Text(name).frame(width: 60, alignment: .leading)
                    Slider(value: volumeBinding(channel), in: 0...1)
                    Toggle(isOn: muteBinding(channel)) { Image(systemName: "speaker.slash.fill") }
                        .toggleStyle(.button).controlSize(.small).help("Mute \(name)")
                }
            }
            Divider()
            HStack {
                Text("Master").frame(width: 60, alignment: .leading)
                Slider(value: $playback.masterVolume, in: 0...1)
            }
            Button("Reset to tune levels") { playback.mixOverrides = [:]; playback.masterVolume = 1 }.controlSize(.small)
        }
    }

    private func volumeBinding(_ channel: UInt8) -> Binding<Double> {
        Binding(get: { playback.mix(forChannel: channel).volume },
                set: { v in var m = playback.mix(forChannel: channel); m.volume = v; playback.mixOverrides[channel] = m })
    }

    private func muteBinding(_ channel: UInt8) -> Binding<Bool> {
        Binding(get: { playback.mix(forChannel: channel).muted },
                set: { v in var m = playback.mix(forChannel: channel); m.muted = v; playback.mixOverrides[channel] = m })
    }
}
