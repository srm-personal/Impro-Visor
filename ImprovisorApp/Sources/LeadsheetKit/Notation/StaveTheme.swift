//
//  StaveTheme.swift
//  LeadsheetKit
//

import SwiftUI

public struct StaveTheme: Equatable, Sendable {
    public var background: Color
    public var ink: Color
    public var staffLine: Color
    public var chordSymbol: Color
    public var sectionMarker: Color
    public var measureNumber: Color
    public var playhead: Color
    public var selection: Color
    public var cursor: Color

    public init(background: Color, ink: Color, staffLine: Color, chordSymbol: Color, sectionMarker: Color,
                measureNumber: Color, playhead: Color, selection: Color, cursor: Color) {
        self.background = background
        self.ink = ink
        self.staffLine = staffLine
        self.chordSymbol = chordSymbol
        self.sectionMarker = sectionMarker
        self.measureNumber = measureNumber
        self.playhead = playhead
        self.selection = selection
        self.cursor = cursor
    }

    public static let light = StaveTheme(
        background: Color(red: 0.99, green: 0.985, blue: 0.97), ink: .black,
        staffLine: Color(white: 0.25), chordSymbol: Color(red: 0.05, green: 0.2, blue: 0.45),
        sectionMarker: Color(red: 0.55, green: 0.3, blue: 0.05), measureNumber: Color(white: 0.5),
        playhead: Color(red: 0.85, green: 0.2, blue: 0.1), selection: Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.18),
        cursor: Color(red: 0.2, green: 0.5, blue: 0.9))

    public static let dark = StaveTheme(
        background: Color(red: 0.11, green: 0.11, blue: 0.12), ink: Color(white: 0.92),
        staffLine: Color(white: 0.7), chordSymbol: Color(red: 0.55, green: 0.75, blue: 1.0),
        sectionMarker: Color(red: 0.95, green: 0.7, blue: 0.35), measureNumber: Color(white: 0.55),
        playhead: Color(red: 1.0, green: 0.4, blue: 0.3), selection: Color(red: 0.4, green: 0.65, blue: 1.0).opacity(0.25),
        cursor: Color(red: 0.4, green: 0.65, blue: 1.0))

    public static func forScheme(_ scheme: ColorScheme) -> StaveTheme { scheme == .dark ? .dark : .light }
}
