//
//  UTType+Leadsheet.swift
//  LeadsheetKit
//

import UniformTypeIdentifiers

public extension UTType {
    /// Impro-Visor leadsheet (`.ls`), exported by Leadsheet Studio. The app's
    /// Info.plist declares the same identifier with the `ls` extension.
    static let leadsheet = UTType(exportedAs: "com.srmorin.leadsheetstudio.leadsheet",
                                  conformingTo: .plainText)
}
