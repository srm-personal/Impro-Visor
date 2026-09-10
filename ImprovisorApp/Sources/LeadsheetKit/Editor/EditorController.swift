//
//  EditorController.swift
//  LeadsheetKit
//
//  The notation editor's brain: cursor, selection, entry state, and every edit
//  command (keyboard, mouse, palette, piano, MIDI all funnel into `perform`).
//  Edits go through the document's undoable `perform`, so undo names are right
//  and the UI updates through the document's publisher.
//

import Foundation
import SwiftUI
import ImprovisorEngine

@MainActor
public final class EditorController: ObservableObject {
    public let document: LeadsheetDocument
    public weak var undoManager: UndoManager?
    public weak var playback: PlaybackController?

    @Published public var partIndex = 0
    @Published public var cursorSlot = 0
    @Published public var selection: Range<Int>?
    @Published public var entry = EntryState()
    /// Layout of the current stave (set by the view) for hit testing.
    @Published public var layout: LayoutDocument?
    /// Pitch of the last entered note — new letters pick the octave nearest it.
    @Published public var lastPitch = 60
    @Published public var loopEnabled = false
    @Published public var status = ""

    /// Sound entered notes.
    public var auditions = true

    private var dragStart: (point: CGPoint, slot: Int, pitch: Int?, eventRange: Range<Int>?)?

    public init(document: LeadsheetDocument, playback: PlaybackController? = nil) {
        self.document = document
        self.playback = playback
        if let first = document.score.melodyParts.first?.notes.first { lastPitch = first.pitch }
    }

    // MARK: Derived

    public var score: Score { document.score }
    public var meter: Meter { score.meter }
    public var formSlots: Int { max(score.chordPart.size, melody.size) }

    public var melody: MelodyPart {
        partIndex < score.melodyParts.count ? score.melodyParts[partIndex] : MelodyPart()
    }

    /// The range an edit applies to: the selection, else the event at the cursor.
    public var targetRange: Range<Int>? {
        if let selection, !selection.isEmpty { return selection }
        if let p = melody.event(atSlot: cursorSlot), !p.event.isRest { return p.start..<p.end }
        return nil
    }

    public func chord(atSlot slot: Int) -> ChordSymbol? { score.chordPart.chord(at: slot) }

    /// Overlay state for the stave.
    public var overlay: StaveRenderer.Overlay {
        let clef: Clef = layout?.isGrand == true && lastPitch < score.breakpoint ? .bass : (melody.info.stave == .bass ? .bass : .treble)
        let d = PitchSpelling.spell(Note(pitch: lastPitch, duration: 1), key: score.key).diatonic
        return StaveRenderer.Overlay(playheadSlot: playback?.isPlaying == true ? (playback?.positionSlot ?? 0) % max(1, formSlots) : nil,
                                     selection: selection, cursorSlot: cursorSlot,
                                     cursorDiatonic: d, cursorClef: clef)
    }

    // MARK: Editing primitives

    private func edit(_ name: String, _ body: (inout MelodyPart) -> Void) {
        let index = partIndex
        document.perform(name, undoManager: undoManager) { score in
            while score.melodyParts.count <= index { score.melodyParts.append(MelodyPart(events: [])) }
            var part = score.melodyParts[index]
            body(&part)
            part.fill(to: max(score.chordPart.size, part.size))
            score.melodyParts[index] = part
        }
    }

    private func ensureForm(_ slot: Int) -> Bool {
        formSlots > 0 && slot >= 0 && slot < formSlots
    }

    /// Enter a note at the cursor with the current duration and advance.
    public func enter(pitch rawPitch: Int, at slot: Int? = nil, snap: Bool = false, spelling: Accidental? = nil) {
        let at = slot ?? cursorSlot
        guard ensureForm(at) else { return }
        var pitch = max(0, min(127, rawPitch))
        if snap {
            let chord = chord(atSlot: at)
            if entry.approachNext {
                pitch = Harmony.nearest(pitch, in: Harmony.approachPitchClasses(for: chord))
            } else if entry.harmonic {
                pitch = Harmony.snap(pitch, chord: chord, mode: entry.mode)
            }
        }
        entry.approachNext = false
        let duration = min(entry.slots, formSlots - at)
        let spell = spelling ?? (Harmony.approachPitchClasses(for: chord(atSlot: at)).isEmpty ? .natural : .natural)
        edit("Enter Note") { $0.setNote(at: at, pitch: pitch, duration: duration, spelling: spell) }
        lastPitch = pitch
        selection = nil
        cursorSlot = min(formSlots, at + duration)
        audition(pitch)
    }

