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
song after a relaunch, so there was no previous cover to compare it with. With over half of
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
needs a developer token. Whether Music's `playerInfo` notification carries the catalog ID for a
catalog track (`PlayInfo` has a `storeURL` field for its `Store URL` key) has not been checked.
