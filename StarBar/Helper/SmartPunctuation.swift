//
//  SmartPunctuation.swift
//  StarBar
//
//  Typewriter punctuation into typographic punctuation, for text on screen.
//

import Foundation

extension String {

    /// The same text with typewriter marks replaced by typographic ones: curly quotes, a real
    /// apostrophe and a single ellipsis character.
    ///
    /// Music's metadata is full of straight marks -- "Calling My Name (Live New Orleans '89)",
    /// "Silium's Hill" -- and they look like what they are, a typewriter compromise.
    ///
    /// For display only. It must not touch anything compared or stored: a track's identity can
    /// be `name|artist|album`, and prettifying one side of that comparison would stop it
    /// matching itself.
    var typographicPunctuation: String {
        var result = ""
        result.reserveCapacity(count)

        var previous: Character?
        var index = startIndex

        while index < endIndex {
            let character = self[index]

            switch character {
            case "'":
                // Always the apostrophe. In song titles a single quote is nearly always an
                // apostrophe ("Silium's") or an elision ("'89"), and both are this character;
                // a genuinely quoted phrase is rare enough not to be worth guessing at.
                result.append("\u{2019}")

            case "\"":
                // Opening when it starts the text or follows a space or an opening bracket
                let opens = previous.map { $0.isWhitespace || "([{".contains($0) } ?? true
                result.append(opens ? "\u{201C}" : "\u{201D}")

            case ".":
                // Three in a row become one ellipsis character, which sets better and cannot
                // be split across a truncation
                let afterTwoMore = self.index(index, offsetBy: 3, limitedBy: endIndex)
                if let end = afterTwoMore, self[index..<end] == "..." {
                    result.append("\u{2026}")
                    previous = "\u{2026}"
                    index = end
                    continue
                }
                result.append(character)

            default:
                result.append(character)
            }

            previous = character
            index = self.index(after: index)
        }

        return result
    }

}
