# Cross-app matching: a Spotify song in the user's Music library

Measured 2026-10-28 on macOS 27.2 with Music 1.7.2, against one user's library of 8,092 tracks (8,089 of them songs), read-only. These are the facts the matching in StarBar 1.8 is built on: `SongName`, `SongMatcher`, `MusicLibraryIndex` and `LibraryMatchFinder`. Re-measure before relying on anything here for a different Music version or a very different library.

## What Spotify gives to match on

From `com.spotify.client.PlaybackStateChanged` (see [spotify.md](spotify.md)):

- `Artist` is **one name**, the primary artist. Featured artists appear in `Name` ("Song (feat. Someone)"), never in `Artist`.
- `Album Artist` is always empty for a song.
- `Duration` is in milliseconds.
- `Track ID` tells a song (`spotify:track:`) and a local file (`spotify:local:`) from an episode. Only those two are looked for.

So the library side is the one that gets split into names: a Music credit like "Calvin Harris & Dua Lipa" has to match a Spotify `Artist` of "Calvin Harris".

## Reading the library

- **One property over the whole library is one Apple Event**: `arrayByApplyingSelector:` on the library playlist's tracks returns every track's value in order. 14 to 48 ms per property on 2026-10-28, ten properties in about 250 ms. The Swift overlay in Xcode 16.4's SDK has no `arrayByApplying(_:)`, so the index calls the selector through the Objective-C runtime.
- **But the time varies a great deal.** On 2026-10-29 the same read of eleven columns of the same library took about 0.35 s, 4.4 s and 25 s at three launches of StarBar a few minutes apart. Music answers Apple Events one at a time, so while the read is out every other read StarBar makes waits behind it. So the index reads only what finding a song takes (persistent ID, name, artist, album artist), and `LibraryMatchFinder` reads the rest (media kind, album, length, rating, plays) from the few copies a song has. Each column's time is logged; what made the slow reads slow is not known.
- The lists come back in the same order, so they are paired by position. A track added or removed between two reads would pair one song's name with another's ID, so the persistent IDs are read first and again last, and the read is thrown away if they differ.
- **A missing value is left out of the list, not kept as a placeholder.** Measured 2026-10-29 on 8,093 tracks: `duration` came back with 8,090 values, because three songs (all file tracks) had no length, while JXA's own bulk read of the same property keeps a placeholder for each. Paired by position, every length after the first gap would have belonged to the song before. So the columns a song needs (persistent ID, name, artist) must be full length or the read is thrown away, and any other short column is left out of that read. The first build on a real library threw every read away for this reason; the tests' fakes had full columns.
- **Music can be slow to answer after a spell idle.** Measured 2026-10-29: the persistent-ID search for one copy, under StarBar's 1 s short timeout, failed with errAETimeout (-1712) on its count event after Music had been idle for about seven minutes; the same search from JXA straight afterwards took 209, 65, 16, 11 and 26 ms. Scripting Bridge answers a timed-out search with an empty list, which looks like a song that has gone, so a lookup has to count the failed events to tell the two apart. The copies are therefore read on the index's background connection with its 10 s timeout, and a lookup Music didn't answer is asked again once.
- **Where the time between a Spotify song starting and its copy's stars goes.** Measured 2026-10-29 with "Go Slowly" by Radiohead played four times over: three starts took 332 to 587 ms from Spotify's notification to the match, of which reading the copy on the index's connection took 153 to 421 ms and fetching it again on the station's connection, on the main thread, about 150 ms more. The fourth took 3,940 ms. Music answered that lookup's events in 496, 16, 17, 157, 424, 691, 716, 285 and 281 ms, against its usual 15 to 25, the station's fetch took 848 ms for seven events, and the main thread had just spent two seconds on two menu bar reads that timed out (errAETimeout, -1712). Of the sixteen events a lookup sent, eight found Music's library playlist, four on each connection, and the menu bar and strip then read the copy's rating and heart on the main thread, four events each. Since then the playlist is found once per Music process on each connection, the rating and heart are read with the copy, and the station's track is a reference that sends nothing.
- **One record, not one event per property.** The first build after that still read seven properties one at a time, each through the persistent-ID search, so each event searched the library again. Installed and measured the same night, with two Radiohead songs played alternately in Spotify, one copy took 993, 2,089, 459 and 1,359 ms, starting two minutes after the live tests had kept Music busy for two minutes; both Go Slowly reads missed the 1 s wait, so it showed as a Spotify song first. Eleven minutes later, with Music idle, the same build read six copies in 122 to 200 ms, and every play showed the copy's stars directly, in the menu bar and the strip, 130 to 211 ms after Spotify's notification. So most of the first run's time was Music still being slow, not the reads themselves. A probe a few minutes later, with Music idle, timed the ways of reading the same two copies four times each: the seven reads through the search took 133 to 172 ms; `get()` on the search (7 to 22 ms) and then the seven reads by ID took 121 to 172 ms; `get()` and then one read of `properties` took 34 to 91 ms (258 ms once, the first time). The record has 59 properties, among them everything a copy needs except `ratingKind`, which has to be read on its own. The media kind arrives as an enumerated descriptor (`'kMdS'`), the heart as a boolean `NSNumber`. Reading rating and heart through the station's search reference took 15 to 65 ms. So a copy is now a `get()` and a `properties` read, plus `ratingKind` when it has a rating.
- Rejected: a `whose` query per song (8 to 18 ms, but one per field combination and no fuzzy matching), Music's `search` command (matches word prefixes, ignores accents, but treats `'` and `’` as different, and Music 1.7.2's `only` enumeration has `names`, not `songs`), and the iTunesLibrary framework (an entitlement and a privacy prompt).
- Music's `whose` ignores case, accents and `'` against `’`. A compound `whose` with `_and` fails from JXA but works from AppleScript.

