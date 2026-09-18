//
//  SVGPath.swift
//  StarBar
//
//  Turning an SVG path's "d" attribute into an NSBezierPath. Pure: see `SVGPathTests`.
//

import Cocoa

/// Reads the subset of SVG path syntax the artwork in this app uses: moves, lines, cubic
/// curves and close, in both absolute and relative form, plus the horizontal and vertical
/// line shorthands and the smooth-curve shorthand.
///
/// Arcs (`A`/`a`) and quadratic curves (`Q`/`T`) are not supported: the parse **stops** at one
/// rather than skipping it, because skipping would draw a shape that is quietly wrong. Nothing
/// here needs them. The result is in SVG coordinates, where y grows downwards -- flip it
/// before drawing, as `MusicNoteGlyph` does.
enum SVGPath {

    /// Parse a path's `d` attribute. Unknown commands end the parse rather than guessing.
    static func path(fromPathData data: String) -> NSBezierPath {
        let path = NSBezierPath()
        var scanner = Scanner(data)

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// Reflected for the smooth-curve shorthand
        var lastControl: CGPoint?
        var command: Character?

        while true {
            scanner.skipSeparators()
            var readACommand = false
            if let next = scanner.peekCommand() {
                command = next
                scanner.advance()
                readACommand = true
            } else if command == nil || scanner.isAtEnd {
                break
            }
            // Otherwise the previous command repeats with fresh numbers, which SVG allows

            guard let verb = command else { break }

            // Close takes no numbers, so repeating it implicitly would consume nothing and
            // spin here forever, appending a close element each time. Only honour it when the
            // letter was actually read this time round.
            if (verb == "Z" || verb == "z") && !readACommand { return path }
            let isRelative = verb.isLowercase

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                return isRelative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }

            switch verb {
            case "M", "m":
                guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                current = point(x, y)
                subpathStart = current
                path.move(to: current)
                lastControl = nil
                // A second pair after a moveto is a lineto, per the spec
                command = isRelative ? "l" : "L"

            case "L", "l":
                guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                current = point(x, y)
                path.line(to: current)
                lastControl = nil

            case "H", "h":
                guard let x = scanner.nextNumber() else { return path }
                current = CGPoint(x: isRelative ? current.x + x : x, y: current.y)
                path.line(to: current)
                lastControl = nil

            case "V", "v":
                guard let y = scanner.nextNumber() else { return path }
                current = CGPoint(x: current.x, y: isRelative ? current.y + y : y)
                path.line(to: current)
                lastControl = nil

            case "C", "c":
                guard let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                      let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                let control1 = point(x1, y1)
                let control2 = point(x2, y2)
                current = point(x, y)
                path.curve(to: current, controlPoint1: control1, controlPoint2: control2)
                lastControl = control2

            case "S", "s":
                guard let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                      let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                // The first control point mirrors the previous one about the current point
                let mirrored = lastControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let control2 = point(x2, y2)
                current = point(x, y)
                path.curve(to: current, controlPoint1: mirrored, controlPoint2: control2)
                lastControl = control2

            case "Z", "z":
                path.close()
                current = subpathStart
                lastControl = nil

            default:
                // An unsupported command: stop rather than draw something wrong
                return path
            }

            if scanner.isAtEnd { break }
        }

        return path
    }

    /// Walks the `d` string, handing back commands and numbers
    private struct Scanner {

        private let characters: [Character]
        private var index = 0

        init(_ data: String) {
            characters = Array(data)
        }

        var isAtEnd: Bool {
            return index >= characters.count
        }

        mutating func advance() {
            index += 1
        }

        /// Commas and whitespace separate values and carry no meaning
        mutating func skipSeparators() {
            while index < characters.count, characters[index] == "," || characters[index].isWhitespace {
                index += 1
            }
        }

        func peekCommand() -> Character? {
            guard index < characters.count else { return nil }
            let character = characters[index]
            return character.isLetter ? character : nil
        }

        /// A number, which may be signed and may have one decimal point.
        ///
        /// SVG allows a sign or a second point to start the next number with no separator at
        /// all, as in "1.5.5" or "1-2", so the scan has to stop on both.
        mutating func nextNumber() -> CGFloat? {
            skipSeparators()
            var digits = ""
            var hasPoint = false

            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                digits.append(characters[index])
                index += 1
            }
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    digits.append(character)
                } else if character == "." && !hasPoint {
                    hasPoint = true
                    digits.append(character)
                } else {
                    break
                }
                index += 1
            }

            // Exponent notation, which many SVG exporters emit. Without this "1e-5" would
            // scan as 1, and the "e" would then be read as an unknown command and end the
            // parse -- most of a path lost with nothing said about it.
            if !digits.isEmpty, index < characters.count,
               characters[index] == "e" || characters[index] == "E" {
                var lookahead = index + 1
                var exponent = String(characters[index])
                if lookahead < characters.count,
                   characters[lookahead] == "-" || characters[lookahead] == "+" {
                    exponent.append(characters[lookahead])
                    lookahead += 1
                }
                var exponentDigits = ""
                while lookahead < characters.count, characters[lookahead].isNumber {
                    exponentDigits.append(characters[lookahead])
                    lookahead += 1
                }
                // Only take it when there are digits after the e, so a stray letter is still
                // treated as a command
                if !exponentDigits.isEmpty {
                    digits += exponent + exponentDigits
                    index = lookahead
                }
            }

            return Double(digits).map { CGFloat($0) }
        }

    }

}
