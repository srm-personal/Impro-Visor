//
//  SectionInfo.swift
//  ImprovisorEngine
//
//  Section structure of a lead sheet: a list of sections, each starting at a
//  measure and (optionally) declaring its own style. Ports the data behavior of
//  imp/style/SectionInfo and SectionRecord.
//

import Foundation

/// A single section: where it starts and which style plays it.
public struct SectionRecord: Equatable, Sendable {
    /// Zero-based measure index at which this section begins.
    public var measure: Int
    /// Style name for this section. Empty means "use the previous style"
    /// (Java writes this as `(section (style))`).
    public var styleName: String
    /// `true` for a `(phrase …)` marker, `false` for a `(section …)` marker.
    public var isPhrase: Bool

    public init(measure: Int, styleName: String = "", isPhrase: Bool = false) {
        self.measure = measure
        self.styleName = styleName
        self.isPhrase = isPhrase
    }

    /// Whether this record inherits the style in effect before it.
    public var usesPreviousStyle: Bool { styleName.isEmpty }
}

/// The ordered list of sections, kept sorted by measure with at most one
/// record per measure (the Java `SectionInfo.addSection` invariant).
public struct SectionInfo: Equatable, Sendable {
    public private(set) var records: [SectionRecord]

    public init(records: [SectionRecord] = []) {
        self.records = []
        for r in records { add(r) }
    }

    /// Insert a record, replacing any existing record at the same measure.
    public mutating func add(_ record: SectionRecord) {
        records.removeAll { $0.measure == record.measure }
        let index = records.firstIndex { $0.measure > record.measure } ?? records.count
        records.insert(record, at: index)
    }

    public mutating func remove(atMeasure measure: Int) {
        records.removeAll { $0.measure == measure }
    }

    public var isEmpty: Bool { records.isEmpty }
    public var count: Int { records.count }

    /// The style name in effect at a given measure, falling back to `default`.
    public func styleName(atMeasure measure: Int, default defaultStyle: String) -> String {
        var current = defaultStyle
        for record in records where record.measure <= measure {
            if !record.styleName.isEmpty {
                current = record.styleName
            }
        }
        return current
    }

    /// The record that governs `measure` (the last one starting at or before it).
    public func record(atMeasure measure: Int) -> SectionRecord? {
        records.last { $0.measure <= measure }
    }
}
