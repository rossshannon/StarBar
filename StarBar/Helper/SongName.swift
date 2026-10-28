//
//  SongName.swift
//  StarBar
//
//  Song titles, artists and albums folded so that two players' names for the same song
//  compare equal. Pure rules, no Apple Events: see `SongNameTests`.
//

import Foundation

/// Folding the names Spotify and Music give a song down to what they agree on.
///
/// Spotify writes "Bohemian Rhapsody - Remastered 2011" where a library has "Bohemian
/// Rhapsody", "Florence + The Machine" where it has "Florence and the Machine", and
/// "Don\u{2019}t" where it has "Don't". Each rule here is fixed and small, so a match can be
/// explained in one line of the log, and anything the rules don't recognise is left in
/// place: an unfamiliar word costs a match, never makes a wrong one.
///
/// Measured on 2026-10-28 against an 8,092-track library: 397 titles there are shared by
/// different artists, and 75 songs are held both as the studio recording and as a live, remix
/// or acoustic one. So the artist always has to agree, and the words that mark a different
/// recording are kept rather than folded away.
enum SongName {

    /// A title with its edition words taken off
    struct Title: Equatable {
        /// The song's own name, folded: "bohemian rhapsody"
        let core: String
        /// What makes this recording a different one from the plain song: "live", "remix",
        /// or a whole named version the rules don't know, such as "variant:salsa version".
        /// Empty for the plain song. Two titles only match when these are equal.
        let versions: Set<String>
        /// Artists credited in the title, as in "(feat. Aloe Blacc)", folded like `artist(_:)`
        let featured: [String]
    }

    /// What a bracketed or dashed part of a title says about the recording
    enum Descriptor: Equatable {
        /// An edition of the same recording, or a trivial edit of it: "Remastered 2011",
        /// "Radio Edit", "Single Version", "From \u{201C}8 Mile\u{201D}". Dropped.
        case edition
        /// A different performance or arrangement: kept, so only the same kind matches
        case version(Set<String>)
    }

    // MARK: - Text

