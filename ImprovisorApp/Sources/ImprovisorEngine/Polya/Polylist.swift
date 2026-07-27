//
//  Polylist.swift
//  ImprovisorEngine
//
//  A Swift port of `polya.Polylist` — a Lisp-style singly-linked (cons) list.
//  The style and lickgen engines lean heavily on `first()`, `rest()`,
//  `length()`, `nth()`, `assoc()`, etc., so this deliberately keeps the Java
//  method shape to make those ports mechanical. Elements are `PolyValue`s.
//
//  Cons lists share tails, so `rest()` is O(1) and non-copying. The list is
//  treated as immutable here (the Java `setFirst`/`setNth` mutators are rarely
//  used by the engine code we port and are intentionally omitted in favor of
//  building fresh lists).
//

import Foundation

/// An immutable Lisp-style list of `PolyValue`s. The empty list is
/// `Polylist.empty` (the analogue of Java's `Polylist.nil`).
public final class Polylist: Equatable, Hashable, CustomStringConvertible, Sequence, @unchecked Sendable {
    // `@unchecked Sendable` is sound because a Polylist is fully immutable:
    // every stored property is a `let`, and cons cells are never mutated after
    // construction.

    /// A cons cell: a head element and the tail list.
    private final class Cell {
        let first: PolyValue
        let rest: Polylist
        init(_ first: PolyValue, _ rest: Polylist) {
            self.first = first
            self.rest = rest
        }
    }

    private let cell: Cell?

    private init(cell: Cell?) {
        self.cell = cell
    }

    /// The empty list, `()`.
    public static let empty = Polylist(cell: nil)

    /// Construct a non-empty list from a head and tail (the `cons` operation).
    public convenience init(_ first: PolyValue, _ rest: Polylist) {
        self.init(cell: Cell(first, rest))
    }

    // MARK: Predicates

    /// True when the list has no elements.
    public var isEmpty: Bool { cell == nil }

    /// True when the list has at least one element.
    public var nonEmpty: Bool { cell != nil }

    // MARK: Access

    /// The first element. Traps on the empty list (matches the Java
    /// `NullPointerException` contract — callers guard with `nonEmpty`).
    public func first() -> PolyValue {
        guard let cell else { preconditionFailure("first() of empty Polylist") }
        return cell.first
    }

    /// The first element, or `nil` if the list is empty (safe variant).
    public func firstOrNil() -> PolyValue? { cell?.first }

    /// The tail of the list (everything after the first element). The tail of
    /// the empty list is the empty list, matching the Java behavior used by
    /// several traversal loops.
    public func rest() -> Polylist { cell?.rest ?? .empty }

    public func second() -> PolyValue { rest().first() }
    public func third() -> PolyValue { rest().rest().first() }
    public func fourth() -> PolyValue { rest().rest().rest().first() }
    public func fifth() -> PolyValue { rest().rest().rest().rest().first() }
    public func sixth() -> PolyValue { rest().rest().rest().rest().rest().first() }

    /// The n-th element (0-based).
    public func nth(_ n: Int) -> PolyValue {
        var list = self
        var i = n
        while i > 0 {
            list = list.rest()
            i -= 1
        }
        return list.first()
    }

    /// The last element. Traps on the empty list.
    public func last() -> PolyValue {
        guard var cell else { preconditionFailure("last() of empty Polylist") }
        while let next = cell.rest.cell {
            cell = next
        }
        return cell.first
    }

    // MARK: Construction

    /// Prepend an element, returning a new list (the cons operation).
    public func cons(_ first: PolyValue) -> Polylist {
        Polylist(first, self)
    }

    /// Build a list from a Swift array of values.
    public static func of(_ values: [PolyValue]) -> Polylist {
        var result = Polylist.empty
        for value in values.reversed() {
            result = result.cons(value)
        }
        return result
    }

    /// Variadic convenience constructor mirroring Java's `Polylist.list(...)`.
    public static func list(_ values: PolyValue...) -> Polylist {
        of(values)
    }

    // MARK: Length & conversion

    /// The number of elements.
    public var length: Int {
        var n = 0
        var cell = self.cell
        while let c = cell {
            n += 1
            cell = c.rest.cell
        }
        return n
    }

    /// The elements as a Swift array (head-first order).
    public func toArray() -> [PolyValue] {
        var result: [PolyValue] = []
        var cell = self.cell
        while let c = cell {
            result.append(c.first)
            cell = c.rest.cell
        }
        return result
    }

    // MARK: Higher-order & search

    /// The list reversed.
    public func reverse() -> Polylist {
        var result = Polylist.empty
        var cell = self.cell
        while let c = cell {
            result = result.cons(c.first)
            cell = c.rest.cell
        }
        return result
    }

    /// This list followed by `other`.
    public func append(_ other: Polylist) -> Polylist {
        var result = other
        for value in toArray().reversed() {
            result = result.cons(value)
        }
        return result
    }

    /// True if `value` is an element of the list (by `PolyValue` equality).
    public func member(_ value: PolyValue) -> Bool {
        var cell = self.cell
        while let c = cell {
            if c.first == value { return true }
            cell = c.rest.cell
        }
        return false
    }

    /// Association-list lookup: find the first sub-list whose own first element
    /// equals `key`, returning that sub-list (or `nil`). Mirrors
    /// `polya.Polylist.assoc`. Used pervasively to read `(keyword value ...)`
    /// entries out of style/grammar/leadsheet S-expressions.
    public func assoc(_ key: PolyValue) -> Polylist? {
        var cell = self.cell
        while let c = cell {
            if case let .list(sub) = c.first, sub.nonEmpty, sub.first() == key {
                return sub
            }
            cell = c.rest.cell
        }
        return nil
    }

    /// Convenience: `assoc` keyed by a symbol name.
    public func assoc(_ key: String) -> Polylist? {
        assoc(.symbol(key))
    }

    // MARK: Equatable

    public static func == (lhs: Polylist, rhs: Polylist) -> Bool {
        var a = lhs.cell
        var b = rhs.cell
        while let ca = a, let cb = b {
            if ca.first != cb.first { return false }
            a = ca.rest.cell
            b = cb.rest.cell
        }
        return a == nil && b == nil
    }

    public func hash(into hasher: inout Hasher) {
        var cell = self.cell
        while let c = cell {
            hasher.combine(c.first)
            cell = c.rest.cell
        }
    }

    // MARK: Sequence

    public func makeIterator() -> AnyIterator<PolyValue> {
        var cell = self.cell
        return AnyIterator {
            guard let c = cell else { return nil }
            cell = c.rest.cell
            return c.first
        }
    }

    // MARK: CustomStringConvertible

    public var description: String {
        "(" + toArray().map(\.description).joined(separator: " ") + ")"
    }
}
