//
//  PolyaParser.swift
//  ImprovisorEngine
//
//  Top-level S-expression reader, mirroring `polya.Tokenizer.nextSexp` /
//  `getRestSexp`. Turns a token stream into `PolyValue`s. Leadsheet files mix
//  parenthesized metadata lists with bare chord tokens and `|` bar separators
//  at the top level, so both `parse` (first form) and `parseAll` (every
//  top-level form) are provided.
//

import Foundation

/// Parses S-expression text into `PolyValue` trees.
public enum PolyaParser {

    /// Parse the first top-level S-expression from `input`, or `nil` if empty.
    public static func parse(_ input: String) -> PolyValue? {
        var reader = Reader(Tokenizer(input).tokenize())
        return reader.nextSexp()
    }

    /// Parse every top-level S-expression / atom from `input`, in order.
    /// This is the entry point used to read whole leadsheet files, where the
    /// chord progression appears as a flat run of bare chord symbols and `|`.
    public static func parseAll(_ input: String) -> [PolyValue] {
        var reader = Reader(Tokenizer(input).tokenize())
        var result: [PolyValue] = []
        while let value = reader.nextSexp() {
            result.append(value)
        }
        return result
    }

    /// A cursor over the token stream that builds `PolyValue`s recursively.
    private struct Reader {
        private let tokens: [Token]
        private var pos = 0

        init(_ tokens: [Token]) {
            self.tokens = tokens
        }

        private mutating func next() -> Token? {
            guard pos < tokens.count else { return nil }
            defer { pos += 1 }
            return tokens[pos]
        }

        /// Read one top-level S-expression. Mirrors `nextSexp()`.
        mutating func nextSexp() -> PolyValue? {
            guard let token = next() else { return nil }
            switch token {
            case .open:
                return .list(readRest())
            case .close:
                // Stray ')' — treat as the empty list, as the Java reader does.
                return .list(.empty)
            case .comma:
                return .symbol(",")
            case .pipe:
                return .symbol("|")
            case .openBracket:
                return .symbol("[")
            case .closeBracket:
                return .symbol("]")
            case let .long(v):
                return .long(v)
            case let .double(v):
                return .double(v)
            case let .symbol(s):
                return .symbol(s)
            }
        }

        /// Read the remainder of a list after an opening `(`. Mirrors
        /// `getRestSexp()`. Built iteratively (then reversed) to avoid deep
        /// recursion on long lists.
        mutating func readRest() -> Polylist {
            var elements: [PolyValue] = []
            loop: while let token = next() {
                switch token {
                case .close:
                    break loop
                case .open:
                    elements.append(.list(readRest()))
                case .pipe:
                    elements.append(.symbol("|"))
                case .comma:
                    elements.append(.symbol(","))
                case .openBracket:
                    elements.append(.symbol("["))
                case .closeBracket:
                    elements.append(.symbol("]"))
                case let .long(v):
                    elements.append(.long(v))
                case let .double(v):
                    elements.append(.double(v))
                case let .symbol(s):
                    elements.append(.symbol(s))
                }
            }
            return Polylist.of(elements)
        }
    }
}
