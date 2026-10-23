# Spotify: what the desktop app sends and answers

Measured 2026-10-21 on macOS 27.0.1 with Spotify 1.3.5.3058, from a standalone listener (proved first with a test post from another process) and `osascript`. These are the facts StarBar's Spotify support is built on. Re-measure before relying on anything here for a different Spotify version.

## The notification

Spotify posts one distributed notification, `com.spotify.client.PlaybackStateChanged`, with object `"com.spotify.client"`. No other name fired.

A song or episode's payload always has the same 13 keys:

| Key | Type | Notes |
|---|---|---|
| `Name`, `Artist`, `Album` | String | An episode has an **empty** `Artist`; its `Album` is the show |
| `Album Artist` | String | Empty for songs; the show for episodes |
| `Track ID` | String | `spotify:track:…`, `spotify:episode:…` |
| `Player State` | String | `Playing`, `Paused`, `Stopped` |
| `Has Artwork` | Bool | |
| `Duration` | Int | Milliseconds (213560) |
| `Playback Position` | Double | Seconds |
| `Disc Number`, `Track Number`, `Popularity` | Int | 0 for episodes |
| `Play Count` | Int | Always 0 |

There is no artwork in the payload, and nothing that marks Spotify Connect playback or an ad. Ads were not captured (no free account to hand), which is why StarBar announces by an allow-list of Track ID prefixes.

### When it posts

- **Posts**, about 0.6 to 1.1 s after the command: play, pause, resume, next track, `play track` with a URI, previous track in the first ~3 s of a song.
- **Posts nothing**: a seek (setting `player position`), previous track after ~3 s (which restarts the same song), play while already playing. So a restarted song cannot be detected from the notification.
- **Quit**: one payload with `Player State = Stopped` and no other key.
- **Launch**: a second bare `Stopped` about 4.5 s after launch, then a `Paused` payload at position 0 for a stale "last played" song that was not the one playing at quit. Pressing play then posted `Playing` for the song from before the quit, at a position about 10 s past where it was, apparently the account's server-side state.

An AppleScript read made straight after a command often still answers with the state from before it.

## AppleScript

Reads one property at a time from `current track`:

- Work: `name`, `artist`, `album`, `id` (the URI), `track number`, `disc number`, `played count` (0), `popularity`, `duration` (milliseconds, although the sdef says seconds), `artwork url`, `spotify url` (the URI, not an https link).
- `album artist` is an empty string.
- `starred` always fails with -10000, "AppleEvent handler failed", so `properties of current track` fails too.
- `id of current track` fails with -1700 just after launch, before anything is loaded.
- `player state` and `player position` (a real, seconds) work. A `player position` read from a fresh `osascript` process took 159 to 367 ms, median 173 ms, mostly process start.

`artwork url` is on `i.scdn.co`; the image is a 640×640 JPEG of about 130 KB, for songs and episodes alike.

### Sandbox access groups

Spotify's sdef declares access groups, so a sandboxed app can use `com.apple.security.scripting-targets` rather than a temporary exception:

- `com.spotify.playback` on the application class and on next track, previous track, playpause, pause, play and play track.
- `com.spotify.library` (read only) on the track class.
- `*` on the Standard Suite.

StarBar asks for `com.spotify.playback` (to read `current track` and `player state`) and `com.spotify.library` (to read the track's properties).

## Opening a song

`open spotify:track:…` drives playback rather than showing the song, and not consistently. Spotify never came to the front.

- A different song while paused: jumped to it and played from 0.
- A different song while playing: nothing; opening it again paused playback.
- The song already loaded, while playing: once it paused, once nothing.
- The song already loaded, while paused: restarted from 0 and played.
- An album URI: nothing.

The sdef has no command that only reveals a song, so the menu bar's Spotify heart brings Spotify to the front instead.

## Liking songs: the Web API

AppleScript can't like a song, so StarBar 1.7 uses Spotify's Web API. Facts from Spotify's documentation as of 2026-10-23, not yet measured against the live API:

- Since February 2026 the library endpoints take URIs of any type: `GET https://api.spotify.com/v1/me/library/contains?uris=…` answers an array of booleans, and `PUT` and `DELETE` on `https://api.spotify.com/v1/me/library?uris=…` save and remove. `uris` is a comma-separated query parameter, at most 40. The Track ID in the notification is such a URI already.
- Scopes: `user-library-read` for `contains`, `user-library-modify` for saving and removing.
- An app in Development Mode serves at most five users, its owner needs Premium, and the request quota is per app. A 429 carries `Retry-After`; an exhausted quota says `QUOTA_EXCEEDED`.
- Sign-in: Authorization Code with PKCE, so no client secret. Redirect URIs must be https or a loopback IP, but "redirects using a custom scheme will still be supported", which is what `starbar://spotify-callback` relies on.
- Access tokens last an hour (`expires_in: 3600`). A refresh may or may not return a new refresh token.

To check during the first live test: whether a bodiless `PUT` gets 411 (StarBar sends an empty body to be safe), whether `contains` on an episode works, and whether the ad hoc build asks for the Keychain after each update.

Measured 2026-10-23 on the first live test: sign-in, `contains`, like and unlike all worked. Reinstalling an ad hoc build **did** bring up a Keychain prompt (securityd: "displaying keychain prompt for /Applications/StarBar.app"), so the tokens moved to a file in the app's container.

The client ID is built in, so users only press Connect: asking each user to register a developer app, which also needs Premium, was rejected. The cost is Development Mode's cap of five accounts, added by hand on the dashboard. Moving past it needs Spotify's Extended Quota, which since 2025 is granted only to organisations.