    /// Enter a letter (0–6 = C…B) in the octave nearest the last pitch.
    public func enter(letter: Int, octaveShift: Int) {
        let natural = Harmony.pitch(letter: letter, octave: 4, key: score.key)
        // Candidate octaves; choose the one nearest lastPitch.
        var best = natural
        for oct in -2...9 {
            let p = natural + (oct - 4) * 12
            if abs(p - lastPitch) < abs(best - lastPitch) { best = p }
        }
        best += octaveShift * 12
        let spelling: Accidental = (best % 12 == 1 || best % 12 == 3 || best % 12 == 6 || best % 12 == 8 || best % 12 == 10)
            ? (score.key.index > 0 ? .sharp : .flat) : .natural
        enter(pitch: best, snap: false, spelling: spelling)
    }

    public func enterRest() {
        guard ensureForm(cursorSlot) else { return }
        let duration = min(entry.slots, formSlots - cursorSlot)
        edit("Enter Rest") { $0.setRest(at: self.cursorSlot, duration: duration) }
        selection = nil
        cursorSlot += duration
    }

    public func tie() {
        guard cursorSlot > 0, cursorSlot < formSlots else { return }
        let extra = min(entry.slots, formSlots - cursorSlot)
        edit("Extend Note") { $0.extendNote(endingAt: self.cursorSlot, by: extra) }
        cursorSlot += extra
    }

    public func eraseSelection() {
        guard let range = targetRange else { return }
        edit("Delete") { $0.erase(range: range) }
        cursorSlot = range.lowerBound
        selection = nil
    }

    public func removeSelection() {
        guard let range = targetRange else { return }
        edit("Remove") { part in
            part.remove(range: range)
            part.fill(to: max(part.size, self.score.chordPart.size))
        }
        cursorSlot = range.lowerBound
        selection = nil
    }

    public func transposeSelection(by semitones: Int) {
        guard let range = targetRange else { return }
        edit("Transpose") { $0.transpose(range: range, by: semitones) }
        if let n = melody.event(atSlot: range.lowerBound)?.event.note { lastPitch = n.pitch }
    }

    public func stepSelection(by steps: Int) {
        guard let range = targetRange else { return }
        let key = score.key
        edit("Move Pitch") { $0.mapNotes(in: range) { n in n.withPitch(Harmony.step(n.pitch, by: steps, key: key)) } }
        if let n = melody.event(atSlot: range.lowerBound)?.event.note { lastPitch = n.pitch; audition(n.pitch) }
    }

    public func toggleEnharmonic() {
        guard let range = targetRange else { return }
        edit("Enharmonic") { $0.mapNotes(in: range) { $0.enharmonicToggled() } }
    }

    public func nudgeSelection(by direction: Int) {
        guard let range = targetRange else { return }
        let delta = direction * entry.slots
        let newStart = range.lowerBound + delta
        guard newStart >= 0, newStart + range.count <= formSlots else { return }
        let content = melody.events(in: range)
        edit("Move Notes") { part in
            part.erase(range: range)
            part.replace(range: newStart..<(newStart + range.count), with: content)
        }
        selection = newStart..<(newStart + range.count)
        cursorSlot = newStart
    }

    // MARK: Cursor / selection

    public func moveCursor(by direction: Int) {
        let step = entry.slots
        cursorSlot = max(0, min(formSlots, cursorSlot + direction * step))
        selection = nil
    }

    public func extendSelection(by direction: Int) {
        let step = entry.slots
        let current = selection ?? cursorSlot..<cursorSlot
        let anchor = current.lowerBound == cursorSlot ? current.upperBound : current.lowerBound
        cursorSlot = max(0, min(formSlots, cursorSlot + direction * step))
        selection = min(anchor, cursorSlot)..<max(anchor, cursorSlot)
        if selection?.isEmpty == true { selection = nil }
    }

    public func selectAll() {
        selection = 0..<formSlots
        cursorSlot = 0
    }

    public func select(range: Range<Int>?) {
        selection = range.flatMap { $0.isEmpty ? nil : $0 }
        if let range { cursorSlot = range.lowerBound }
    }

    // MARK: Clipboard

    public func copy(_ scope: ClipboardScope) {
        let range = selection ?? (targetRange ?? cursorSlot..<min(formSlots, cursorSlot + entry.slots))
        var clip = Clip(meter: meter)
        if scope != .chords { clip.melody = melody.events(in: range) }
        if scope != .melody { clip.chords = score.chordPart.slice(range) }
        Clipboard.write(clip)
        status = "Copied \(range.count / max(1, meter.slotsPerBeat)) beats"
    }

    public func cut(_ scope: ClipboardScope) {
        copy(scope)
        if scope != .chords { eraseSelection() }
        if scope != .melody, let range = selection ?? targetRange {
            document.perform("Cut Chords", undoManager: undoManager) { score in
                score.chordPart = score.chordPart.replacing(range: range, with: ChordPart())
            }
        }
    }

