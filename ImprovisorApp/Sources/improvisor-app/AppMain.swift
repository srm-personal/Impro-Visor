//
//  AppMain.swift
//  improvisor-app
//
//  A native macOS SwiftUI front end for the Impro-Visor engine (Step 8). Built as
//  a SwiftPM executable so it runs with `swift run improvisor-app`; a real
//  bundled/signed .app target is the follow-on step.
//

import SwiftUI

@main
struct ImprovisorApp: App {
    @StateObject private var model: AppModel

    init() {
        let root = DataLibrary.locate()
        let library = DataLibrary(root: root ?? URL(filePath: FileManager.default.currentDirectoryPath))
        _model = StateObject(wrappedValue: AppModel(library: library))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentMinSize)
    }
}