## What the library looks like

These decided the rules more than any guess did.

| | Count |
|---|---|
| Titles shared by different artists | 397 |
| Songs held in both a studio and a live or remix version | 75 |
| Songs held two or more times | 442 |
| ... of which the copies' ratings disagree | 103 |
| Credits a comma, `&`, "and" or `+` would split into one-word names, as "Earth, Wind & Fire" | 52 |

- Titles shared by different artists are why the artist must match: title alone would rate the wrong song.
- Studio against live or remix is why those words are kept, so the two count as different songs. That is a choice, not a measurement, and can be revisited.
- Duplicates with conflicting ratings are why one copy is chosen, by a fixed order (the album Spotify named, then a rated copy, then the nearest length, then the most played), and only that copy is rated (also a choice: rating every copy was the alternative).
- Those one-word splits are why a comma, `&`, "and" or `+` splits a credit only when one of the resulting names has more than one word. The first version split them all, and "Earth" alone matched. The cost is a duo of one-word names ("Simon & Garfunkel" and any real pair like it) matching only on the whole credit.
- **A track on a live or remix album often says so only in the album's name.** "Everything In Its Right Place" on "I Might Be Wrong: Live Recordings", the whole of Nirvana's "MTV Unplugged In New York", and Spotify's "Foregone Destruction" on "Tournament Rematch: Unreal Tournament Remixed", which is someone else's remix credited to the original composer. So an album's name can mark its tracks live or remix too (`SongName.albumVersions`), and two copies match only when title and album together say the same. Of the 736 pairs of library tracks the title rules call the same song, this tells 26 apart, 22 rightly. The other four come from albums that only sound like it ("I Could Live In Hope" by Low, "Giant (Remixes)", which holds the original too) and each costs one copy where the user has another. "Live" in an album's name counts only before "at", "in", "from" or "on", after a bracket or at the end, because albums are often named after songs: "Live to Tell", "Live Forever". The index holds no albums, so this is checked once each copy's album has been read (`SongMatcher.ranked(_:for:)`).

## Recall against the user's Spotify likes

Measured 2026-10-29 by running the rules (through the Python mirror in the project's shared files) over the 185 songs liked in the user's Spotify account and the 8,092-track library read the day before. The likes are 183 different songs. **18 are found**; the other 165 were checked for near misses.

- 20 were found by name; the album rule then left out two, both from "Tournament Rematch: Unreal Tournament Remixed", which had matched the original recordings, 122 s and 48 s shorter. Those two are why the album rule exists.
- Most of the rest the user doesn't have: game and film soundtracks, covers, and songs by artists the library has other songs by.
- **Three songs the user has were missed because the two apps credit them to different names**: "The Merchant" by Yoann Laulan is the library's by Valmont de Ragondas, his alias; "Orsis" by Peter McConnell is the library's by Blizzard Music; "Curry Goat, Rice and Peas" by Autotuned Vids is the library's by "Autotunedvids & Solesky". Matching on title and length alone would find all three (their lengths agree within a second) but was rejected: in the same library 19 pairs of tracks share a title and a length within 1.5 s with no artist in common, and of the 12 that aren't voice memos several are covers, such as "Killing Me Softly" by the Fugees and by Roberta Flack, 1 s apart.
- **Length is not a test of the same recording either**: some matches differ greatly in length and are still the same song in another edit ("Sweet Harmony", 4:22 on the single and 15:18 on the album), and within the library 112 same-song pairs differ by more than 30% and 10 s, many of them radio or single edits ("Move On Up" is 2:46 and 8:49).
- "a-ha" and "Aha" fold to different names ("a ha" against "aha"). None of the likes is affected, since the one a-ha like is an acoustic version the user doesn't have.

## Open

- Recall against the user's likes is above; recall against what they actually play has not been measured. The first live checks, 2026-10-29: three versions of "The Maker" by Daniel Lanois each got the right answer. The studio version found the user's studio copy on Sling Blade, "The Maker - Live" found their "The Maker (Live)" on the same live album, and "The Maker - Calypso Demo" found nothing, the word "demo" keeping it from the studio copy. Seven songs the user doesn't own were correctly not found.
- Whether the names-only read is reliably quick has not been measured yet.
- No rating has been written through this path to a real library yet.
