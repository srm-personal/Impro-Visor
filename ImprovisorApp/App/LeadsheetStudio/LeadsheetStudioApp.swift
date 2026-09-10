//
//  LeadsheetStudioApp.swift
//  Leadsheet Studio
//
//  A native macOS leadsheet editor and play-along engine, ported from
//  Impro-Visor (Robert Keller, Harvey Mudd College). GPL-2.0-or-later.
//

import SwiftUI
import LeadsheetKit

@main
struct LeadsheetStudioApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { LeadsheetDocument() }) { configuration in
            DocumentView(document: configuration.document)
        }
        .commands {
            SidebarCommands()
        }
    }
}
