//
//  PracticeLoopTests.swift
//  LeadsheetStudioUITests
//
//  A thin smoke suite for the core practice loop: open a tune, pick a style,
//  change the tempo, play/stop, loop the form, generate a solo. It checks that
//  the controls exist and respond — musical correctness is covered by the
//  engine and differential tests (`swift test`, ImprovisorApp/Testing).
//
//  macOS only: the project has no iOS target (see Testing/BUG_LOG.md).
//

import XCTest

final class PracticeLoopTests: XCTestCase {

    private var tuneURL: URL!

    /// <repo>/ImprovisorApp/App/LeadsheetStudioUITests/PracticeLoopTests.swift
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Work on a COPY so nothing the test does can be saved over the corpus.
        let source = Self.repoRoot.appendingPathComponent("leadsheets/imaginary-book/12-barBlues.ls")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeadsheetStudioUITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tuneURL = dir.appendingPathComponent("SmokeBlues.ls")
        try FileManager.default.copyItem(at: source, to: tuneURL)
    }

    override func tearDownWithError() throws {
        if let tuneURL { try? FileManager.default.removeItem(at: tuneURL.deletingLastPathComponent()) }
    }

    /// Launch with the tune as a document to open.
    private func launchWithTune() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [tuneURL.path,
                               "-hasSeenOnboarding", "YES",
                               "-showInspector", "YES",
                               "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Poll `condition` until it holds or `seconds` pass.
    private func poll(_ seconds: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    /// Click a control in the inspector. Controls inside the SwiftUI inspector
    /// form can report `isHittable == false` even when visible; fall back to
    /// clicking the centre of the element's frame.
    private func press(_ target: XCUIElement) {
        if target.isHittable {
            target.click()
        } else {
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
    }

    func testOpenTuneShowsItsMusic() throws {
        let app = launchWithTune()
        XCTAssertTrue(app.windows["SmokeBlues.ls"].waitForExistence(timeout: 15)
                      || app.windows.containing(NSPredicate(format: "title CONTAINS 'SmokeBlues'")).firstMatch
                          .waitForExistence(timeout: 5),
                      "the tune did not open in a document window")
        XCTAssertTrue(element(app, "stave").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "chordCell-1").waitForExistence(timeout: 10), "no chords shown for bar 1")
    }

    func testPickStyleChangeTempoPlayStopAndLoop() throws {
        let app = launchWithTune()
        XCTAssertTrue(element(app, "stave").waitForExistence(timeout: 15))

        // Pick a style.
        let style = app.popUpButtons["stylePicker"].firstMatch
        XCTAssertTrue(style.waitForExistence(timeout: 10), "style picker not found (inspector hidden?)")
        press(style)
        let bossa = app.menuItems["bossa"].firstMatch
        XCTAssertTrue(bossa.waitForExistence(timeout: 5))
        press(bossa)
        XCTAssertEqual(style.value as? String, "bossa")

        // Change the tempo.
        let tempo = app.textFields["tempoField"].firstMatch
        XCTAssertTrue(tempo.waitForExistence(timeout: 5))
        tempo.click()
        tempo.typeKey("a", modifierFlags: .command)
        tempo.typeText("132\n")
        XCTAssertEqual(tempo.value as? String, "132")

        // Loop the form, play, confirm it is playing, stop.
        let loop = element(app, "loopForm")
        XCTAssertTrue(loop.waitForExistence(timeout: 5))
        loop.click()

        let play = app.buttons["play"].firstMatch
        let stop = app.buttons["stop"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertFalse(stop.isEnabled, "stop should be disabled before playing")
        play.click()
        XCTAssertTrue(poll(10) { stop.isEnabled }, "playback did not start")
        sleep(1)
        stop.click()
        XCTAssertTrue(poll(10) { !stop.isEnabled }, "playback did not stop")
    }

    func testGenerateSoloFillsTheStave() throws {
        let app = launchWithTune()
        let stave = element(app, "stave")
        XCTAssertTrue(stave.waitForExistence(timeout: 15))
        let before = (stave.value as? String) ?? ""

        let generate = app.buttons["generateSolo"].firstMatch
        XCTAssertTrue(generate.waitForExistence(timeout: 10), "generate button not found (inspector hidden?)")
        press(generate)

        XCTAssertTrue(poll(15) { ((stave.value as? String) ?? "") != before }, "the stave did not change")
        let after = (stave.value as? String) ?? ""
        XCTAssertGreaterThan(after.split(separator: " ").count, 8, "generated solo is suspiciously short: \(after)")
    }
}
