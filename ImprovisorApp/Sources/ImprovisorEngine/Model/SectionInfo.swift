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
public struct SectionRecord: Equatable {
    /// Zero-based measure index at which this section begins.
    public var measure: Int
    /// Style name for this section (empty means "inherit the score's style").
    public var styleName: String
    /// Whether this section starts a new phrase (`isPhrase` in Java).
    public var isPhrase: Bool

    public init(measure: Int, styleName: String = "", isPhrase: Bool = true) {
        self.measure = measure
        self.styleName = styleName
        self.isPhrase = isPhrase
    }
}

/// The ordered list of sections.
public struct SectionInfo: Equatable {
    public var records: [SectionRecord]

    public init(records: [SectionRecord] = []) {
        self.records = records
    }

    public mutating func add(_ record: SectionRecord) {
        records.append(record)
    }

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
}
