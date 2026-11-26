# Apple Music catalog tracks: what StarBar can and cannot do

Measured on macOS 27 (Darwin 27.0.0) with Music.app, 2026-09-17, against Ross's library
(8,077 tracks). All findings are from live reads and writes, not documentation.

## The short version

When you play a song straight from the Apple Music catalog without adding it to your library,
Music hands out a **different kind of object** than it does for a library song. On that object:

- **Setting a rating fails.** Music returns a permission error. Nothing is stored, and the
  failure is silent from the user's point of view.
- **Setting the favourite (heart) succeeds** and is retained.
- Neither write adds the song to the library.

So the stars are misleading on these tracks, and the heart is not.

## The two object kinds

Music models a playing track as one of several scripting classes. The one that matters here:

| | Library song | Apple Music catalog stream |
|---|---|---|
| Scripting class | `file track` (`cFlT`) | `URL track` (`cURT`) |
| `location` | a file URL | absent |
| `cloud status` | a real value | `missing value` |
| `database ID` | stable library ID | a large transient ID |
| Set rating | works | **fails, error -54** |
| Set favourite | works | works |

This holds even for songs added from Apple Music and never downloaded: they are still
`file track`s with a `cloud status` of `subscription`, and ratings work on them normally.
Library membership, not where the audio comes from, is what decides whether a rating sticks.

### The same song can be both

Ross's library contains "Street Spirit (Fade Out)" as a `file track` (database ID 5769).
Playing that same song from the Apple Music catalog produced a *separate* `URL track`
(database ID 372036) with its own rating of 0. Rating the streamed copy would not have
touched the library copy even if the write had succeeded.

## Evidence

Writing a rating to the catalog track, via AppleScript:

```
BEFORE class=URL track dbID=372036 rating=0 favorited=false
setRating=ERROR Music got an error: File permission error.
setFavorited=ok
AFTER  class=URL track dbID=372036 rating=0 favorited=true
libraryCount unchanged (8077 before and after)
```

StarBar already hits this in production. Its own log, while this track was playing:

```
iTunesRadioStation.swift[219], eventDidFail(_:withError:):
AppleEvent (tvea) call fail with error The operation couldn't be completed. (OSStatus error -54.)
```

OSStatus -54 is a permission error — the same refusal, arriving through Scripting Bridge
instead of AppleScript. The app sends the write, Music refuses it, the error is logged and
discarded, and the menu bar keeps showing the stars the user just set.

## How to detect it in code

`is iTunesURLTrack` does **not** work. `iTunes/Vendor/iTunes.swift` declares
`extension SBObject: iTunesFileTrack`, `iTunesSharedTrack` and `iTunesURLTrack`, so every
Scripting Bridge object satisfies all three casts. Verified: the runtime class is always
plain `SBObject`.

Two things that do work, both read from Swift:

1. **The AppleEvent class code**, which is the direct expression of "what kind of track is
   this":

   ```swift
   (track as AnyObject).value(forKey: "objectClass") as? NSAppleEventDescriptor
   // typeCodeValue == 'cURT' for a catalog stream, 'cFlT' for a library song
   ```

2. **`location == nil`**, which is simpler but indirect. Not yet proven against a library
   song that is in the cloud but not downloaded — every subscription track sampled so far
   was downloaded and had a location.

Route 1 is preferred: it asks Music what the track *is*, rather than inferring it from a
missing file path.

Do not use `rating kind`. An unrated *library* song also reports `computed`; it means "this
rating was derived from the album", not "this track cannot be rated".

Do not use `cloud status` from Swift. `missing value` arrives as `0`, which matches no case
of `iTunesEClS`, so the enum cannot represent it.

`exists` returns `true` for a catalog track, so `iTunesPlayer.currentTrack` does not filter
these out — the app treats them as ordinary tracks today.

## Adding the song to the library

`duplicate <track> to source "Library"` adds it. Three things about it are not obvious:

- It must be the library **source**. Duplicating to `library playlist 1` fails with
  "Can only duplicate subscription tracks to library source" (-10006).
- **It returns nothing usable.** The scripting dictionary declares a result specifier, but the
  variable is undefined afterwards. A first test appeared to succeed only because the read was
  inside a `try` block that swallowed the error.
