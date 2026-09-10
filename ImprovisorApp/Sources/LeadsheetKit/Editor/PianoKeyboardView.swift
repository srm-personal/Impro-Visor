//
//  PianoKeyboardView.swift
//  LeadsheetKit
//
//  An on-screen piano: two octaves centred on the editor's last pitch, chord
//  tones of the chord at the cursor highlighted; clicking a key enters that
//  pitch at the cursor with the current duration.
//

import SwiftUI
import ImprovisorEngine

public struct PianoKeyboardView: View {
    @ObservedObject var editor: EditorController
    public var octaves = 2

    public init(editor: EditorController, octaves: Int = 2) {
        self.editor = editor
        self.octaves = octaves
    }

    private var lowC: Int {
        // Start at the C below the last pitch's octave, clamped.
        let base = (editor.lastPitch / 12) * 12 - 12
        return max(24, min(96, base))
    }

    public var body: some View {
        GeometryReader { geo in
            let whiteCount = octaves * 7 + 1
            let whiteW = geo.size.width / CGFloat(whiteCount)
            let h = geo.size.height
            let chord = editor.chord(atSlot: editor.cursorSlot)
            let chordTones = Set(chord?.chordTones.map(\.semitones) ?? [])
            let colorTones = Set(chord?.colorTones.map(\.semitones) ?? [])
            ZStack(alignment: .topLeading) {
                // White keys.
                ForEach(0..<whiteCount, id: \.self) { i in
                    let pitch = lowC + whiteOffset(i)
                    keyView(pitch: pitch, isBlack: false, chordTones: chordTones, colorTones: colorTones)
                        .frame(width: whiteW - 1, height: h)
                        .offset(x: CGFloat(i) * whiteW)
                }
                // Black keys.
                ForEach(0..<(octaves * 7), id: \.self) { i in
                    if [0, 1, 3, 4, 5].contains(i % 7) {
                        let pitch = lowC + whiteOffset(i) + 1
                        keyView(pitch: pitch, isBlack: true, chordTones: chordTones, colorTones: colorTones)
                            .frame(width: whiteW * 0.6, height: h * 0.62)
                            .offset(x: CGFloat(i) * whiteW + whiteW * 0.7)
                    }
                }
            }
        }
        .frame(minHeight: 70)
        .accessibilityIdentifier("piano")
    }

    private func whiteOffset(_ i: Int) -> Int { (i / 7) * 12 + [0, 2, 4, 5, 7, 9, 11][i % 7] }

    private func keyView(pitch: Int, isBlack: Bool, chordTones: Set<Int>, colorTones: Set<Int>) -> some View {
        let pc = pitch % 12
        let isChord = chordTones.contains(pc), isColor = colorTones.contains(pc)
        let isLast = pitch == editor.lastPitch
        let fill: Color = isChord ? Color.accentColor.opacity(isBlack ? 0.9 : 0.35)
            : (isColor ? Color.orange.opacity(isBlack ? 0.8 : 0.3) : (isBlack ? Color.black : Color.white))
        return Button {
            editor.enter(pitch: pitch, snap: false)
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(isLast ? Color.red : Color.gray.opacity(0.7), lineWidth: isLast ? 2 : 0.8))
                .overlay(alignment: .bottom) {
                    if pc == 0 && !isBlack {
                        Text("C\(pitch / 12 - 1)").font(.system(size: 9)).foregroundStyle(.secondary).padding(.bottom, 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(NoteSerializer.pitchToken(pitch, spelling: .natural))
    }
}
