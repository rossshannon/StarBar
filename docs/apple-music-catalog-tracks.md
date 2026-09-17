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

## Open question

Whether the favourite on a catalog track reaches the user's Apple Music account or only the
session. Setting it on a streamed copy of a song that was also in the library left the library
copy reading as favourited, but it may have been favourited already — untested either way.
