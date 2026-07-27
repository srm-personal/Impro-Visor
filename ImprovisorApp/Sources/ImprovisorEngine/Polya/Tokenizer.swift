//
//  Tokenizer.swift
//  ImprovisorEngine
//
//  A Swift port of the lexical layer of `polya.Tokenizer`. The Java version
//  subclasses `java.io.StreamTokenizer` with `resetSyntax()` so it scans one
//  character at a time and builds words itself; this reimplements that behavior
//  directly, which is both clearer and avoids StreamTokenizer's quirks.
//
//  Token rules (matching the Java behavior on the real data files):
//    * Whitespace separates tokens and is otherwise ignored.
//    * `(` `)` `[` `]` `,` `|` are each single-character tokens.
//    * `//` starts a line comment; `/ *` … `* /` is a block comment.
//      A lone `/` that is NOT followed by `/` or `*` is an ordinary word
//      character — this is what lets slash chords like `A/B` tokenize as one
//      word while `// ...` comments in .grammar files are still stripped.
//    * Any other run of characters is a "word", classified as an integer
//      (Java `Long`), else a double (Java `Double`), else a symbol.
//

import Foundation

/// A lexical token produced by `Tokenizer`.
public enum Token: Equatable {
    case open          // (
    case close         // )
    case openBracket   // [
    case closeBracket  // ]
    case comma         // ,
    case pipe          // |
    case long(Int)
    case double(Double)
    case symbol(String)
}

/// Breaks S-expression source text into `Token`s.
public struct Tokenizer {

    private let scalars: [Character]

    public init(_ input: String) {
        self.scalars = Array(input)
    }

    /// Characters that terminate a word and are single-character tokens.
    private static let breakChars: Set<Character> = ["(", ")", "[", "]", ",", "|"]

    private static func isWhitespace(_ c: Character) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0C}"
    }

    /// Produce the full token stream.
    public func tokenize() -> [Token] {
        var tokens: [Token] = []
        var i = 0
        let n = scalars.count

        while i < n {
            let c = scalars[i]

            // Whitespace.
            if Tokenizer.isWhitespace(c) {
                i += 1
                continue
            }

            // Comments (only when `/` is immediately followed by `/` or `*`).
            if c == "/" && i + 1 < n {
                let next = scalars[i + 1]
                if next == "/" {
                    // Line comment: skip to end of line.
                    i += 2
                    while i < n && scalars[i] != "\n" { i += 1 }
                    continue
                }
                if next == "*" {
                    // Block comment: skip to the closing `*/`.
                    i += 2
                    while i + 1 < n && !(scalars[i] == "*" && scalars[i + 1] == "/") {
                        i += 1
                    }
                    i += 2 // consume the closing `*/` (clamped below)
                    if i > n { i = n }
                    continue
                }
            }

            // Single-character tokens.
            if Tokenizer.breakChars.contains(c) {
                switch c {
                case "(": tokens.append(.open)
                case ")": tokens.append(.close)
                case "[": tokens.append(.openBracket)
                case "]": tokens.append(.closeBracket)
                case ",": tokens.append(.comma)
                case "|": tokens.append(.pipe)
                default: break
                }
                i += 1
                continue
            }

            // A word: accumulate until whitespace, a break char, or a
            // comment-starting `/`.
            var word = ""
            while i < n {
                let ch = scalars[i]
                if Tokenizer.isWhitespace(ch) || Tokenizer.breakChars.contains(ch) {
                    break
                }
                if ch == "/" && i + 1 < n && (scalars[i + 1] == "/" || scalars[i + 1] == "*") {
                    break
                }
                word.append(ch)
                i += 1
            }
            tokens.append(Tokenizer.classify(word))
        }

        return tokens
    }

    /// Classify a word as integer, double, or symbol — in the same order the
    /// Java tokenizer tries `Long`, then `Double`, then falls back to a word.
    static func classify(_ word: String) -> Token {
        if let i = Int(word) {
            return .long(i)
        }
        if let d = parseJavaDouble(word) {
            return .double(d)
        }
        return .symbol(word)
    }

    /// Parse a double the way Java's `Double.valueOf` would for the numeric
    /// forms in the data, but *reject* the words Swift's `Double(_:)` would
    /// wrongly accept as numbers (`"inf"`, `"nan"`, and hex like `"0x1p2"`),
    /// since those appear as ordinary symbols (e.g. rule names) here.
    static func parseJavaDouble(_ word: String) -> Double? {
        guard let first = word.first else { return nil }
        // Must start with a digit, sign, or decimal point to be a number.
        if !(first.isNumber || first == "-" || first == "+" || first == ".") {
            return nil
        }
        // Reject hex float notation (`0x...p...`) — not used in the data.
        if word.contains("x") || word.contains("X") { return nil }
        return Double(word)
    }
}
