//
//  AboutView.swift
//  LeadsheetKit
//
//  About window: name, version, credits to Impro-Visor, GPL-2 licence text.
//

import SwiftUI
import ImprovisorEngine

public struct AboutInfo: Equatable, Sendable {
    public var name: String
    public var version: String
    public var build: String
    public var credits: String
    public var licenseText: String
    public var sourceURL: URL
    public var originalURL: URL

    public static func current(library: DataLibrary = .shared) -> AboutInfo {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let license = (bundle.url(forResource: "LICENSE", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) })
            ?? (try? String(contentsOf: library.root.appending(path: "LICENSE.txt"), encoding: .utf8))
            ?? "GNU GENERAL PUBLIC LICENSE, Version 2. See https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
        return AboutInfo(
            name: "Leadsheet Studio",
            version: version,
            build: build,
            credits: """
            Leadsheet Studio is a native macOS port of Impro-Visor (Improvisation Advisor), \
            created by Robert Keller and Harvey Mudd College. The accompaniment styles, grammars, \
            chord vocabulary and leadsheet library ship unchanged from Impro-Visor and remain the \
            work of their contributors.

            Leadsheet Studio is free software under the GNU General Public License version 2 or later. \
            The complete source code is available at the address below.
            """,
            licenseText: license,
            sourceURL: URL(string: "https://github.com/srm-personal/Impro-Visor/tree/swift-port")!,
            originalURL: URL(string: "https://www.cs.hmc.edu/~keller/jazz/improvisor/")!)
    }
}

public struct AboutView: View {
    let info = AboutInfo.current()
    @State private var showLicense = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(info.name).font(.title.bold())
            Text("Version \(info.version) (\(info.build))").foregroundStyle(.secondary)
            Text(info.credits).font(.callout).multilineTextAlignment(.center).frame(maxWidth: 440)
            HStack(spacing: 16) {
                Link("Source code", destination: info.sourceURL)
                Link("Impro-Visor", destination: info.originalURL)
                Button(showLicense ? "Hide License" : "View License") { showLicense.toggle() }
            }
            if showLicense {
                ScrollView {
                    Text(info.licenseText).font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(height: 220)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
