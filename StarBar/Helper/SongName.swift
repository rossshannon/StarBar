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
        /// What makes this recording a different one from the plain song: a kind, such as
        /// "live" or "remix"; a kind with the name it was given, such as "remix:frankmusik"
        /// or "live:sydney"; or a whole named version the rules don't know, such as
        /// "variant:salsa version". Empty for the plain song. `isSameRecording` says how two
        /// tracks' versions are compared.
        let versions: Set<String>
        /// Artists credited in the title, as in "(feat. Aloe Blacc)", folded like `artist(_:)`
        let featured: [String]
        /// Those of `featured` credited with "with", as in "(with Justin Bieber)". Such a part
        /// is a guest on the same recording or an arrangement of a different one ("(With
        /// Strings)"), and only the other track's credits can tell which.
        let withNames: [String]
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
        var withNames: [String] = []
        var versions = Set<String>()

        func credit(_ keyword: String, _ names: String) {
            let names = artistNames(in: names)
            featured += names
            if keyword == "with" {
                withNames += names
            }
        }

        func take(_ part: String) -> Bool {
            guard let descriptor = describe(part) else { return false }
            switch descriptor {
            case .edition:
                break
            case .version(let kinds):
                versions.formUnion(kinds)
            }
            return true
        }

        // "(feat. Aloe Blacc)", "[with Rihanna]"
        for match in featuredInBrackets.matches(in: text, range: whole(text)).reversed() {
            credit(substring(text, match.range(at: 1)), substring(text, match.range(at: 2)))
            text = removing(match.range, from: text)
        }

        // Spotify's " - Remastered 2011", " - Live at Wembley", " - feat. X"
        if let match = dashSuffix.firstMatch(in: text, range: whole(text)) {
            let suffix = substring(text, match.range(at: 1))
            if let found = featuredCredit.firstMatch(in: suffix, range: whole(suffix)) {
                credit(substring(suffix, found.range(at: 1)), substring(suffix, found.range(at: 2)))
                text = removing(match.range, from: text)
            } else if take(suffix) {
                text = removing(match.range, from: text)
            }
        }

        // "(Remastered)", "[Radio Edit]", "(Live)", but not "(Fade Out)" or "(Don't Fear) The
        // Reaper", which are part of the song's name
        for match in bracketed.matches(in: text, range: whole(text)).reversed()
        where take(substring(text, match.range(at: 1))) {
            text = removing(match.range, from: text)
        }

        // "Song feat. X", with no brackets. Only with the dot: "A Feat of Strength" and "Fifty
        // Ft Woman" are names.
        if let match = featuredBare.firstMatch(in: text, range: whole(text)) {
            credit(substring(text, match.range(at: 1)), substring(text, match.range(at: 2)))
            text = removing(match.range, from: text)
        }

        let core = squash(text)
            .split(separator: " ")
            .map { $0 == "pt" ? "part" : String($0) }
            .joined(separator: " ")
        return Title(core: core, versions: versions, featured: featured, withNames: withNames)
    }

    /// What a part of a title in brackets or after " - " says, or nil when it is part of the
    /// song's name.
    ///
    /// Words that mark a different recording win: "Live at Wembley" is a version, not an
    /// edition, whatever else it says, and the name it gives the version is kept with it
    /// ("live:wembley"), because two remixes by different people, or two nights' live
    /// recordings, are different recordings. Then a part made only of edition words ("2011
    /// Remaster", "Single Version", "Radio Edit") is an edition, and so is a soundtrack
    /// credit. A part that ends in "Version", "Mix" or "Edit" but has other words in it ("Salsa
    /// Version", "Matt Butcher Mix") is a version the rules don't know, kept whole so it only
    /// matches itself.
    static func describe(_ part: String) -> Descriptor? {
        let folded = fold(part)
        let kinds = versionKinds
            .filter { $0.words.firstMatch(in: folded, range: whole(folded)) != nil }
            .map { $0.kind }
        if !kinds.isEmpty {
            let name = nameWords(of: folded).joined(separator: " ")
            return .version(Set(kinds.map { name.isEmpty ? $0 : $0 + ":" + name }))
        }
        let words = squash(folded).split(separator: " ").map(String.init)
        guard let first = words.first, let last = words.last else { return nil }
        if words.allSatisfy(isEditionWord) || (first == "from" && isSoundtrackCredit(folded)) {
            return .edition
        }
        if namedVersionEndings.contains(last) {
            return .version(["variant:" + words.joined(separator: " ")])
        }
        return nil
    }

    /// Whether a folded title (`Title.core`) names a part of an album rather than a song:
    /// "intro", "interlude 2", "untitled". Every album can have one, so two of them by one
    /// artist are the same track only on the same release.
    static func isGenericTitle(_ core: String) -> Bool {
        return genericTitle.firstMatch(in: core, range: whole(core)) != nil
    }

    // MARK: - Artists and albums

    /// One artist's name, folded, without a leading "The": "The Cranberries" and
    /// "Cranberries" are the same band, and so is "Cranberries, The", the way some libraries
    /// sort it.
    static func artist(_ raw: String) -> String {
        var text = fold(raw)
        if let match = trailingThe.firstMatch(in: text, range: whole(text)) {
            text = substring(text, match.range(at: 1))
        }
        let name = squash(text)
        return name.hasPrefix("the ") ? String(name.dropFirst(4)) : name
    }

    /// Every artist a credit names as its own, and the whole credit too: "Calvin Harris & Dua
    /// Lipa" gives "calvin harris", "dua lipa" and "calvin harris and dua lipa", and "Queen &
    /// David Bowie" gives "queen" among others. A band named like a list stays one name: see
    /// `artistNames(in:)`.
    ///
    /// A guest, after "feat." or "with", is left out, as one in a title is: "Calvin Harris
    /// feat. Rihanna" gives "calvin harris" and the whole credit, never "rihanna". On their
    /// own, a guest's name would find their own song of the same title, and put the user's
    /// rating on it.
    ///
    /// Only for the library's side. Spotify's artist is one name, compared whole.
    static func artists(_ raw: String) -> Set<String> {
        var own = fold(raw)
        if let guest = guestSeparator.firstMatch(in: own, range: whole(own)), let range = Range(guest.range, in: own) {
            own = String(own[..<range.lowerBound])
        }
        var names = Set(artistNames(in: own))
        for credit in [artist(own), artist(raw)] where !credit.isEmpty {
            names.insert(credit)
        }
        return names
    }

    /// Everyone a credit names, its guests too: what a "(with ...)" in another track's title
    /// is checked against (`Title.withNames`), never who the track is by
    static func credits(_ raw: String) -> Set<String> {
        return artists(raw).union(split(fold(raw), on: guestSeparator).dropFirst().flatMap { artistNames(in: $0) })
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

    /// What an album's name says about every track on it: "live" for "Live at the Fillmore
    /// West", "MTV Unplugged" or "Parklive (Live)", "remix" for "Strobe (Remixes)" or
    /// "Machinarium Remixed". Empty for most albums.
    ///
    /// A track on such an album often says nothing about it in its own title: Spotify's
    /// "Foregone Destruction" on "Tournament Rematch: Unreal Tournament Remixed" is someone's
    /// remix, and the library's "Everything In Its Right Place" on "I Might Be Wrong: Live
    /// Recordings" is live. Measured 2026-10-29: of the 736 pairs of library tracks the title
    /// rules call the same song, these words told 26 apart, 22 of them rightly. The other four
    /// are albums that only sound live or remixed, such as "I Could Live In Hope"; each costs
    /// one copy where the user has another.
    static func albumVersions(_ raw: String) -> Set<String> {
        let folded = fold(raw)
        return Set(albumVersionKinds
            .filter { $0.words.firstMatch(in: folded, range: whole(folded)) != nil }
            .map { $0.kind })
    }

    /// Every kind of recording a track is, from its title and its album together, without the
    /// names the title gives them: "live" for "Black - Live at GTE Amphitheater". Two tracks
    /// can only be the same recording when these are equal.
    static func versions(of name: String, on album: String) -> Set<String> {
        return kinds(of: title(name).versions).union(albumVersions(album))
    }

    /// The kinds of recording `versions` names, without the names: "remix:frankmusik" is a
    /// "remix". A version the rules don't know is a kind of its own.
    static func kinds(of versions: Set<String>) -> Set<String> {
        return Set(versions.map { named($0)?.kind ?? $0 })
    }

    /// Whether two tracks are the same recording, as far as their titles and albums say. They
    /// have to be the same kinds of recording (`versions(of:on:)`), and then, for each kind,
    /// the same performance of it:
    ///
    /// - Both named: by the same name. Two remixers, two venues, two years at one venue
    ///   ("Live at Wembley 1986" and "1987") or two takes are two recordings.
    /// - Named by one only: when the other's album names it ("Clocks - Live in Sydney" is the
    ///   "Clocks (Live)" on "Live in Sydney"), or the two are on the same release (Spotify's
    ///   "Hotel California - Live On MTV, 1994" is the "(Live)" on "Hell Freezes Over").
    /// - Named by neither: a performance, such as a live recording or a remix, only on the
    ///   same release, since nothing else says which night or which remixer it was. Plain
    ///   "Clocks" on "Live in Sydney" is not plain "Clocks" on "Live in Buenos Aires".
    ///   Anything else ("Instrumental", a reprise) is the same whatever the albums.
    static func isSameRecording(_ name: String, on album: String, as otherName: String, on otherAlbum: String) -> Bool {
        let kinds = versions(of: name, on: album)
        guard kinds == versions(of: otherName, on: otherAlbum) else { return false }
        let mine = names(in: title(name).versions), theirs = names(in: title(otherName).versions)
        let sameRelease = isSameRelease(album, otherAlbum)
        return kinds.allSatisfy { kind in
            let myNames = mine[kind] ?? [], theirNames = theirs[kind] ?? []
            if !myNames.isEmpty && !theirNames.isEmpty {
                return myNames == theirNames
            }
            if !myNames.isEmpty || !theirNames.isEmpty {
                let (given, plainAlbum) = myNames.isEmpty ? (theirNames, album) : (myNames, otherAlbum)
                return sameRelease || given.allSatisfy { isNamed($0, by: plainAlbum) }
            }
            return sameRelease || !performanceKinds.contains(kind)
        }
    }

    /// Whether two albums are the same release, once their edition words are off: "Hell
    /// Freezes Over (Remaster 2018)" is "Hell Freezes Over", and Music's "Wonderful Life -
    /// Single" is the single Spotify calls "Wonderful Life". Never for a track with no album.
    static func isSameRelease(_ album: String, _ otherAlbum: String) -> Bool {
        let one = release(album), other = release(otherAlbum)
        return !one.isEmpty && one == other
    }

    /// `album(_:)` without the " single" or " ep" Music adds
    private static func release(_ raw: String) -> String {
        let folded = album(raw)
        for kind in releaseKinds where folded.hasSuffix(" " + kind) {
            return String(folded.dropLast(kind.count + 1))
        }
        return folded
    }

    /// The names a title gives each kind of version: ["live": ["sydney"]] for "Clocks - Live
    /// in Sydney"
    private static func names(in versions: Set<String>) -> [String: Set<String>] {
        var names: [String: Set<String>] = [:]
        for version in versions {
            guard let own = named(version) else { continue }
            names[own.kind, default: []].insert(own.name)
        }
        return names
    }

    /// Whether an album's name holds every word of a version's name: "sydney" is named by
    /// "Live in Sydney"
    private static func isNamed(_ name: String, by album: String) -> Bool {
        return Set(name.split(separator: " ").map(String.init)).isSubset(of: Set(nameWords(of: fold(album))))
    }

    /// A named version's kind and name: ("remix", "frankmusik") for "remix:frankmusik". Nil for
    /// a plain kind, and for a version the rules don't know, whose whole text is its kind.
    private static func named(_ version: String) -> (kind: String, name: String)? {
        guard !version.hasPrefix("variant:"), let colon = version.firstIndex(of: ":") else { return nil }
        return (String(version[..<colon]), String(version[version.index(after: colon)...]))
    }

    /// The words that name a version, from a folded part of a title or an album's name: what is
    /// left once the words that mark the kind of recording, edition words and the words that
    /// join a name ("at", "in", "from", "recorded") are taken out. "sydney" for "Live in
    /// Sydney", "michael woods" for "Michael Woods Remix - Radio Edit".
    ///
    /// Numbers stay, since they tell performances apart: "wembley 1986" is not "wembley 1987",
    /// and "Take 2" is "session:2". A remaster's year goes with it.
    private static func nameWords(of folded: String) -> [String] {
        var text = remasterPhrase.stringByReplacingMatches(in: folded, range: whole(folded), withTemplate: " ")
        for kind in versionKinds {
            text = kind.words.stringByReplacingMatches(in: text, range: whole(text), withTemplate: " ")
        }
        return squash(text).split(separator: " ").map(String.init)
            .filter { (isNumber($0) || !isEditionWord($0)) && !joiningWords.contains($0) }
    }

    private static func isNumber(_ word: String) -> Bool {
        return word.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    /// "From \u{201C}8 Mile\u{201D} Soundtrack", "From the Motion Picture \u{201C}Titanic\u{201D}",
    /// "From \u{201C}TRON: Legacy\u{201D}/Score", but not "From The Heart"
    private static func isSoundtrackCredit(_ folded: String) -> Bool {
        return folded.contains("\"") || soundtrackWords.firstMatch(in: folded, range: whole(folded)) != nil
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
        ("session", pattern(#"\bsessions?\b|\brehearsal\b|\bouttake\b|\balternate\b|\balt\.? take\b|\btake(?= \d+\b)"#)),
        ("rerecording", pattern(#"\bre-?record(ed|ing)?\b"#)),
    ]

    /// Words in an album's name that mark every track on it as a different recording. Narrower
    /// than `versionKinds`, because an album is often named after a song: "Live to Tell" and
    /// "Live Forever" are not live albums, so "live" counts only before "at", "in", "from",
    /// "on" or a number ("Live 2003"), or after a bracket, or at the end. "Live After Death"
    /// and "Live and Dangerous" are missed.
    private static let albumVersionKinds: [(kind: String, words: NSRegularExpression)] = [
        ("live", pattern(#"\blive (at|in|from|on|recordings?|sessions?)\b|\blive \d|[\(\[]live\b|\blive[\)\]]?$|\bin concert\b|\bunplugged\b"#)),
        ("remix", pattern(#"\bremix(es|ed)?\b"#)),
    ]

    /// Words that only ever describe an edition of a recording, or a trivial edit of it.
    /// "Mix" is here so that "2009 Mix" and "Stereo Mix" are editions; a named mix such as
    /// "Matt Butcher Mix" still has a word that isn't, so it stays a version.
    private static let editionWords: Set<String> = [
        "remaster", "remastered", "re", "master", "mastered", "deluxe", "expanded",
        "edition", "anniversary", "bonus", "track", "single", "album", "radio", "edit",
        "version", "mono", "stereo", "explicit", "clean", "original", "lp", "ep", "digitally",
        "digital", "soundtrack", "motion", "picture", "feat", "ft", "featuring", "with",
        "extended", "mix", "mixed", "12", "7", "45", "inch", "super", "special", "collectors",
        "short", "long", "full", "length", "legacy", "the", "a",
    ]

    /// Words that join the name of a version to its kind, as in "Recorded Live at Wembley"
    private static let joiningWords: Set<String> = ["at", "in", "from", "on", "of", "and", "for", "by", "to", "recorded"]

    /// Titles that name a part of an album rather than a song, with an optional number
    private static let genericTitle = pattern(#"^(intro|introduction|outro|interlude|intermission|prelude|prologue|epilogue|overture|coda|segue|skit|untitled|hidden track|bonus track|reprise)( (\d+|[ivx]+))?$"#)

    /// Kinds of recording that differ from one performance or remixer to the next, so two
    /// plain ones are the same only on the same release (`isSameRecording`)
    private static let performanceKinds: Set<String> = ["live", "remix", "acoustic", "demo", "session", "rerecording", "orchestral"]

    /// A remaster and its year, in a version's name: "Live at Wembley - 2011 Remaster"
    private static let remasterPhrase = pattern(#"\b(\d{4} )?(digitally )?re-?master(ed)?( \d{4})?\b"#)

    /// A soundtrack credit says which film, or that it is one
    private static let soundtrackWords = pattern(#"\bsoundtrack\b|\bmotion picture\b|\bfilm\b|\bmovie\b|\bseries\b|\bmusical\b|\bscore\b"#)

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
    private static let featuredBare = pattern(#"\s+(feat\.|ft\.|featuring)\s+(.*)$"#)
    private static let bracketed = pattern(#"\s*[\(\[]([^\(\)\[\]]*)[\)\]]"#)
    private static let dashSuffix = pattern(#"\s+-\s+(.*)$"#)
    private static let trailingThe = pattern(#"^(.+?)\s*,\s*the$"#)
    /// Always between two artists
    private static let creditSeparator = pattern(#"\s*(?:;|\sx\s|\svs\.?\s)\s*"#)
    /// Before a credit's guests
    private static let guestSeparator = pattern(#"\s(?:feat\.?|ft\.?|featuring|with)\s"#)
    /// Between two artists, or inside a band's name: see `artistNames(in:)`
    private static let listSeparator = pattern(#"\s*(?:,|/|\s&\s|\sand\s|\s\+\s)\s*"#)
    /// "Tyler, The Creator": a comma before "The" is inside a name
    private static let commaThe = pattern(#",\s*the\s+"#)

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

    /// The artists a credit names, each folded as `artist(_:)`.
    ///
    /// "vs.", "x" and ";" always separate artists. A comma, "/", "&", "and" or "+" does only
    /// when a name it separates is more than one word. A list of single words is a band's
    /// name -- "Earth, Wind & Fire", "AC/DC", "Echo & the Bunnymen" -- and splitting it would
    /// let a band called Earth match Earth, Wind & Fire's "September". The cost is a duo
    /// credited by single names, like "Drake & Future", which then only matches whole. Beside
    /// a longer name a single word is kept, since it is usually the lead: "Queen & David
    /// Bowie" is Queen's "Under Pressure" (dropping it lost that, 2026-10-29).
    ///
    /// ", The" can be inside a name ("Tyler, The Creator") or start the next one ("Metro
    /// Boomin, The Weeknd & 21 Savage"), and only knowing the artists tells which, so the
    /// names are read both ways.
    private static func artistNames(in credit: String) -> [String] {
        let folded = fold(credit)
        let joined = commaThe.stringByReplacingMatches(in: folded, range: whole(folded), withTemplate: " the ")
        var names: [String] = []
        for reading in joined == folded ? [folded] : [joined, folded] {
            for name in split(reading, on: creditSeparator).flatMap({ listedNames(in: $0) }) where !name.isEmpty && !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    /// The names in one artist of a credit, or the whole of it when it is a band named like a
    /// list: see `artistNames(in:)`
    private static func listedNames(in segment: String) -> [String] {
        let names = split(segment, on: listSeparator).map { artist($0) }.filter { !$0.isEmpty }
        guard names.count > 1, names.contains(where: { $0.contains(" ") }) else {
            return [artist(segment)]
        }
        return names
    }

    /// `text` in pieces, cut at every match of `separator`
    private static func split(_ text: String, on separator: NSRegularExpression) -> [String] {
        var parts: [String] = []
        var start = text.startIndex
        for match in separator.matches(in: text, range: whole(text)) {
            guard let range = Range(match.range, in: text) else { continue }
            parts.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
        }
        parts.append(String(text[start...]))
        return parts
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
