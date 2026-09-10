//
//  SnapshotRenderer.swift
//  LeadsheetKit
//
//  Renders notation to PNG data — for tests (the agent inspects the images),
//  for print/PDF previews, and for README screenshots.
//

import SwiftUI
import AppKit
import ImprovisorEngine

@MainActor
public enum SnapshotRenderer {

    /// PNG of a laid-out score.
    public static func png(layout: LayoutDocument, theme: StaveTheme = .light, scale: CGFloat = 2) -> Data? {
        let view = StaveCanvas(layout: layout, theme: theme)
            .background(theme.background)
        return png(view: view, size: CGSize(width: layout.width, height: layout.height), scale: scale)
    }

    /// PNG of any view at a fixed size.
    public static func png<V: View>(view: V, size: CGSize, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        guard let cg = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    /// Convenience: lay out and render a score.
    public static func png(score: Score, part: Int = 0, options: StaveOptions = StaveOptions(),
                           theme: StaveTheme = .light, scale: CGFloat = 2) -> Data? {
        png(layout: StaveLayout.layout(score: score, part: part, options: options), theme: theme, scale: scale)
    }
}
