//
//  PolyaTests.swift
//  ImprovisorEngineTests
//
//  Step 1 coverage: tokenizer, Polylist operations, and the S-expression
//  reader, validated against real Impro-Visor data files.
//

import XCTest
@testable import ImprovisorEngine

final class PolyaTests: XCTestCase {

    // MARK: Tokenizer

    func testTokenizeSimpleList() {
        let tokens = Tokenizer("(title So What)").tokenize()
        XCTAssertEqual(tokens, [
            .open, .symbol("title"), .symbol("So"), .symbol("What"), .close
        ])
    }

    func testTokenizeNumbers() {
        // Integers classify as .long, decimals as .double.
        XCTAssertEqual(Tokenizer("4").tokenize(), [.long(4)])
        XCTAssertEqual(Tokenizer("140.0").tokenize(), [.double(140.0)])
        XCTAssertEqual(Tokenizer("-960").tokenize(), [.long(-960)])
        XCTAssertEqual(Tokenizer("0.67").tokenize(), [.double(0.67)])
    }

    func testSlashChordIsOneWord() {
        // A single '/' inside a word (slash chord) must not start a comment.
        let tokens = Tokenizer("A/Bb C/E").tokenize()
        XCTAssertEqual(tokens, [.symbol("A/Bb"), .symbol("C/E")])
    }

    func testLoneSlashIsSymbol() {
        // In leadsheets a bare '/' means "repeat previous chord".
        XCTAssertEqual(Tokenizer("Dm7 | / |").tokenize(),
                       [.symbol("Dm7"), .pipe, .symbol("/"), .pipe])
    }

    func testLineComment() {
        let tokens = Tokenizer("foo // this is ignored\nbar").tokenize()
        XCTAssertEqual(tokens, [.symbol("foo"), .symbol("bar")])
    }

    func testBlockComment() {
        let tokens = Tokenizer("foo /* ignored\nmulti-line */ bar").tokenize()
        XCTAssertEqual(tokens, [.symbol("foo"), .symbol("bar")])
    }

    func testSymbolsWithSpecialChars() {
        // Bass register tokens etc. use trailing dashes; V90 is a velocity rule.
        XCTAssertEqual(Tokenizer("g-- V90 A4").tokenize(),
                       [.symbol("g--"), .symbol("V90"), .symbol("A4")])
    }

    // MARK: Parser

    func testParseSimpleList() {
        guard case let .list(list)? = PolyaParser.parse("(title So What)") else {
            return XCTFail("expected a list")
        }
        XCTAssertEqual(list.toArray(),
                       [.symbol("title"), .symbol("So"), .symbol("What")])
    }

    func testParseMeter() {
        guard case let .list(list)? = PolyaParser.parse("(meter 4 4)") else {
            return XCTFail("expected a list")
        }
        XCTAssertEqual(list.toArray(), [.symbol("meter"), .long(4), .long(4)])
    }

    func testParseNestedStyleFragment() {
        let input = "(bass-pattern (rules B4 S4 C4 V90 A4)(weight 10.0))"
        guard case let .list(list)? = PolyaParser.parse(input) else {
            return XCTFail("expected a list")
        }
        XCTAssertEqual(list.first(), .symbol("bass-pattern"))

        guard case let .list(rules) = list.second() else {
            return XCTFail("expected nested rules list")
        }
        XCTAssertEqual(rules.toArray(), [
            .symbol("rules"), .symbol("B4"), .symbol("S4"),
            .symbol("C4"), .symbol("V90"), .symbol("A4")
        ])

        guard case let .list(weight) = list.third() else {
            return XCTFail("expected nested weight list")
        }
        XCTAssertEqual(weight.toArray(), [.symbol("weight"), .double(10.0)])
    }

    // MARK: Polylist operations

    func testPolylistBasics() {
        let list = Polylist.of([.symbol("a"), .long(2), .symbol("c")])
        XCTAssertEqual(list.length, 3)
        XCTAssertEqual(list.first(), .symbol("a"))
        XCTAssertEqual(list.second(), .long(2))
        XCTAssertEqual(list.nth(2), .symbol("c"))
        XCTAssertEqual(list.last(), .symbol("c"))
        XCTAssertEqual(list.rest().toArray(), [.long(2), .symbol("c")])
        XCTAssertEqual(list.reverse().first(), .symbol("c"))
        XCTAssertTrue(list.member(.long(2)))
        XCTAssertFalse(list.member(.long(9)))
    }

    func testAssoc() {
        // (a-list) of (keyword value) sublists, like style/leadsheet metadata.
        let alist = PolyaParser.parse("((title So What)(tempo 160.0)(key 0))")!
        guard case let .list(list) = alist else { return XCTFail() }
        XCTAssertEqual(list.assoc("tempo")?.second(), .double(160.0))
        XCTAssertEqual(list.assoc("key")?.second(), .long(0))
        XCTAssertNil(list.assoc("missing"))
    }

    // MARK: Real data files

    func testParseSoWhatLeadsheet() throws {
        let content = try TestData.contents("leadsheets/imaginary-book/SoWhat.ls")
        let forms = PolyaParser.parseAll(content)
        XCTAssertGreaterThan(forms.count, 0)

        // First form is (title So What?)
        guard case let .list(titleForm) = forms[0] else {
            return XCTFail("expected first form to be the title list")
        }
        XCTAssertEqual(titleForm.first(), .symbol("title"))

        // The bare chord tokens appear at the top level as symbols.
        XCTAssertTrue(forms.contains(.symbol("Dm7")))
        XCTAssertTrue(forms.contains(.symbol("Ebm7")))
        XCTAssertTrue(forms.contains(.symbol("|")))
    }

    func testParseAllLeadsheetsDoNotCrash() throws {
        let files = TestData.files(under: "leadsheets", ext: "ls")
        XCTAssertGreaterThan(files.count, 1000,
                             "expected the full leadsheet corpus to be present")
        var parsed = 0
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            let forms = PolyaParser.parseAll(content)
            XCTAssertGreaterThan(forms.count, 0, "empty parse: \(file.lastPathComponent)")
            parsed += 1
        }
        XCTAssertGreaterThan(parsed, 1000)
    }

    func testParseAllStylesDoNotCrash() throws {
        let files = TestData.files(under: "styles", ext: "sty")
        XCTAssertGreaterThan(files.count, 100)
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                continue
            }
            XCTAssertGreaterThan(PolyaParser.parseAll(content).count, 0,
                                 "empty parse: \(file.lastPathComponent)")
        }
    }
}