    public func paste(_ scope: ClipboardScope) {
        guard let clip = Clipboard.read(meter: meter, vocabulary: DataLibrary.shared.vocabulary) else { return }
        let at = selection?.lowerBound ?? cursorSlot
        if scope != .chords, let events = clip.melody, !events.isEmpty {
            let length = min(events.reduce(0) { $0 + $1.duration }, formSlots - at)
            guard length > 0 else { return }
            edit("Paste") { $0.replace(range: at..<(at + length), with: events) }
            cursorSlot = at + length
            selection = nil
        }
        if scope != .melody, let chords = clip.chords, chords.size > 0 {
            document.perform("Paste Chords", undoManager: undoManager) { score in
                score.chordPart = score.chordPart.replacing(range: at..<min(score.chordPart.size, at + chords.size), with: chords)
            }
        }
    }

    // MARK: Mouse

    /// Quantize a raw slot to the current duration grid within its measure.
    public func quantize(_ slot: Int) -> Int {
        let grid = max(1, min(entry.slots, meter.slotsPerBeat))
        let spm = max(1, meter.slotsPerMeasure)
        let inBar = slot % spm
        return slot - inBar + (inBar / grid) * grid
    }

    /// Resolve a click point to a slot and pitch (nil pitch when off-staff).
    public func hit(at point: CGPoint) -> (slot: Int, pitch: Int?, piece: Int?)? {
        guard let layout, let rawSlot = layout.slot(at: point) else { return nil }
        let slot = quantize(rawSlot)
        var pitch: Int?
        if let (d, _) = layout.diatonic(at: point) {
            pitch = Harmony.pitch(letter: Diatonic.letter(d), octave: Diatonic.octave(d), key: score.key)
        }
        // A note head under the pointer?
        let sp = layout.geometry.spaceHeight
        var piece: Int?
        for glyph in layout.glyphs {
            if case let .noteHead(x, y, _, index) = glyph, abs(x - point.x) <= sp * 0.9, abs(y - point.y) <= sp * 0.7 {
                piece = index
                break
            }
        }
        return (slot, pitch, piece)
    }

    /// A click: on a note selects it; elsewhere enters a note (or rest with ⌥) at the point.
    public func click(at point: CGPoint, modifiers: KeyEvent.Modifiers = []) {
        guard let hit = hit(at: point) else { return }
        if let index = hit.piece, let layout, index < layout.pieces.count {
            let piece = layout.pieces[index]
            if let placed = melody.placed.first(where: { $0.index == piece.eventIndex }) {
                if modifiers.contains(.shift), let sel = selection {
                    selection = min(sel.lowerBound, placed.start)..<max(sel.upperBound, placed.end)
                } else {
                    selection = placed.start..<placed.end
                }
                cursorSlot = placed.start
                if let n = placed.event.note { lastPitch = n.pitch; audition(n.pitch) }
            }
            return
        }
        if modifiers.contains(.shift) {
            let anchor = selection?.lowerBound ?? cursorSlot
            selection = min(anchor, hit.slot)..<max(anchor, hit.slot + entry.slots)
            return
        }
        if modifiers.contains(.option) {
            cursorSlot = hit.slot
            enterRest()
            return
        }
        guard let pitch = hit.pitch else { cursorSlot = hit.slot; selection = nil; return }
        enter(pitch: pitch, at: hit.slot, snap: true)
    }

    public func beginDrag(at point: CGPoint) {
        guard let hit = hit(at: point) else { dragStart = nil; return }
        var range: Range<Int>?
        if let index = hit.piece, let layout, index < layout.pieces.count,
           let placed = melody.placed.first(where: { $0.index == layout.pieces[index].eventIndex }) {
            range = placed.start..<placed.end
            selection = range
            cursorSlot = placed.start
        }
        dragStart = (point, hit.slot, hit.pitch, range)
    }

    /// Vertical drag changes pitch (snapped in harmonic mode); horizontal drag moves in time.
    public func drag(to point: CGPoint) {
        guard let start = dragStart, let range = start.eventRange, let layout else { return }
        let dy = point.y - start.point.y, dx = point.x - start.point.x
        if abs(dy) >= abs(dx), abs(dy) >= layout.geometry.stepHeight {
            let steps = -Int((dy / layout.geometry.stepHeight).rounded())
            guard steps != 0, let n = melody.event(atSlot: range.lowerBound)?.event.note else { return }
            let original = originalPitch ?? n.pitch
            var target = Harmony.step(original, by: steps, key: score.key)
            if entry.harmonic { target = Harmony.snap(target, chord: chord(atSlot: range.lowerBound), mode: entry.mode) }
            originalPitch = original
            if target != n.pitch {
                edit("Change Pitch") { $0.mapNotes(in: range) { $0.withPitch(target) } }
                lastPitch = target
            }
        } else if abs(dx) >= abs(dy), let slot = layout.slot(at: CGPoint(x: point.x, y: start.point.y)) {
            let newStart = quantize(slot)
            guard newStart != range.lowerBound, newStart >= 0, newStart + range.count <= formSlots else { return }
            let content = melody.events(in: range)
            edit("Move Note") { part in
                part.erase(range: range)
                part.replace(range: newStart..<(newStart + range.count), with: content)
            }
            dragStart?.eventRange = newStart..<(newStart + range.count)
            selection = dragStart?.eventRange
            cursorSlot = newStart
        }
    }