- The new entry is a normal `file track` with a `cloud status` of `subscription`, and it is
  **rateable immediately** — a rating written with no delay at all reads straight back as a
  user rating. There is no window in which the song exists but cannot be rated.

Whether the add also downloads the audio is unresolved. Music reports a size for the new
track, but `~/Music/Music/` is blocked by privacy protection so the bytes can't be checked.
Music has a separate `download` command, which would be redundant if `duplicate` downloaded,
and the download appears to be queued asynchronously in any case. It does not affect whether
there is somewhere to store the rating, which is the part that matters here.

### Finding the song after adding it

Since the add returns nothing, the new song has to be found afterwards — and **not by name**.
Collect the database IDs of the tracks matching the song before the add, then take whichever
one is new. Only a handful ever match, so it is cheap.

Matching on name alone rates the wrong song. That is not hypothetical: a test doing it found
two songs called "Flume" in this library, by Bon Iver and by Rare, and rated both.

### The playing track never changes

After the add, the track Music reports as playing is still the `URL track`, still rating 0,
for the rest of the song. It does not become the library copy. Anything that should show the
new song's rating has to switch to the library copy itself.

## The favourite is held separately on each object

Measured 2026-09-18, resolving what this document previously listed as an open question.

While one song played from the catalog, the two objects disagreed:

| Object | `database ID` | `favorited` | `rating` |
|---|---|---|---|
| The playing catalog track | 373758 | `false` | 0, computed |
| The user's library copy | 376525 | `true` | 80, user |

Music keeps a separate flag on each and does not keep them in step, so a heart written to the
playing track never reads back. The heart therefore goes where the rating goes, through
`PlayingTrack.favoriteTrack`.

Two further findings the same day:

- **Setting Favourite on a catalog track in Music adds the song to the library.** A song for
  which StarBar was showing the Apple Music button was in the library minutes later, with no
  add from StarBar in its log, and stayed there after the favourite was removed again.
- **The favourite is a network round trip.** Music's own star took about 3 s to fill after the
  press, and the scripting flags changed at the same time, not at the moment of the click.

## Artwork is not reliably the playing track's

Measured 2026-09-18 by sampling Music across track changes: its own `current track` name and
album, the artwork count, and an md5 of the artwork bytes.

Three distinct behaviours, all on `URL track`s:

| Behaviour | Example | What the strip showed |
|---|---|---|
| Artwork is present and correct | Bowie, *The Shel Talmy Recordings*; Sam Smith, *Music Room* | the right sleeve |
| Artwork is present and **another song's** | "Strawberry Blonde"; Music returned the sleeve of the *Another Green World* album played before it | the wrong sleeve |
| Artwork is absent at first | "Virginia Isn't for Lovers": count went `0 0 ERR 1 1 1 …`, filling in after about 7 s | the placeholder |

The wrong-sleeve case persisted for minutes, so it is not a race at the track boundary. The
absent case is a race, but often a slower one than the strip's 5.3 s life, so re-reading would
frequently fill in artwork nobody is still looking at.

A library song's own artwork is reliable, and the library copy of a song playing from the
catalog returns the correct sleeve when the catalog track does not. So artwork is read through
`PlayingTrack.artworkTrack`, the user's copy first.

