//
//  EditorCommands.swift
//  LeadsheetKit
//
//  Menu bar commands that act on the focused window's editor.
//

import SwiftUI

public struct EditorCommands: Commands {
    @FocusedObject private var editor: EditorController?

    public init() {}

    public var body: some Commands {
        CommandMenu("Transpose") {
            Group {
                Button("Melody Up a Semitone") { editor?.transpose(.melody, by: 1) }.keyboardShortcut("e", modifiers: [.command])
                Button("Melody Down a Semitone") { editor?.transpose(.melody, by: -1) }.keyboardShortcut("d", modifiers: [.command])
                Button("Melody Up an Octave") { editor?.transpose(.melody, by: 12) }.keyboardShortcut("t", modifiers: [.command])
                Button("Melody Down an Octave") { editor?.transpose(.melody, by: -12) }.keyboardShortcut("g", modifiers: [.command])
                Divider()
                Button("Chords Up a Semitone") { editor?.transpose(.chords, by: 1) }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Chords Down a Semitone") { editor?.transpose(.chords, by: -1) }.keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Both Up a Semitone") { editor?.transpose(.both, by: 1) }.keyboardShortcut("e", modifiers: [.command, .option])
                Button("Both Down a Semitone") { editor?.transpose(.both, by: -1) }.keyboardShortcut("d", modifiers: [.command, .option])
            }
            .disabled(editor == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Edit Chords of Current Bar") { editor?.perform(.focusChords) }
                .keyboardShortcut("k", modifiers: [.command, .shift]).disabled(editor == nil)
            Button("Toggle Harmonic Entry") { editor?.perform(.toggleHarmonic) }.disabled(editor == nil)
            Button("Toggle Enharmonic Spelling") { editor?.perform(.toggleEnharmonic) }.disabled(editor == nil)
        }
    }
}
