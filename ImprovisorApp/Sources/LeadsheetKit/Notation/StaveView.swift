//
//  StaveView.swift
//  LeadsheetKit
//
//  The scrolling notation view: lays the score out for the available width
//  (cached until the score or width changes) and draws it with StaveRenderer,
//  with a separate overlay layer for playhead / selection / cursor so those
//  redraw without re-laying-out.
//

import SwiftUI
import ImprovisorEngine

/// Caches the last layout for a (score, part, options) triple.
@MainActor
final class LayoutCache: ObservableObject {
    private var key: (Score, Int, StaveOptions)?
    private var cached: LayoutDocument?

    func layout(score: Score, part: Int, options: StaveOptions) -> LayoutDocument {
        if let key, let cached, key.0 == score, key.1 == part, key.2 == options { return cached }
        let doc = StaveLayout.layout(score: score, part: part, options: options)
        key = (score, part, options)
        cached = doc
        return doc
    }
}

/// What the user pointed at in the stave.
public struct StaveHit: Equatable, Sendable {
    public var slot: Int
    public var diatonic: Int
    public var clef: Clef
    public var measure: Int
    /// The piece under the pointer, if any.
    public var pieceIndex: Int?
    public var point: CGPoint
}

/// Pointer interaction callbacks (points are in stave coordinates).
public struct StaveInteraction {
    public var onClick: (CGPoint, KeyEvent.Modifiers) -> Void
    public var onDragBegan: (CGPoint) -> Void
    public var onDragChanged: (CGPoint) -> Void
    public var onDragEnded: () -> Void

    public init(onClick: @escaping (CGPoint, KeyEvent.Modifiers) -> Void,
                onDragBegan: @escaping (CGPoint) -> Void,
                onDragChanged: @escaping (CGPoint) -> Void,
                onDragEnded: @escaping () -> Void) {
        self.onClick = onClick
        self.onDragBegan = onDragBegan
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
    }
}

public struct StaveView: View {
    public var score: Score
    public var part: Int = 0
    public var options: StaveOptions
    public var overlay: StaveRenderer.Overlay
    public var onLayout: ((LayoutDocument) -> Void)?
    public var interaction: StaveInteraction?
    /// Extra views laid over the stave in its coordinate space (e.g. chord cells).
    public var decorations: ((LayoutDocument) -> AnyView)?
    @State private var dragging = false

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var cache = LayoutCache()

    public init(score: Score, part: Int = 0, options: StaveOptions = StaveOptions(),
                overlay: StaveRenderer.Overlay = StaveRenderer.Overlay(),
                onLayout: ((LayoutDocument) -> Void)? = nil,
                interaction: StaveInteraction? = nil,
                decorations: ((LayoutDocument) -> AnyView)? = nil) {
        self.score = score
        self.part = part
        self.options = options
        self.overlay = overlay
        self.onLayout = onLayout
        self.interaction = interaction
        self.decorations = decorations
    }

    private static func currentModifiers() -> KeyEvent.Modifiers {
        var mods = KeyEvent.Modifiers()
        let flags = NSApp?.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        return mods
    }

    public var body: some View {
        GeometryReader { geo in
            let width = max(320, geo.size.width)
            var opts = options
            let _ = { opts.width = width }()
            let layout = cache.layout(score: score, part: part, options: opts)
            let theme = StaveTheme.forScheme(colorScheme)
            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    StaveCanvas(layout: layout, theme: theme)
                    OverlayCanvas(layout: layout, theme: theme, overlay: overlay)
                    Color.clear.contentShape(Rectangle())
                        .frame(width: width, height: layout.height)
                        .gesture(staveGesture)
                    if let decorations { decorations(layout) }
                }
                .frame(width: width, height: layout.height)
                .onAppear { onLayout?(layout) }
                .onChange(of: layout) { _, new in onLayout?(new) }
            }
            .background(theme.background)
        }
    }

    private var staveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let interaction else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                if !dragging {
                    if moved > 3 { dragging = true; interaction.onDragBegan(value.startLocation); interaction.onDragChanged(value.location) }
                } else {
                    interaction.onDragChanged(value.location)
                }
            }
            .onEnded { value in
                guard let interaction else { return }
                if dragging { interaction.onDragEnded(); dragging = false }
                else { interaction.onClick(value.location, StaveView.currentModifiers()) }
            }
    }
}

/// Just the notation (no overlay), also used for snapshots and printing.
public struct StaveCanvas: View {
    public var layout: LayoutDocument
    public var theme: StaveTheme

    public init(layout: LayoutDocument, theme: StaveTheme = .light) {
        self.layout = layout
        self.theme = theme
    }

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            StaveRenderer.draw(layout, in: &context, theme: theme, visible: CGRect(origin: .zero, size: size))
        }
        .frame(width: layout.width, height: layout.height)
    }
}

struct OverlayCanvas: View {
    var layout: LayoutDocument
    var theme: StaveTheme
    var overlay: StaveRenderer.Overlay

    var body: some View {
        Canvas { context, _ in
            StaveRenderer.drawOverlay(overlay, layout: layout, in: &context, theme: theme)
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
    }
}
