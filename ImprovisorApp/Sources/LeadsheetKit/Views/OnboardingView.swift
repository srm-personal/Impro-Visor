//
//  OnboardingView.swift
//  LeadsheetKit
//
//  First-run welcome: three short panels on entering notes, entering chords,
//  and playing along. Also reachable from the Help menu.
//

import SwiftUI

public struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    public init() {}

    private struct Panel { let title: String; let symbol: String; let lines: [String] }
    private let panels: [Panel] = [
        Panel(title: "Enter a melody", symbol: "music.note", lines: [
            "Click the staff to place a note where you point; hold ⌥ to place a rest, ⇧-click to extend the selection.",
            "Or type: the letters A–G enter notes at the cursor in the nearest octave (⇧ = octave up, ⌥ = octave down).",
            "Numbers pick the note value — 1 whole, 2 half, 4 quarter, 8 eighth, 6 sixteenth; . adds a dot, 3 makes triplets, - ties, R rests.",
            "↑/↓ move a note by step (⌥ semitone, ⌘ octave); ←/→ move the cursor; ⌫ erases; ⌘Z undoes anything.",
            "Harmonic entry (H) snaps clicked notes to the chord of the moment. The piano below shows chord tones in colour."
        ]),
        Panel(title: "Enter the chords", symbol: "textformat.abc", lines: [
            "Click above a bar (or press ⌘⇧K) to type its chords: Dm7, G7 C7, or Cmaj7 / A7 / for two beats each.",
            "Suggestions appear as you type — Tab takes the first one. Return commits and moves to the next bar; ⌥↩ splits a bar into four cells.",
            "Sections in the inspector change the accompaniment style part-way through the form.",
            "The Transpose menu moves the melody, the chords, or both."
        ]),
        Panel(title: "Play along", symbol: "play.circle", lines: [
            "Space plays or pauses; Return plays the selection in a loop; K stops.",
            "The tempo slider works while playing. Turn on the count-in, loop the form, and set how many choruses to play.",
            "Choose a style, mute or balance the mixer, and press the shuffle button for a fresh accompaniment.",
            "Generate a solo over the selection or as a new chorus from the inspector — then edit it like any melody.",
            "Open any of the 3,280 bundled tunes from File ▸ Open from Library (⌘⇧O)."
        ])
    ]

    public var body: some View {
        VStack(spacing: 16) {
            TabView(selection: $page) {
                ForEach(panels.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: panels[i].symbol).font(.largeTitle).foregroundStyle(.tint)
                            Text(panels[i].title).font(.title2.bold())
                        }
                        ForEach(panels[i].lines, id: \.self) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                Text(line)
                            }
                        }
                        Spacer()
                    }
                    .padding()
                    .tag(i)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 300)
            HStack {
                Text("Welcome to Leadsheet Studio").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if page < panels.count - 1 {
                    Button("Next") { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Start") { hasSeenOnboarding = true; dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .onDisappear { hasSeenOnboarding = true }
    }
}