**It still falls back to the playing track.** Refusing to read a catalog track's artwork at all
was tried and reverted within minutes: the sampling above shows catalog artwork is usually
correct, so the strict rule blanked every Apple Music song's artwork to avoid an occasional
wrong one. A larger sample on 2026-11-03 found the opposite, over half wrong (see "Another song's
cover, not the previous one's" below), and the answer chosen then was Apple's cover first.

### The previous song's cover, left over

Seen again on 2026-11-02: "Chain Home" by Tom Rogerson and Brian Eno, played from the catalog
and not in the library, came back with the sleeve of *The Bends*, straight after "Fake Plastic
Trees". The strip and the popover both showed it until the song was added to the library,
when StarBar switched to the new copy's artwork, which was right. The sleeve on screen looked
like the library file's own low-resolution scan rather than Apple's catalog artwork, which
suggests Music handed back the previous track's artwork as it held it. That is a reading of a
screenshot, not a measurement.

Both wrong sleeves seen so far were **the previous song's**. That much can be caught without
knowing which song a sleeve belongs to: `PlayingTrack.sleeve()` compares Music's answer for a
catalog track the user doesn't have with the previous song's cover, and when they are the same
cover for songs on different albums, shows the placeholder instead. The two are compared as
16 by 16 grids of colours (`SleeveFingerprint`), since the bytes differ with size and
encoding, and the albums as releases (`SongName.releaseName`), since consecutive tracks of one
album share a cover. The tolerance is a guess; StarBar logs every difference it measures.

A cover refused this way is then fetched from Apple's public iTunes Search service, by the
song's artist and title (`AppleMusicArtworkLoader`, below), and shown when it arrives, in the strip
while it is still up and in the popover. Only an exact album and artist match is taken.

Checked live the same evening, in Ireland's store: the search for "Tom Rogerson & Brian Eno
Finding Shore" answered with *Finding Shore* first and a Kenny Rogers album second, and the one
for "Radiohead The Bends" with *The Bends* first among ten, Rosie Carney's own *The Bends*
included. The rule takes the first and turns the others down, and the 600 px cover for each
downloaded (100 KB and 77 KB JPEGs). On the installed build, two catalog songs in turn by
different artists (David Bowie, then Daniel Lanois) measured 0.193 apart, against both the
cover shown for the first and Music's answer for it, so the second kept Music's cover and
Apple was not asked. The refusal itself has not yet been seen live.

### No cover at all

Minutes later, two catalog songs in a row came with no artwork: "Exit Music (For a Film)
[Remastered]" on *OK Computer OKNOTOK 1997 2017*, then "Obsidian" on *Mixing Colours
(Expanded)*. Music reported `count of artworks` 0, and reading artwork 1 failed with a
parameter error, for as long as the songs were looked at. This is the "absent at first" row of
the table above, but it did not fill in. Such a song's cover is asked of Apple too.

Apple's **album** search does not know every edition by Music's name for it: "Radiohead OK
Computer OKNOTOK 1997 2017" answered with the plain *OK Computer* and seven unrelated albums,
and the album rule rightly refused *OK Computer*, whose cover is another. The **song** search
for "Radiohead Exit Music For a Film" answered with the track on *OK Computer OKNOTOK 1997
2017* first, with its own cover, and the plain album's second. So the loader searches for the
song and keeps the cover for its album.

The song search, checked live for five songs as the app sends it (artist and title as Music
gives them, 25 results, Ireland's store):

| Song | Album wanted | Found |
|---|---|---|
| Exit Music (For a Film) [Remastered] | OK Computer OKNOTOK 1997 2017 | 1st |
| Obsidian | Mixing Colours (Expanded) | 1st; 2nd was the plain *Mixing Colours*, another cover |
| Chain Home | Finding Shore | 1st |
| Falling At Your Feet (with Bono) | Shine | 1st, the only result |
| Life On Mars? (Original Ending Version) | Divine Symmetry | **not at all**: no Bowie song among 16 |

Without "(Original Ending Version)", the Bowie search found *Divine Symmetry* 17th, through
other tracks of it, so a title that finds nothing is searched for again without its bracketed
parts. And because an expanded edition and the album can have different covers, the album is
matched letter for letter (case, accents and punctuation aside), not as a release.

### What the search can't find

"Germination (Coda)" by Ryuichi Sakamoto, on *Coda*, came with no cover from Music, and neither
song search found that album: they answered with "Germination" on *Merry Christmas, Mr.
Lawrence*, on the *Call Me By Your Name* soundtrack and in covers by other artists, which the
album rule refused. An album search for "Ryuichi Sakamoto Coda" found no album of that name in
the Irish, US, British or Japanese stores. The iTunes Search service lists what the iTunes Store
sells, so an album that is only streamed on Apple Music is, by this reading, out of its reach;
that it is streaming-only is an inference, not checked. Such a song keeps Music's cover, or the
placeholder when Music has none. The Apple Music API would find it, but needs a developer token signed with a MusicKit key.

### Another song's cover, not the previous one's

On 2026-11-03 the strip showed Nils Frahm's "Some", on *Solo*, with the cover of Ryuichi
Sakamoto's *Coda*. StarBar's log shows it was Music's own answer for the catalog track: the
cover differed from the previous song's ("I Am Sky", Laraaji) by 0.437 against both the cover
shown and Music's own for it, so the check passed it. *Coda* had last played 45 minutes and
twelve songs earlier, and Music had then had **no** cover for the *Coda* song itself. Nothing in
StarBar held that image: the Apple cover cache is keyed by artist and album, and Apple's search
has no *Coda*. Where Music got it is not known; one untested guess is that it answers with the
last artwork it loaded anywhere, such as an album page open in its window. "Some" had played
twice before that morning on another build, and which cover showed then is not recorded.

Nothing in what StarBar remembers could catch that, so since that day **Apple's cover is asked
for every catalog track the user doesn't have**, once per album, and wins whenever the search
finds the album. For "Some", the search for "Nils Frahm Some" had *Solo* first among 25, ahead of
*Solo Remains*, *Paris* and nineteen Johannes Bornlöf compilations. Music's own cover is shown
only when Apple has no match or can't be reached. The cost is the placeholder for about half a
second on the first song of each album, fading to the cover when it comes.

**It is the common case, not the exception.** On the evening of 2026-11-03 a stutter test of
the strip ran a build of main with the left-over check and the break-out sleeve but without this
rule, and every cover the strip showed was captured. Of 21 strips, 9 showed the wrong cover:
9 of the 16 catalog songs not in the library, and none of the 5 library songs. The left-over
check caught one, "The Maker" with *The Bends*. The other eight were not the previous song's:

| Song | Cover shown |
|------|-------------|
| "Windowlicker" | John Foxx, *The Garden* |
| "Soto Wa Ame" | a Roedelius album played four songs earlier |
| "Sunson" | Robin Guthrie, *Continental* |
| "Starman" | Nils Frahm, *Solo* |
| "Selange" | Steve Roach, *Structures from Silence* |
| "Falling At Your Feet" | David Bowie, *Divine Symmetry* |
| "Ziggy Stardust" | Daniel Lanois, *Acadie* |
| "Here Comes the Flood" | a Jon Hassell album |

"Wenn der Südwind weht" showed *Mixing Colours*, the previous song's cover, but it was the first
song after a relaunch, so there was no previous cover to compare it with. Later the same evening "Space
Oddity (2015 Remaster)" showed *OK Computer OKNOTOK 1997 2017*, and Music went on answering with
that cover (an 800×800 PNG) when asked again. OKNOTOK had last played the day before, so a wrong
cover can come from a day back, far beyond anything StarBar remembers; the left-over check
compared it with the previous song's, "Evensong", found a difference of 0.345 and let it
through. Apple's song search had the right album first, *David Bowie (aka Space Oddity) [2015
Remaster]*, and the same search had the right album for each of the nine wrong covers above;
whether the loader's album and artist rules take those results was not checked. With over half of
these songs wrong, the earlier audit's finding that catalog artwork is usually correct no longer
holds, and asking Apple for every such song is what the evidence calls for.

The same log showed the first song after a launch going unchecked: "I Am Sky" showed *Insen*,
the cover of "Aurora", which was playing when StarBar started. Music announces nothing at
launch, so that song had never joined the recent songs; the launch read now adds it.

### Open question

How to tell a wrong sleeve from a right one for an album Apple's search doesn't have, such as
*Coda*. Nothing on an artwork says which song it belongs to, and the catalog object and the
library copy hold different resolutions (800×800 against 600×600 for the same album), so the
bytes cannot be compared either. The Apple Music API would answer by song identifier, but
needs a developer token. Music's `playerInfo` notification does not carry the catalog ID:
measured 2026-09-23 over 24 notifications, it had no `Store URL` key for a catalog track or a
library song, so `PlayInfo.storeURL` stays empty (see "What identifies the playing catalog
track" below). MediaRemote does carry it, with an `mzstatic.com` artwork URL for the song's own
release, but only through a private framework, so it answers the question without being
something to ship.

## Finding the user's copy when the catalog plays a different release

Measured 2026-09-23, read-only, against a library of 8,090 songs.

**Since built:** on 2026-11-16 the library matcher (`SongMatcher`) began finding the user's copy
of a catalog song when the exact search misses, by metadata, as the first proposal at the end
of this section suggests. Its rules are in
[cross-app-matching.md](cross-app-matching.md#apple-music-catalog-songs-and-titles-without-their-last-bracket).
The prototype key below came first and is not the one StarBar uses.

### The case that prompted it

| | The playing catalog track | The user's library copy |
|---|---|---|
| Name | Where the Streets Have No Name | Where the Streets Have No Name **(New Edit)** |
| Album | The Joshua Tree (20th Anniversary Deluxe Edition) [2007 Remaster] | **U218 Singles** |
| Duration | 336.6 s | **286.5 s** |
| Class | `URL track` | `file track`, `cloud status` purchased |
| Rating, favourite | 0 computed, false | 80 user, true |

`libraryCopy(of:)` matches name, artist and album together, and two of the three differ, so it
finds nothing and the menu bar offers to add a song the user already owns. The durations differ
by 50 s, so these are different edits: no identifier comparison will ever join them.

### Three kinds of "the same song"

| Kind | Example | What can join them |
|---|---|---|
| The same catalog item | An album added from Apple Music, then played from its catalog page | Exact name, artist and album (what StarBar did then), or the catalog ID |
| The same recording, another release | A remaster, a compilation, a soundtrack reissue | Artist and a cleaned title, with durations within a few seconds |
| The same song, another edit | The U2 case; radio and single edits | Artist and a cleaned title only. Duration can differ by a minute or more |

The public catalog shows why IDs cannot do the second and third kinds. A search of the iTunes
Search API for the title returns 15 U2 songs, each with its own ID, and the 2007 remaster that
was playing is a 16th. The 15 are the album version (338 s, twice), two "Edited Version"s
(275 s), "New Edit U218" (286 s), the U218 Singles version (288 s), six live recordings, a
remix, a medley and the 2023 re-recording.

### What identifies the playing catalog track

- **Scripting Bridge: nothing.** Its roughly 80 properties include no store or catalog ID,
  `address` raises -1728, and album artist, year and track number are blank. Music's scripting
  dictionary declares no such property.
- **MediaRemote (private framework): the full set.** A direct call from an ordinary process
  returns nothing, which matches the restriction Apple added in macOS 15.4. Loaded into
  `/usr/bin/perl` through `DynaLoader`, the workaround `mediaremote-adapter` uses, it returned:
  `iTunesStoreIdentifier` 1440783563 (the song; the iTunes lookup API confirms it is this
  release, 336,613 ms), `AlbumiTunesStoreAdamIdentifier` 1440783429,
  `ArtistiTunesStoreAdamIdentifier` 78500, an artwork URL, and the radio station playing it.
  The song was playing from a station ("Champagne Supernova (Remastered) Station"), and a play
  straight from an album page has not been sampled. It gave the same keys for 12 more station
  songs. For a library song, its `iTunesStoreIdentifier` equals the library's `storeItemID`
  (see below) in all three cases tried: a subscription, a matched and a purchased song. Its
  `UniqueIdentifier` is the catalog song ID for a catalog stream, but the signed persistent ID
  for a library song. That route depends on an Apple binary's allow-listing, and Apple can
  close it in any update.
- **The `playerInfo` notification: no store identifier at all.** For a catalog track it
  carries only `Name`, `Artist`, `Album`, `Genre`, `Player State` and `Total Time`. For a
  library song it adds `PersistentID`, `Library PersistentID` and sometimes `Composer`. There
  is no `Store URL` key in either case (24 notifications captured).
- **MusicKit: not usable as StarBar is signed.** Catalog requests, ISRC filtering and
  `Song.playParameters` exist on macOS 12+, and `MusicLibraryRequest` on macOS 14+. All of
  them need the MusicKit App Service on an App ID owned by a paid developer team. An ad hoc
  build has no team. `SystemMusicPlayer`, which would name the playing song, does not exist
  on native macOS. So MusicKit could say whether two catalog IDs share a recording (ISRC), but
  it cannot say what Music is playing.

### What identifies library songs

- **`ITLibMediaItem` has undocumented catalog properties:** `storeItemID`,
  `subscriptionAdamID` and `cloudUniversalLibraryID`. `ITLibAlbum` has `adamID`,
  `subscriptionAdamID` and `cloudAlbumID`. `ITLibArtist` has `subscriptionAdamID`. They were
  found by listing the class's Objective-C properties. None of them is in the public headers.
- **Reading them needs Media & Apple Music permission.** `AMPLibraryAgent` refuses a bare
  command-line binary without prompting ("Refusing connection … TCC not granted"). An app
  bundle with `NSAppleMusicUsageDescription` gets a prompt, and once allowed it loads the whole
  library in 5.6 s.
- **Only `storeItemID` is filled in.** `subscriptionAdamID`, `cloudUniversalLibraryID` and all
  three album IDs read as empty on every song.
- **`storeItemID` follows `cloud status` exactly.** It is set on every subscription (787),
  purchased (464) and no-longer-available (50) song, and on 3,367 of 3,371 matched songs. It is
  never set on an uploaded (3,307) or unknown (106) song. That is 4,888 of 8,310 songs (59 %).
  ITLibrary lists 220 more songs than Music's library playlist does, all Apple Music or HLS
  kinds. Why they are missing from the playlist was not investigated.
- **A purchase's ID is usually out of date.** Apple re-issues albums under new IDs, and the
  purchase keeps the old one. The user's U2 New Edit, bought on *U218 Singles*, has
  `storeItemID` 205162007, which the lookup API no longer knows. The same edit is now
  1440729868. In random samples of 150 songs, the IDs that resolved in the Irish store were
  145 subscription, 140 matched, and only 32-44 purchased. The purchased figure is a range, not
  a measurement: two identical queries to the lookup service returned 32 and then 42. Adding
  the UK and US stores raised it only to 44.

### Twelve songs from a station

With playback allowed, 12 consecutive songs from the station were skipped through, and each
was checked against the library three ways. All 12 were `URL track`s. The station played
deluxe and remastered editions, such as *Urban Hymns (Deluxe / Remastered 2016)* and *(What's
The Story) Morning Glory? (30th Anniversary Deluxe Edition)*.

| Check | Songs with a library copy |
|---|---|
| Catalog ID (MediaRemote) equals a library `storeItemID` | 0 |
| Exact name, artist and album (StarBar then) | 1 ("Burn the Witch") |
| The loose key below | 7 |

The user owned the original release of most of these songs, not the deluxe edition, so the IDs
differed. Five of the seven loose matches were within 2 s: "Live Forever", "Beetlebum",
"Bigmouth Strikes Again", "Castle on the Hill" and "Wonderwall". The other two were within
7 s: an uploaded copy of "Burn the Witch", and "With or Without You" from *U218 Singles*.
"Castle on the Hill" is one of the 220 songs ITLibrary lists and Music's library playlist does
not, so a lookup through Music would find six.

**Driving playback for a measurement changes play statistics.** Skipping through a station
touched no library song. But playing a library song for 4 s, pausing it and then playing
another library song counted a skip on the first: its `skipped count` rose by one and its
`skipped date` became the time of the switch. `played count` did not change. The last song,
which was only paused, gained no skip. So it is starting the next track that counts the skip,
not the short play. Sample with catalog tracks, or stop after one library song.

### Loose matching against the library

A prototype key: the artist, folded to lowercase ASCII, without a leading "The" or a "feat."
clause, plus the title with its release annotations removed. The album is ignored. Only two
kinds of annotation are removed:

- **Release packaging:** remaster and remastered, with or without a year, bonus track, LP
  version, original version, mono, stereo, deluxe.
- **Edits:** radio edit, single version, single edit, edit, new edit, radio version, 7" version.

Live, remix, demo, cover, acoustic, instrumental, "Part 2", "Reprise" and anything unrecognised
stay in the key, because they are a different performance or a different piece.

Across the library:

- The 8,090 songs give 7,603 keys. **424 keys match more than one song** (911 songs in all).
- The spread of durations within a key: 180 within 3 s, 81 within 15 s, 86 within 60 s, 77
  more than 60 s.
- **Within 3 s, the matches are nearly always one recording.** In a random sample of 25 keys
  whose songs came from different albums, 23 were one recording on different releases. The
  two that were not were a live session with exactly the album take's length and a radio
  session released on a compilation.
- **Beyond 60 s, matches are mostly other performances whose titles do not say so.** Examples
  are live albums (*Pulse*, *Live at CBGB's*, *I Might Be Wrong*) and full-length against
  single edits. A few are different pieces with the same name: "Terran Theme 4" from two
  StarCraft games and "Finale" from two Halo soundtracks.
- **The artist is essential.** 370 cleaned titles are shared by different artists, for
  example "Intro", "One" and "Time".
- **The user's own copies often disagree.** Where a key has two or more user ratings, they
  differ in 28 of 62 keys within 3 s, 14 of 19 within 15 s, 33 of 37 within 60 s and 23 of 31
  beyond. So "your rating for this song" is often not one number.

The key joins the U2 case: both titles clean to "where the streets have no name". It lands in
the widest band, with a 50 s gap.

The figures above compare library songs with each other. The direction StarBar needs is from
catalog to library, so the same key was run over the public catalog's versions of 8 songs the
library holds in several versions. Those songs were by U2, Pink Floyd (2), The Smiths (2),
Radiohead, Curtis Mayfield and Daft Punk, giving 106 catalog rows:

- **50 rows had a library copy within 3 s, and the nearest copy was always the same
  recording.** In 6 of them the 3 s window also held a different recording: the Smiths' John
  Peel session "This Charming Man", 3 s longer than the single. So rank candidates by the gap.
  Do not treat the window as a set of equal matches.
- **2 rows matched within 15 s**, both remasters of the same recording.
- **8 rows matched only more loosely.** Two were the U2 album version against the user's New
  Edit, which is the case the user wants. Three were *The Wall*'s "Comfortably Numb" against
  the *Echoes* edit of the same recording. Three were wrong: Curtis Mayfield live recordings
  whose titles do not say so, from *The Berlin Sessions* and *Live In Europe*.
- **46 rows matched nothing.** Every row labelled live, remix, demo, session or re-recording
  was correctly excluded, including the 2023 U2 re-recording. So were four edit spellings the
  prototype does not know: "New Edit U218", "Edited Version", "Full-Length Version" and
  "Extended Version". Those misses are safe ones, because they only lose a suggestion.

### Cost

A bulk read of 14 properties for all 8,093 tracks takes 0.98 s. That is one Apple Event per
property, not per track. A `whose artist is "U2"` query that reads three properties of the 19
matching tracks takes 17-131 ms. A per-song candidate lookup scoped by artist is cheap enough to
run once per song, so it needs no index and cannot go stale.

### What this suggested

These were the proposals on 2026-09-23. The first was built on 2026-11-16, in the form
cross-app-matching.md describes, and the second still holds. StarBar links the copy the
matcher finds without naming it or asking, so the third and fourth have not been built, nor
has the fifth.

1. **Metadata is the only supported route, and it covers the U2 case.** Identifiers help only
   when the user's copy *is* the catalog item under another name. Both routes to them are
   private interfaces, and they matched none of the 12 station songs. Name, artist and
   duration found 7 of the 12, against 1 for the exact match StarBar used then. A lookup through
   Scripting Bridge cannot see the 220 Apple Music songs that are missing from the library
   playlist. Those are the songs most likely to be playing from the catalog.
2. **Keep the exact match automatic.**
3. **Treat a same-recording match as a strong candidate, not a certainty.** From catalog to
   library, the nearest copy within 3 s was the same recording in all 50 rows. But 50 rows of 8
   songs is a small sample, and a wrong link overwrites a rating that cannot be restored. Name
   the copy wherever its stars appear, for example "Your copy · U218 Singles", so a wrong link
   is visible before anything is written.
4. **Offer looser matches for the user to confirm, and remember the answer.** For example, a
   menu item: "Rate your copy: Where the Streets Have No Name (New Edit), U218 Singles, 4:46,
   ★★★★". Key the answer by the catalog song's name, artist, album and duration. A catalog
   track's database ID changes between reads, and nobody has measured whether its persistent
   ID survives a replay.
5. **Where copies disagree, list them.** Do not pick one silently. Of the 149 keys whose
   copies carry two or more user ratings, 98 disagree.

The reverse direction needs nothing for ratings, because a library song can always be rated.
The same key could still show that other copies exist, such as the 424 keys above. It could
also offer to give them all one rating.