    private var originalPitch: Int?

    public func endDrag() {
        if let range = dragStart?.eventRange, let n = melody.event(atSlot: range.lowerBound)?.event.note, originalPitch != nil {
            audition(n.pitch)
        }
        dragStart = nil
        originalPitch = nil
    }

    // MARK: Actions

    /// Handle a key event; returns whether it was consumed.
    @discardableResult
    public func handle(_ key: KeyEvent) -> Bool {
        guard let action = KeyMap.action(for: key) else { return false }
        perform(action)
        return true
    }

    public func perform(_ action: EditorAction) {
        switch action {
        case let .enterPitch(letter, octaveShift): enter(letter: letter, octaveShift: octaveShift)
        case let .setBase(base): entry.base = base
        case .toggleDot: entry.dotted.toggle()
        case .toggleTriplet: entry.triplet.toggle()
        case .tie: tie()
        case .rest: enterRest()
        case .eraseSelection: eraseSelection()
        case .removeSelection: removeSelection()
        case let .moveCursor(d): moveCursor(by: d)
        case let .extendSelection(d): extendSelection(by: d)
        case let .nudgeSelection(d): nudgeSelection(by: d)
        case let .stepPitch(d): stepSelection(by: d)
        case let .transpose(s): transposeSelection(by: s)
        case .toggleHarmonic: entry.harmonic.toggle(); status = entry.harmonic ? "Harmonic entry" : "Simple entry"
        case .approachNext: entry.approachNext = true; status = "Next note: approach tone"
        case .toggleEnharmonic: toggleEnharmonic()
        case .playPause: playback?.togglePlayPause(score: score)
        case .playSelection:
            if let range = selection { playback?.play(score: score, range: range, loop: true) }
            else { playback?.play(score: score, from: cursorSlot) }
        case .stop: playback?.stop()
        case .toggleLoop: loopEnabled.toggle(); playback?.loopWholeForm = loopEnabled
        case let .tempoDelta(d): if let p = playback { p.tempo = max(30, min(300, p.tempo + d)) }
        case .undo: undoManager?.undo()
        case .redo: undoManager?.redo()
        case let .cut(scope): cut(scope)
        case let .copy(scope): copy(scope)
        case let .paste(scope): paste(scope)
        case .selectAll: selectAll()
        case .escape: selection = nil; playback?.stop()
        case .focusChords, .generateSolo: break // handled by the view / Phase 8
        }
    }

    // MARK: Sound

    private func audition(_ pitch: Int) {
        guard auditions else { return }
        playback?.audition(pitch: pitch, program: melody.info.instrument)
    }
}

extension Note {
    func withPitch(_ p: Int) -> Note { Note(pitch: max(0, min(127, p)), duration: duration, volume: volume, spelling: spelling) }
}

public extension ChordPart {
    /// This progression with `range` replaced by `new` (re-based at the range
    /// start, trimmed/padded to the range; empty `new` = hold the previous chord).
    func replacing(range: Range<Int>, with new: ChordPart) -> ChordPart {
        guard !range.isEmpty, size > 0 else { return self }
        var out = ChordPart(info: info)
        let clipped = range.lowerBound..<min(range.upperBound, size)
        // Before.
        for e in slice(0..<clipped.lowerBound).entries { out.append(e.symbol, duration: e.duration) }
        // Replacement.
        var filled = 0
        for e in new.entries where filled < clipped.count {
            let d = min(e.duration, clipped.count - filled)
            out.append(e.symbol, duration: d)
            filled += d
        }
        if filled < clipped.count {
            let hold = out.entries.last?.symbol ?? .noChord
            out.append(hold, duration: clipped.count - filled)
        }
        // After.
        for e in slice(clipped.upperBound..<size).entries { out.append(e.symbol, duration: e.duration) }
        return out.mergingRepeats()
    }

    /// Adjacent identical chords merged into one entry.
    func mergingRepeats() -> ChordPart {
        var out = ChordPart(info: info)
        for e in entries {
            if let last = out.entries.last, last.symbol == e.symbol {
                out.extendLast(by: e.duration)
            } else {
                out.append(e.symbol, duration: e.duration)
            }
        }
        return out
    }
}
