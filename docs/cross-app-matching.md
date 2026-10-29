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

## Open

- Recall against real Spotify listening (how many songs the user owns are found) has not been measured yet. The first live checks, 2026-10-29: three versions of "The Maker" by Daniel Lanois each got the right answer. The studio version found the user's studio copy on Sling Blade, "The Maker - Live" found their "The Maker (Live)" on the same live album, and "The Maker - Calypso Demo" found nothing, the word "demo" keeping it from the studio copy. Seven songs the user doesn't own were correctly not found.
- Whether the names-only read is reliably quick has not been measured yet.
- No rating has been written through this path to a real library yet.
