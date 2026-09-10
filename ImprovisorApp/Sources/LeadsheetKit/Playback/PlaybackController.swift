//
//  PlaybackController.swift
//  LeadsheetKit
//
//  Main-actor façade over the engine's Transport for one document window:
//  builds the arrangement (ArrangementBuilder), owns the audio backend, and
//  publishes transport state for SwiftUI. Phase 8 grows this into the full
//  transport bar / mixer model.
//

import Foundation
import Combine
import ImprovisorEngine

public enum OutputKind: String, CaseIterable, Identifiable, Sendable {
    case builtIn = "Built-in synth"
    case coreMIDI = "MIDI out"
    public var id: String { rawValue }
}

@MainActor
public final class PlaybackController: ObservableObject {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var positionSlot = 0
    @Published public var tempo: Double = 160 { didSet { transport?.setTempo(tempo) } }
    @Published public var choruses = 1
    @Published public var seed = 1
    @Published public var output: OutputKind = .builtIn
    @Published public var midiDestinationHint = ""
    @Published public var status = ""

    public let library: DataLibrary
    private var backend: InstrumentBackend?
    private var transport: Transport?
    public private(set) var arrangement: Arrangement?

    public init(library: DataLibrary = .shared) {
        self.library = library
    }

    /// Build and play `score` from the top.
    public func play(score: Score) {
        stop()
        var options = ArrangementOptions()
        options.choruses = max(1, choruses)
        options.seed = UInt64(max(0, seed))
        let arrangement = ArrangementBuilder.build(score: score, styles: library, options: options)
        self.arrangement = arrangement
        guard !arrangement.tracks.isEmpty else { status = "Nothing to play."; return }

        guard let backend = makeBackend() else {
            status = output == .coreMIDI ? "No MIDI destination found." : "Could not start the audio engine."
            return
        }
        do { try backend.start() } catch { status = "Audio engine failed: \(error.localizedDescription)"; return }
        self.backend = backend

        let transport = Transport(backend: backend)
        transport.onPosition = { [weak self] slot in
            Task { @MainActor in self?.positionSlot = slot }
        }
        transport.onFinished = { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                self?.status = "Finished."
            }
        }
        transport.load(tracks: arrangement.tracks, slotsPerMeasure: score.meter.slotsPerMeasure)
        for track in arrangement.tracks {
            transport.setMix(TrackMix(volume: Double(track.volume) / 127, muted: false), channel: track.channel)
        }
        transport.setMasterVolume(Double(arrangement.masterVolume) / 127)
        transport.setTempo(tempo)
        self.transport = transport
        transport.play()
        isPlaying = true
        status = "Playing \(arrangement.tracks.count) tracks · \(Int(tempo)) bpm"
    }

    public func stop() {
        transport?.stop()
        transport = nil
        backend?.stop()
        backend = nil
        if isPlaying { status = "Stopped." }
        isPlaying = false
        positionSlot = 0
    }

    /// Export the current (or a fresh) arrangement of `score` as a MIDI file.
    public func exportMIDI(score: Score, to url: URL) {
        var options = ArrangementOptions()
        options.choruses = max(1, choruses)
        options.seed = UInt64(max(0, seed))
        let arrangement = ArrangementBuilder.build(score: score, styles: library, options: options)
        do {
            try MIDIFileWriter.write(tracks: arrangement.tracks, tempoBPM: tempo, to: url)
            status = "Exported \(url.lastPathComponent)"
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func makeBackend() -> InstrumentBackend? {
        switch output {
        case .builtIn: return AVAudioEngineSynth()
        case .coreMIDI: return CoreMIDIBackend(destinationHint: midiDestinationHint.isEmpty ? nil : midiDestinationHint)
        }
    }
}
