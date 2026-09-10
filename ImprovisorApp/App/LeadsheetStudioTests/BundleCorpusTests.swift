//
//  BundleCorpusTests.swift
//  LeadsheetStudioTests
//
//  Runs inside the built app: the corpus must be found in the bundle, and the
//  document type must be registered.
//

import XCTest
import UniformTypeIdentifiers
import LeadsheetKit
import ImprovisorEngine

final class BundleCorpusTests: XCTestCase {

    func testCorpusIsBundled() {
        let resources = Bundle.main.resourceURL!
        XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appending(path: "vocab/My.voc").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appending(path: "styles/swing.sty").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appending(path: "leadsheets/imaginary-book/SoWhat.ls").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resources.appending(path: "LICENSE.txt").path))
    }

    func testSharedLibraryUsesTheBundle() {
        XCTAssertEqual(DataLibrary.shared.root.standardizedFileURL, Bundle.main.resourceURL!.standardizedFileURL)
        XCTAssertGreaterThan(DataLibrary.shared.styleNames.count, 100)
        XCTAssertGreaterThan(DataLibrary.shared.vocabulary.formCount, 100)
        let soWhat = DataLibrary.shared.score(atLeadsheet: DataLibrary.shared.url("leadsheets/imaginary-book/SoWhat.ls"))
        XCTAssertEqual(soWhat?.measureCount, 32)
    }

    func testLeadsheetTypeIsDeclared() {
        XCTAssertEqual(UTType.leadsheet.preferredFilenameExtension, "ls")
        XCTAssertTrue(UTType.leadsheet.conforms(to: .plainText))
        let types = Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]]
        XCTAssertEqual(types?.first?["CFBundleTypeRole"] as? String, "Editor")
    }
}
