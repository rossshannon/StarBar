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
            let names = artistNames(in: names).everyone
            featured += names
            if keyword == "with" {
                withNames += names
            }
        }

        func take(_ part: String) -> Bool {
            guard let descriptor = describe(part) else { return false }
            if case .version(let kinds) = descriptor {
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
        // "(Expanded & Remastered)"
        let editionWords = words.filter { $0 != "and" }
        if (!editionWords.isEmpty && editionWords.allSatisfy(isEditionWord)) || (first == "from" && namesASoundtrack(folded)) {
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

    /// Who a credit is by (`artists`), and everyone it names (`everyone`).
    ///
    /// `artists` is every artist the credit names as its own, and the whole credit too:
    /// "Calvin Harris & Dua Lipa" gives "calvin harris", "dua lipa" and "calvin harris and dua
    /// lipa", and "Queen & David Bowie" gives "queen" among others. A band named like a list
    /// stays one name: see `artistNames(in:)`.
    ///
    /// A guest, after "feat." or "with", is left out of `artists`, as one in a title is:
    /// "Calvin Harris feat. Rihanna" gives "calvin harris" and the whole credit, never
    /// "rihanna". On their own, a guest's name would find their own song of the same title,
    /// and put the user's rating on it.
    ///
    /// `everyone` is `artists` and the rest the credit names: its guests, and a one-word name
    /// after the lead, which `artists` leaves out as a likely backing band. Everyone is
    /// what a "(with ...)" in another track's title is checked against (`Title.withNames`),
    /// never who the track is by: "All The Stars (with SZA)" by Kendrick Lamar is the
    /// library's by "Kendrick Lamar & SZA", and leaving SZA out of everyone lost it (the fourth
    /// review, 2026-10-29). One pass for both, since this runs for every track in the library.
    ///
    /// Only for the library's side. Spotify's artist is one name, compared whole.
    static func credited(_ raw: String) -> (artists: Set<String>, everyone: Set<String>) {
        let parts = split(fold(raw), on: guestSeparator)
        let own = parts.first ?? ""
        let names = artistNames(in: own)
        var artists = Set(names.own)
        for credit in [artist(own), artist(raw)] where !credit.isEmpty {
            artists.insert(credit)
        }
        var everyone = artists.union(names.everyone)
        for guest in parts.dropFirst() {
            everyone.formUnion(artistNames(in: guest).everyone)
        }
        return (artists, everyone)
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
    /// remix, though not which of the album's named remixes, so it is none of them
    /// (`isSameRecording`); and the library's "Everything In Its Right Place" on "I Might Be
    /// Wrong: Live Recordings" is live. Measured 2026-10-29: of the 736 pairs of library tracks the title
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
    ///   ("Live at Wembley 1986" and "1987"), two shows ("1st Show" and "2nd Show") or two
    ///   takes are two recordings. On the same release one name can say less than the other
    ///   instead: Spotify's "Hotel California - Live On MTV, 1994" is the "(Live on MTV)" on
    ///   "Hell Freezes Over".
    /// - Named by one only: when the other's album names it ("Clocks - Live in Sydney" is the
    ///   "Clocks (Live)" on "Live in Sydney"), or the two are on the same release ("Hotel
    ///   California - Live On MTV, 1994" is the "(Live)" on "Hell Freezes Over"). But a track
    ///   a remix album's name alone makes a remix is not one of its named remixes, since such
    ///   an album holds the original too: plain "Sweet Nothing" on "Sweet Nothing (Remixes)"
    ///   is not the "[Tiësto Remix]" on it.
    /// - Named by neither: a performance, such as a live recording or a remix, only on the
    ///   same release, since nothing else says which night or which remixer it was. Plain
    ///   "Clocks" on "Live in Sydney" is not plain "Clocks" on "Live in Buenos Aires".
    ///   Anything else ("Instrumental", a reprise) is the same whatever the albums.
    static func isSameRecording(_ name: String, on album: String, as otherName: String, on otherAlbum: String) -> Bool {
        let kinds = versions(of: name, on: album)
        guard kinds == versions(of: otherName, on: otherAlbum) else { return false }
        let myTitle = title(name).versions, theirTitle = title(otherName).versions
        let mine = names(in: myTitle), theirs = names(in: theirTitle)
        let sameRelease = isSameRelease(name, on: album, as: otherName, on: otherAlbum)
        return kinds.allSatisfy { kind in
            let myNames = mine[kind] ?? [], theirNames = theirs[kind] ?? []
            if !myNames.isEmpty && !theirNames.isEmpty {
                return myNames == theirNames || (sameRelease && oneNamesLess(myNames, theirNames, kind: kind))
            }
            if !myNames.isEmpty || !theirNames.isEmpty {
                let (given, plainAlbum, plainTitle) = myNames.isEmpty ? (theirNames, album, myTitle) : (myNames, otherAlbum, theirTitle)
                let isNamedByAlbum = given.allSatisfy { isNamed($0, by: plainAlbum) }
                if kind == "remix" && !SongName.kinds(of: plainTitle).contains(kind) {
                    return isNamedByAlbum
                }
                return sameRelease || isNamedByAlbum
            }
            return sameRelease || !performanceKinds.contains(kind)
        }
    }

    /// Whether two albums are the same release, once what says nothing about which release
    /// is off (`release(_:)`): "Hell Freezes Over (Remaster 2018)" is "Hell Freezes Over", and
    /// Music's "Wonderful Life - Single" is the single Spotify calls "Wonderful Life". Never
    /// for a track with no album.
    ///
    /// A plain version one name has and the other's not ("I Might Be Wrong: Live Recordings"
    /// and "I Might Be Wrong") is the same release only when the other says nothing else:
    /// "Album (Deluxe Edition)" is the studio album, not "Album: In Concert". Or when both
    /// tracks' titles say it, `markedByBoth`: Spotify's "Folsom Prison Blues - Live" on "At
    /// Folsom Prison (Legacy Edition)" is Music's "(Live)" on "At Folsom Prison (Live)", which
    /// the fifth review found missed (2026-10-30). The cost is the mirror of it: a "Song -
    /// Live" on "Album (Live)" is taken for a "Song (Live)" bonus track on "Album (Deluxe
    /// Edition)", which can be another night, should one artist give a studio and a live album
    /// the same name.
    static func isSameRelease(_ album: String, _ otherAlbum: String, markedByBoth: Set<String> = []) -> Bool {
        let one = release(album), other = release(otherAlbum)
        guard !one.name.isEmpty, one.name == other.name else { return false }
        return one.versions == other.versions
            || (one.versions.isEmpty && one.isBare)
            || (other.versions.isEmpty && other.isBare)
            || one.versions.symmetricDifference(other.versions).isSubset(of: markedByBoth)
    }

    /// `isSameRelease` for two tracks: a plain version both their titles mark doesn't tell
    /// their albums apart (`markedByBoth`), so "Intro - Live" on "Alive! (Deluxe Edition)" is
    /// on the release "Intro (Live)" on "Alive! (Live)" is.
    static func isSameRelease(_ name: String, on album: String, as otherName: String, on otherAlbum: String) -> Bool {
        let marked = kinds(of: title(name).versions).intersection(kinds(of: title(otherName).versions))
        return isSameRelease(album, otherAlbum, markedByBoth: marked)
    }

    /// An album's name as a release (`name`): without its edition words ("(Remaster 2018)"),
    /// an edition the rules don't know ("(Limited Edition)", "(Japan Version)", "(Bonus
    /// Tracks)"), a soundtrack credit ("(Original Motion Picture Score)"), Music's " - Single"
    /// and " - EP", or a plain version such as "(Live)" or ": Live Recordings", whose kinds are
    /// kept apart (`versions`). `isBare` when there was none of those to take off.
    ///
    /// A version the album names stays, because it names a different release: "Tour
    /// Anthology (Live in Sydney 2003)" is not "(Live in Buenos Aires 2017)", nor "(Bonus Disc:
    /// Live in Sydney 2003)" "(Bonus Disc: Live in Buenos Aires 2017)". A subtitle goes only
    /// when it is a plain version or says nothing: "TRON: Legacy" is not "TRON". `album(_:)`
    /// takes more off, so it can only choose between copies.
    private static func release(_ raw: String) -> (name: String, versions: Set<String>, isBare: Bool) {
        var text = fold(raw)
        var versions = Set<String>()
        func takesOff(_ part: String, asSubtitle: Bool = false) -> Bool {
            guard let found = releasePart(part, asSubtitle: asSubtitle) else { return false }
            versions.formUnion(found)
            return true
        }
        for match in bracketed.matches(in: text, range: whole(text)).reversed()
        where takesOff(substring(text, match.range(at: 1))) {
            text = removing(match.range, from: text)
        }
        if let match = dashSuffix.firstMatch(in: text, range: whole(text)) {
            let suffix = substring(text, match.range(at: 1))
            if releaseKinds.contains(squash(suffix)) || takesOff(suffix) {
                text = removing(match.range, from: text)
            }
        }
        if let match = subtitle.firstMatch(in: text, range: whole(text)), takesOff(substring(text, match.range(at: 1)), asSubtitle: true) {
            text = removing(match.range, from: text)
        }
        let name = squash(text)
        return (name, versions, name == squash(fold(raw)))
    }

    /// What a part of an album's name says about which release it is: nothing (an empty set)
    /// for an edition, one the rules don't know by its last word, its bonus tracks or its
    /// market ("Japan Version"), or a soundtrack credit; the kinds of a plain version
    /// ("Live", "Live Recordings", "Remixed"); and nil when it names the release, as a named
    /// version ("Live in Sydney 2003") or anything else does. A subtitle of one edition word
    /// is the album's name: "TRON: Legacy".
    private static func releasePart(_ part: String, asSubtitle: Bool) -> Set<String>? {
        let descriptor = describe(part)
        if case .version(let versions)? = descriptor, !versions.contains(where: { $0.hasPrefix("variant:") }) {
            return versions.allSatisfy { !$0.contains(":") } ? versions : nil
        }
        let folded = squash(fold(part))
        let words = folded.split(separator: " ")
        if (descriptor == .edition && !(asSubtitle && words.count == 1)) || words.contains("bonus") || ["edition", "editions"].contains(words.last ?? "")
            || marketVersion.firstMatch(in: folded, range: whole(folded)) != nil
            || isOnlyASoundtrackCredit(words, folded) {
            return []
        }
        return nil
    }

    /// Whether a part of an album's name is a soundtrack credit and nothing more: "Original
    /// Motion Picture Score", "Music from the Netflix Original Series". A series, volume or
    /// part it names is a release of its own, so "Doctor Who: Series 2" is not "Series 1",
    /// nor "Vol. 2" "Vol. 1": dropping any part that held a soundtrack word put a cue from
    /// one series on another's (the fifth review, 2026-10-30).
    private static func isOnlyASoundtrackCredit(_ words: [Substring], _ folded: String) -> Bool {
        return soundtrackWords.firstMatch(in: folded, range: whole(folded)) != nil
            && words.allSatisfy { soundtrackCreditWords.contains(String($0)) }
    }

    /// Whether one side's names for a version of `kind` say no more than the other's, but for
    /// when: a year, "mtv" against "mtv 1994" or "wembley 1986" (from "'86", `nameWords`), and
    /// for a live recording a month or day beside its date, "mtv december 1994". Anything else
    /// the longer name says tells another recording: "folsom state prison" is not "folsom state
    /// prison 2nd show", nor "tiesto" "tiesto deep house" (the fourth review, 2026-10-29). Nor
    /// is a bare number or a month on its own: Club 69 and Studio 54 are names, and so is
    /// "Marshall Jefferson March Remix" (the sixth review, 2026-10-30). A place is left out too,
    /// though Spotify's "Live in Paris, France" is the "(Live in Paris)" on the same album,
    /// since "york" against "new york" would be one.
    private static func oneNamesLess(_ names: Set<String>, _ otherNames: Set<String>, kind: String) -> Bool {
        func words(_ names: Set<String>) -> Set<String> {
            return Set(names.flatMap { $0.split(separator: " ").map(String.init) })
        }
        let (fewer, more) = words(names).count <= words(otherNames).count ? (words(names), otherNames) : (words(otherNames), names)
        guard fewer.isSubset(of: words(more)) else { return false }
        return more.allSatisfy { name in
            let sequence = name.split(separator: " ").map(String.init)
            return sequence.indices.allSatisfy { index in
                let word = sequence[index]
                if fewer.contains(word) || matches(year, word) {
                    return true
                }
                guard kind == "live" else { return false }
                let beside = [index - 1, index + 1].filter { sequence.indices.contains($0) }.map { sequence[$0] }
                if months.contains(word) {
                    return beside.contains { matches(year, $0) || matches(day, $0) }
                }
                return matches(day, word) && beside.contains { months.contains($0) }
            }
        }
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
    /// Numbers and ordinals stay, since they tell performances apart: "wembley 1986" is not
    /// "wembley 1987", "1st Show" is not "2nd Show", and "Take 2" is "session:2". A short
    /// year is the long one, "'86" 1986 and "'05" 2005, so that it is the year another name
    /// gives, and is not taken for a name such as Studio 54's. So does a
    /// record's size, as one word: Arthur Baker's 12\" remix is not his 7\" ("arthur baker
    /// 12in"). A remaster goes with its year ("2003 Digital Remaster"), and so does an
    /// anniversary with its ordinal, but a year the performance has stays beside a remaster's:
    /// "Live at Glastonbury 2011 Remastered 2020" is "glastonbury 2011".
    private static func nameWords(of folded: String) -> [String] {
        var text = recordSize.stringByReplacingMatches(in: folded, range: whole(folded), withTemplate: " $1in ")
        for match in shortYear.matches(in: text, range: whole(text)).reversed() {
            let digits = substring(text, match.range(at: 1))
            text = (text as NSString).replacingCharacters(in: match.range, with: ((Int(digits) ?? 0) < 30 ? "20" : "19") + digits)
        }
        for phrase in [remasterPhrase, anniversaryPhrase] {
            text = phrase.stringByReplacingMatches(in: text, range: whole(text), withTemplate: " ")
        }
        for kind in versionKinds {
            text = kind.words.stringByReplacingMatches(in: text, range: whole(text), withTemplate: " ")
        }
        return squash(text).split(separator: " ").map(String.init)
            .filter { (isCount($0) || !isEditionWord($0)) && !joiningWords.contains($0) }
    }

    /// A number or an ordinal: "1986", "2", "1st"
    private static func isCount(_ word: String) -> Bool {
        return countWord.firstMatch(in: word, range: whole(word)) != nil
    }

    /// "From \u{201C}8 Mile\u{201D} Soundtrack", "From the Motion Picture \u{201C}Titanic\u{201D}",
    /// "From \u{201C}TRON: Legacy\u{201D}/Score", but not "From The Heart"
    private static func namesASoundtrack(_ folded: String) -> Bool {
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
    /// and "Live Recordings"
    private static let joiningWords: Set<String> = [
        "at", "in", "from", "on", "of", "and", "for", "by", "to", "recorded", "recording", "recordings",
    ]

    /// Titles that name a part of an album rather than a song, alone, together ("Intro
    /// (Skit)") or numbered. A film score's cues count: James Horner's "Main Title" on
    /// "Braveheart" is not the one on "Aliens". "Theme", "Finale" and "Opening" don't, since
    /// they are songs' names too.
    private static let genericTitle: NSRegularExpression = {
        let part = "intro|introduction|outro|interlude|intermission|prelude|prologue|epilogue|overture|coda|segue|skit"
            + "|untitled|hidden track|bonus track|reprise|main titles?|main theme|end titles?|end credits"
            + "|opening titles?|opening credits|closing titles?|closing credits"
        return SongName.pattern(#"^(?:\#(part))(?: (?:\#(part)|\d+|[ivx]+))*$"#)
    }()

    /// Kinds of recording that differ from one performance or remixer to the next, so two
    /// plain ones are the same only on the same release (`isSameRecording`)
    private static let performanceKinds: Set<String> = ["live", "remix", "acoustic", "demo", "session", "rerecording", "orchestral"]

    /// A remaster and its year, in a version's name: "Live at Wembley - 2011 Remaster", "2003
    /// Digital Remaster". A year before it is the remaster's only when none follows: in "Live
    /// at Glastonbury 2011 Remastered 2020", 2011 is the night's.
    private static let remasterPhrase = pattern(#"\b(?:\d{4} (?:digital(?:ly)? )?re-?master(?:ed)?\b(?! \d{4}\b)|(?:digital(?:ly)? )?re-?master(?:ed)?(?: \d{4})?\b)"#)

    /// An anniversary edition's ordinal, in a version's name: "25th Anniversary"
    private static let anniversaryPhrase = pattern(#"\b\d+(?:st|nd|rd|th) anniversary\b"#)

    /// A record's size: "12\" Remix", "7-inch Mix", the size in the first group
    private static let recordSize = pattern(#"\b(7|10|12) ?(?:"|''|-?inch(?:es)?\b)"#)

    /// An edition named for where it was sold, or how: "(Japan Version)", "(International
    /// Version)", "(Tour Version)". Never "(Taylor's Version)", a re-recording. One named with
    /// an edition word, such as "(Explicit Version)" or "(Deluxe Version)", is an edition by
    /// `describe` already.
    private static let marketVersion = pattern(#"^(?:japan(?:ese)?|international|u ?s|u ?k|european?|australian|tour|standard) version$"#)

    /// A soundtrack credit says which film, or that it is one
    private static let soundtrackWords = pattern(#"\bsoundtrack\b|\bmotion picture\b|\bfilm\b|\bmovie\b|\bseries\b|\bmusical\b|\bscore\b"#)

    /// The words a soundtrack credit on an album is made of, and nothing that says which
    /// series, volume or part
    private static let soundtrackCreditWords: Set<String> = [
        "original", "motion", "picture", "score", "soundtrack", "music", "from", "the", "tv", "television",
        "series", "film", "movie", "musical", "cast", "recording", "netflix", "official", "and", "songs",
        "inspired", "by", "video", "game", "a", "an", "of", "to", "for", "hbo", "amazon", "apple", "disney",
        "hulu", "bbc", "prime",
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
    private static let countWord = pattern(#"^\d+(st|nd|rd|th)?$"#)
    /// What a live recording's name can add to say when: a year, and a month or a day beside
    /// it (`oneNamesLess`)
    private static let year = pattern(#"^(19|20)\d{2}$"#)
    private static let day = pattern(#"^([1-9]|[12]\d|3[01])(st|nd|rd|th)?$"#)
    private static let months: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
    ]
    /// "'86", with its apostrophe, which a number in a name doesn't have
    private static let shortYear = pattern(#"(?<![\w'])'(\d{2})(?![\w'])"#)
    private static let featuredInBrackets = pattern(#"\s*[\(\[]\s*(feat\.?|ft\.?|featuring|with)\s+([^\)\]]*)[\)\]]"#)
    private static let featuredCredit = pattern(#"^(feat\.?|ft\.?|featuring|with)\s+(.*)$"#)
    private static let featuredBare = pattern(#"\s+(feat\.|ft\.|featuring)\s+(.*)$"#)
    private static let bracketed = pattern(#"\s*[\(\[]([^\(\)\[\]]*)[\)\]]"#)
    private static let dashSuffix = pattern(#"\s+-\s+(.*)$"#)
    /// "I Might Be Wrong: Live Recordings"
    private static let subtitle = pattern(#"\s*:\s+([^:]+)$"#)
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
    /// a longer name a single word is kept when it comes first, since it is then the lead:
    /// "Queen & David Bowie" is Queen's "Under Pressure" (dropping it lost that, 2026-10-29).
    /// After the lead, a single word is as often a backing band as an artist of its own:
    /// "Bob Dylan & The Band" did "Tears of Rage" with them, and The Band's own is another
    /// recording. So it is left out of `own`, the names the track counts as by, and "Metro
    /// Boomin, The Weeknd & 21 Savage" can't be found as The Weeknd's, nor "Diana Ross & The
    /// Supremes" as The Supremes'. `everyone` keeps it, for a "(with ...)" to be checked
    /// against.
    ///
    /// ", The" can be inside a name ("Tyler, The Creator") or start the next one ("Metro
    /// Boomin, The Weeknd & 21 Savage"), and only knowing the artists tells which, so the
    /// names are read both ways.
    private static func artistNames(in credit: String) -> (own: [String], everyone: [String]) {
        let folded = fold(credit)
        let joined = commaThe.stringByReplacingMatches(in: folded, range: whole(folded), withTemplate: " the ")
        var own: [String] = [], everyone: [String] = []
        for reading in joined == folded ? [folded] : [joined, folded] {
            for segment in split(reading, on: creditSeparator) {
                let listed = listedNames(in: segment)
                for name in listed.own where !name.isEmpty && !own.contains(name) {
                    own.append(name)
                }
                for name in listed.everyone where !name.isEmpty && !everyone.contains(name) {
                    everyone.append(name)
                }
            }
        }
        return (own, everyone)
    }

    /// The names in one artist of a credit, or the whole of it when it is a band named like a
    /// list: see `artistNames(in:)`
    private static func listedNames(in segment: String) -> (own: [String], everyone: [String]) {
        let names = split(segment, on: listSeparator).map { artist($0) }.filter { !$0.isEmpty }
        guard names.count > 1, names.contains(where: { $0.contains(" ") }) else {
            let whole = artist(segment)
            return ([whole], [whole])
        }
        return (names.enumerated().filter { $0.offset == 0 || $0.element.contains(" ") }.map { $0.element }, names)
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

    /// Whether `regex` matches the whole of `word`, as the patterns anchored with ^ and $ do
    private static func matches(_ regex: NSRegularExpression, _ word: String) -> Bool {
        return regex.firstMatch(in: word, range: whole(word)) != nil
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