    /// Case, accents, letters such as ø and ß, and typographic quotes and dashes folded away.
    /// Punctuation stays, because the title rules below read brackets and " - ".
    static func fold(_ text: String) -> String {
        var result = ""
        for scalar in text.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if let replacement = foldedScalars[scalar] {
                result += replacement
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Letters and digits only, one space between words. "&" and "+" read as "and", and an
    /// apostrophe joins its word rather than splitting it, so "Don't" is "dont", not "don t".
    static func squash(_ text: String) -> String {
        var words: [String] = []
        var word = ""
        func endWord() {
            if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        for scalar in text.unicodeScalars {
            if scalar == "&" || scalar == "+" {
                endWord()
                words.append("and")
            } else if scalar == "'" {
                continue
            } else if CharacterSet.alphanumerics.contains(scalar) {
                word.unicodeScalars.append(scalar)
            } else {
                endWord()
            }
        }
        endWord()
        return words.joined(separator: " ")
    }

    // MARK: - Titles

    /// The song's name with edition words and featured artists taken off, and what is left
    /// that marks a different recording.
    static func title(_ raw: String) -> Title {
        var text = fold(raw)
        var featured: [String] = []
        var versions = Set<String>()

        // "(feat. Aloe Blacc)", "[with Rihanna]"
        for match in featuredInBrackets.matches(in: text, range: whole(text)).reversed() {
            featured += artistNames(in: substring(text, match.range(at: 2)))
            text = removing(match.range, from: text)
        }

        // Spotify's " - Remastered 2011", " - Live at Wembley", " - feat. X"
        if let match = dashSuffix.firstMatch(in: text, range: whole(text)) {
            let suffix = substring(text, match.range(at: 1))
            if let credit = featuredCredit.firstMatch(in: suffix, range: whole(suffix)) {
                featured += artistNames(in: substring(suffix, credit.range(at: 2)))
                text = removing(match.range, from: text)
            } else if let descriptor = describe(suffix) {
                if case .version(let kinds) = descriptor {
                    versions.formUnion(kinds)
                }
                text = removing(match.range, from: text)
            }
        }

        // "(Remastered)", "[Radio Edit]", "(Live)", but not "(Fade Out)" or "(Don't Fear) The
        // Reaper", which are part of the song's name
        for match in bracketed.matches(in: text, range: whole(text)).reversed() {
            guard let descriptor = describe(substring(text, match.range(at: 1))) else { continue }
            if case .version(let kinds) = descriptor {
                versions.formUnion(kinds)
            }
            text = removing(match.range, from: text)
        }

        // "Song feat. X", with no brackets
        if let match = featuredBare.firstMatch(in: text, range: whole(text)) {
            featured += artistNames(in: substring(text, match.range(at: 2)))
            text = removing(match.range, from: text)
        }

        let core = squash(text)
            .split(separator: " ")
            .map { $0 == "pt" ? "part" : String($0) }
            .joined(separator: " ")
        return Title(core: core, versions: versions, featured: featured)
    }

    /// What a part of a title in brackets or after " - " says, or nil when it is part of the
    /// song's name.
    ///
    /// Words that mark a different recording win: "Live at Wembley" is a version, not an
    /// edition, whatever else it says. Then a part made only of edition words ("2011
    /// Remaster", "Single Version", "Radio Edit") is an edition. A part that ends in
    /// "Version", "Mix" or "Edit" but has other words in it ("Salsa Version", "Matt Butcher
    /// Mix") is a version the rules don't know, kept whole so it only matches itself.
    static func describe(_ part: String) -> Descriptor? {
        let folded = fold(part)
        let kinds = Set(versionKinds
            .filter { $0.words.firstMatch(in: folded, range: whole(folded)) != nil }
            .map { $0.kind })
        if !kinds.isEmpty {
            return .version(kinds)
        }
        let words = squash(folded).split(separator: " ").map(String.init)
        guard let first = words.first, let last = words.last else { return nil }
        if first == "from" || words.allSatisfy(isEditionWord) {
            return .edition
        }
        if namedVersionEndings.contains(last) {
            return .version(["variant:" + words.joined(separator: " ")])
        }
        return nil
    }

    // MARK: - Artists and albums

    /// One artist's name, folded, without a leading "The": "The Cranberries" and
    /// "Cranberries" are the same band.
    static func artist(_ raw: String) -> String {
        let name = squash(fold(raw))
        return name.hasPrefix("the ") ? String(name.dropFirst(4)) : name
    }

    /// Every artist a credit names, and the whole credit too: "Simon & Garfunkel" gives
    /// "simon", "garfunkel" and "simon and garfunkel", and "Cave, Nick & Warren Ellis" gives
    /// "warren ellis" among others.
    ///
    /// Only for the library's side. Spotify's artist is one name, compared whole, so that
    /// "Earth" can't match "Earth, Wind & Fire".
    static func artists(_ raw: String) -> Set<String> {
        var names = Set(artistNames(in: raw))
        let credit = artist(raw)
        if !credit.isEmpty {
            names.insert(credit)
        }
        return names
    }

    /// An album's name without its edition words: "A Night At The Opera (2011 Remaster)" is
    /// "a night at the opera". Only for choosing between copies, never for deciding whether
    /// two tracks are the same song.
    ///
    /// Music's " - Single" and " - EP" stay: the single is a different release from the album
    /// it came from, and the copy on the album Spotify names should win over it.
    static func album(_ raw: String) -> String {
        var text = fold(raw)
        for match in bracketed.matches(in: text, range: whole(text)).reversed()
        where describe(substring(text, match.range(at: 1))) != nil {
            text = removing(match.range, from: text)
        }
        if let match = dashSuffix.firstMatch(in: text, range: whole(text)) {
            let suffix = substring(text, match.range(at: 1))
            if !releaseKinds.contains(squash(suffix)), describe(suffix) != nil {
                text = removing(match.range, from: text)
            }
        }
        return squash(text)
    }

    // MARK: - Rules

    /// Words that mark a different recording, with what they are filed as
    private static let versionKinds: [(kind: String, words: NSRegularExpression)] = [
        ("live", pattern(#"\blive\b|\bin concert\b|\bunplugged\b"#)),
        ("remix", pattern(#"\bremix\b|\brmx\b|\bdub\b|\brework\b|\bre-?edit\b|\bvip\b"#)),
        ("acoustic", pattern(#"\bacoustic\b"#)),
        ("demo", pattern(#"\bdemo\b"#)),
        ("instrumental", pattern(#"\binstrumental\b"#)),
        ("karaoke", pattern(#"\bkaraoke\b"#)),
        ("a cappella", pattern(#"\ba ?cappella\b|\bacapella\b"#)),
        ("orchestral", pattern(#"\borchestral\b|\bsymphonic\b"#)),
        ("reprise", pattern(#"\breprise\b"#)),
        ("session", pattern(#"\bsessions?\b|\brehearsal\b|\bouttake\b|\balternate\b|\balt\.? take\b|\btake \d+\b"#)),
    ]

    /// Words that only ever describe an edition of a recording, or a trivial edit of it.
    /// "Mix" is here so that "2009 Mix" and "Stereo Mix" are editions; a named mix such as
    /// "Matt Butcher Mix" still has a word that isn't, so it stays a version.
    private static let editionWords: Set<String> = [
        "remaster", "remastered", "re", "master", "mastered", "recorded", "deluxe", "expanded",
        "edition", "anniversary", "bonus", "track", "single", "album", "radio", "edit",
        "version", "mono", "stereo", "explicit", "clean", "original", "lp", "ep", "digitally",
        "digital", "soundtrack", "motion", "picture", "feat", "ft", "featuring", "with",
        "extended", "mix", "mixed", "12", "7", "45", "inch", "super", "special", "collectors",
        "short", "long", "full", "length", "the", "a",
    ]

    /// How a named version the rules don't know ends
    private static let namedVersionEndings: Set<String> = ["version", "mix", "edit", "remaster", "remastered"]

    /// The kinds of release Music names after an album's " - "
    private static let releaseKinds: Set<String> = ["single", "ep"]

    private static func isEditionWord(_ word: String) -> Bool {
        if editionWords.contains(word) {
            return true
        }
        // A year ("2011", "1980s") or an ordinal ("25th Anniversary")
        return yearOrOrdinal.firstMatch(in: word, range: whole(word)) != nil
    }

    private static let yearOrOrdinal = pattern(#"^(\d{4}s?|\d+(st|nd|rd|th))$"#)
    private static let featuredInBrackets = pattern(#"\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s+([^\)\]]*)[\)\]]"#)
    private static let featuredCredit = pattern(#"^(feat\.?|ft\.?|featuring|with)\s+(.*)$"#)
    private static let featuredBare = pattern(#"\s+(feat\.?|ft\.?|featuring)\s+(.*)$"#)
    private static let bracketed = pattern(#"\s*[\(\[]([^\(\)\[\]]*)[\)\]]"#)
    private static let dashSuffix = pattern(#"\s+-\s+(.*)$"#)
    private static let artistSeparator = pattern(#"\s*(?:,|;|/|\s&\s|\sand\s|\sx\s|\sfeat\.?\s|\sft\.?\s|\sfeaturing\s|\swith\s|\svs\.?\s|\s\+\s)\s*"#)

    /// Typographic marks to their typewriter forms, and letters that Unicode does not take
    /// apart into a base letter and an accent
    private static let foldedScalars: [Unicode.Scalar: String] = [
        "ø": "o", "Ø": "o", "æ": "ae", "Æ": "ae", "œ": "oe", "Œ": "oe", "ß": "ss",
        "ł": "l", "Ł": "l", "đ": "d", "Đ": "d", "ð": "d", "Ð": "d", "þ": "th", "Þ": "th", "ı": "i",
        "\u{2018}": "'", "\u{2019}": "'", "\u{201B}": "'", "\u{2032}": "'", "`": "'", "\u{00B4}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{2033}": "\"",
        "\u{2010}": "-", "\u{2011}": "-", "\u{2012}": "-", "\u{2013}": "-", "\u{2014}": "-",
        "\u{2015}": "-", "\u{2212}": "-",
    ]

    // MARK: - Helpers

    /// The artists a credit names, each folded as `artist(_:)`
    private static func artistNames(in credit: String) -> [String] {
        let folded = fold(credit)
        var names: [String] = []
        var start = folded.startIndex
        for match in artistSeparator.matches(in: folded, range: whole(folded)) {
            guard let range = Range(match.range, in: folded) else { continue }
            names.append(artist(String(folded[start..<range.lowerBound])))
            start = range.upperBound
        }
        names.append(artist(String(folded[start...])))
        return names.filter { !$0.isEmpty }
    }

    /// The rules are constants, so one that doesn't compile is a programming error
    private static func pattern(_ source: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: source)
    }

    private static func whole(_ text: String) -> NSRange {
        return NSRange(text.startIndex..., in: text)
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    private static func removing(_ range: NSRange, from text: String) -> String {
        guard let swiftRange = Range(range, in: text) else { return text }
        var result = text
        result.removeSubrange(swiftRange)
        return result
    }

}
