//
//  KeyEventHost.swift
//  LeadsheetKit
//
//  An invisible AppKit view that becomes first responder for the stave and
//  turns NSEvents into KeyEvents for the EditorController. Command shortcuts
//  reach the menu bar first (Undo, Cut/Copy/Paste, Select All), which route
//  back here through the responder chain selectors.
//

import SwiftUI
import AppKit

public struct KeyEventHost: NSViewRepresentable {
    public var controller: EditorController
    /// Bump to request keyboard focus.
    public var focusToken: Int

    public init(controller: EditorController, focusToken: Int) {
        self.controller = controller
        self.focusToken = focusToken
    }

    public func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.controller = controller
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    public func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.controller = controller
        if context.coordinator.lastToken != focusToken {
            context.coordinator.lastToken = focusToken
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }
    public final class Coordinator { var lastToken = -1 }
}

public final class KeyCatcherView: NSView {
    weak var controller: EditorController?

    public override var acceptsFirstResponder: Bool { true }
    public override var isFlipped: Bool { true }

    public override func keyDown(with event: NSEvent) {
        guard let controller, let key = KeyCatcherView.keyEvent(from: event) else { return super.keyDown(with: event) }
        if !controller.handle(key) { super.keyDown(with: event) }
    }

    // Edit-menu selectors (the menu bar owns ⌘X/C/V/A/Z).
    @objc public func cut(_ sender: Any?) { controller?.perform(.cut(.melody)) }
    @objc public func copy(_ sender: Any?) { controller?.perform(.copy(.melody)) }
    @objc public func paste(_ sender: Any?) { controller?.perform(.paste(.melody)) }
    public override func selectAll(_ sender: Any?) { controller?.perform(.selectAll) }
    @objc public func delete(_ sender: Any?) { controller?.perform(.eraseSelection) }

    public override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool { true }

    static func keyEvent(from event: NSEvent) -> KeyEvent? {
        var mods = KeyEvent.Modifiers()
        if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
        if event.modifierFlags.contains(.option) { mods.insert(.option) }
        if event.modifierFlags.contains(.command) { mods.insert(.command) }
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        switch event.keyCode {
        case 126: return KeyEvent(special: .up, modifiers: mods)
        case 125: return KeyEvent(special: .down, modifiers: mods)
        case 123: return KeyEvent(special: .left, modifiers: mods)
        case 124: return KeyEvent(special: .right, modifiers: mods)
        case 51: return KeyEvent(special: .delete, modifiers: mods)
        case 117: return KeyEvent(special: .forwardDelete, modifiers: mods)
        case 53: return KeyEvent(special: .escape, modifiers: mods)
        case 36, 76: return KeyEvent(special: .return, modifiers: mods)
        case 49: return KeyEvent(special: .space, modifiers: mods)
        case 48: return KeyEvent(special: .tab, modifiers: mods)
        default: break
        }
        // Use the unmodified character so ⌥/⇧ letters still map to letters.
        guard let chars = event.charactersIgnoringModifiers, let first = chars.first else { return nil }
        if first.isLetter || first.isNumber || ".-=[]".contains(first) {
            return KeyEvent(String(first), modifiers: mods)
        }
        return nil
    }
}
