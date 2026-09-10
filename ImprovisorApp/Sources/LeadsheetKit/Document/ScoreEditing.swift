//
//  ScoreEditing.swift
//  LeadsheetKit
//
//  Undoable edits. Instead of one command class per edit (the Java app has ~50),
//  every edit is a closure over `inout Score`; the previous value is captured
//  and registered with the UndoManager so undo/redo is a value swap. Rapid
//  edits of the same kind (typing) can be grouped with `beginGroup`/`endGroup`.
//

import Foundation
import ImprovisorEngine

@MainActor
public extension LeadsheetDocument {

    /// Apply `edit` to the score as an undoable action named `name`.
    func perform(_ name: String, undoManager: UndoManager?, _ edit: (inout Score) -> Void) {
        let old = score
        var new = old
        edit(&new)
        guard new != old else { return }
        replaceScore(with: new, old: old, name: name, undoManager: undoManager)
    }

    /// Replace the whole score (used by open-from-library, generators, undo).
    func replaceScore(with new: Score, old: Score? = nil, name: String, undoManager: UndoManager?) {
        let previous = old ?? score
        score = new
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.replaceScore(with: previous, old: new, name: name, undoManager: undoManager)
            }
        }
        undoManager?.setActionName(name)
    }
}
