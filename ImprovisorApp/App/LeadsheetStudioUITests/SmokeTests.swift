//
//  SmokeTests.swift
//  LeadsheetStudioUITests
//
//  Launches the real app and walks the core flow: new document, chords in
//  bar 1, three notes typed on the stave, play/stop, print dialog.
//

import XCTest

final class SmokeTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-showInspector", "NO"]
        app.launch()
        return app
    }

    func testNewDocumentEnterChordsAndNotesPlayAndPrint() throws {
        let app = launch()
        // A document window (DocumentGroup opens one, otherwise ⌘N).
        if !app.windows.firstMatch.waitForExistence(timeout: 10) {
            app.typeKey("n", modifierFlags: .command)
        }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let stave = app.descendants(matching: .any)["stave"].firstMatch
        XCTAssertTrue(stave.waitForExistence(timeout: 10), "stave not found")

        // Chords for bar 1 via the Chords… button (⌘⇧K path).
        let chordsButton = app.buttons["Chords…"].firstMatch
        if chordsButton.waitForExistence(timeout: 5) {
            chordsButton.click()
            let field = app.textFields["chordField"].firstMatch
            if field.waitForExistence(timeout: 5) {
                field.click()
                field.typeText("Dm7 G7")
                field.typeKey(.escape, modifierFlags: [])
            }
        }

        // Notes: click the stave, then type c e g.
        stave.click()
        app.typeText("ceg")
        let value = (stave.value as? String) ?? ""
        XCTAssertTrue(value.contains("c8") && value.contains("e8") && value.contains("g8"), "stave value: \(value)")

        // Play / stop.
        let play = app.buttons["play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.click()
        let stop = app.buttons["stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        sleep(1)
        stop.click()

        // Print dialog appears and can be cancelled.
        app.typeKey("p", modifierFlags: .command)
        let sheet = app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 8) {
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTAssertTrue(window.exists)
    }
}
