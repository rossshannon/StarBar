# Privacy Policy for StarBar

StarBar has no accounts, no analytics, no crash reporting and no update check, and it keeps nothing about you anywhere but your Mac. It goes online for two things only: cover art, from Apple or Spotify, and, if you connect your Spotify account, liking Spotify songs.

This page lists everything StarBar reads, changes, keeps and sends. It was last updated in November 2026, for StarBar 1.9.0.

## What StarBar reads

- **From Music**: the playing song's name, artist, album, cover, rating and favourite. StarBar asks Music through Scripting Bridge, which is why macOS asks you to allow it under System Settings → Privacy & Security → Automation.
- **From Spotify**, if you use it: the playing song's name, artist, album and the address of its cover. macOS asks you to allow that under Automation too, the first time it's needed.
- **From your Music library**, when a Spotify song is playing and Music is open: the titles and artists of your songs, so StarBar can find your copy of the same song. It keeps that list in memory only, and reads it again only after Music says the library has changed.

These are conversations between apps on your Mac.

## What StarBar changes

Only when you click, drag or press one of its shortcuts:

- The rating and favourite of the playing song in Music, or of your Music copy of the Spotify song that's playing.
- Your Music library, when you click **Add to Library** for a song playing from the Apple Music catalogue: Music adds that one song, so it has somewhere to keep a rating.
- Your Spotify Liked Songs, if you've connected your Spotify account, when you click the heart.

StarBar doesn't edit file tags, rename or move files, or create or change playlists.

## What StarBar keeps on your Mac

- **Your preferences**, in the standard macOS preferences store for the app.
- **The last song from your library that Music played**: its name, artist and Music's ID for it. It's there so that pressing Play in the popover when Music has nothing loaded can start that song again. Each new song replaces it, so it is never a history.
- **Your Spotify sign-in**, if you connect Spotify, in a file inside StarBar's own sandbox container, readable only by you. **Disconnect** in Preferences deletes it.
- **The last few covers**, in memory while StarBar runs, so it doesn't fetch the same one twice.

Nothing else is kept: no record of what you've listened to and no copy of your library.

## What StarBar sends over the network

- **Covers for Apple Music songs you haven't added to your library.** When Music plays a song straight from the Apple Music catalogue and it isn't in your library, Music often gives StarBar the wrong cover or none at all. So StarBar asks Apple's iTunes Search service (`itunes.apple.com`) for the song, sending its artist and title and your Mac's region, which picks the store to search. It then downloads the cover from Apple's image server (`mzstatic.com`). Other songs from the same album then use the cover already fetched rather than asking again. The request goes to the company that is already streaming you the song. Songs in your library, including Apple Music songs you've added, never cause this request: their covers come from your library.
- **Covers for Spotify songs.** While a Spotify song is playing, StarBar downloads its cover from Spotify's image server (`i.scdn.co`). The request says only which cover is wanted.
- **Spotify likes, if you connect.** Press **Connect** in Preferences and StarBar signs in through Spotify's own page at `accounts.spotify.com`, so your password never passes through StarBar. After that it asks `api.spotify.com` once per new song whether that song is in your Liked Songs, and sends a like or unlike when you click the heart. None of this happens until you press Connect. To revoke the sign-in on Spotify's side as well, remove the app under **Manage apps** on your Spotify account page.

Like any request on the internet, each of these also reaches the server with your IP address. Nothing is sent anywhere but Apple and Spotify, and only for the purposes above. If you play only songs from your own library and don't use Spotify, StarBar makes no network requests at all.

## What StarBar never does

- There are no StarBar accounts and no licence server: the app is free and MIT licensed.
- There is no analytics, crash reporting or telemetry of any kind.
- There is no update check. New versions come from the [releases page](https://github.com/rossshannon/StarBar/releases) when you go and get them.
- Nothing about you is sold or shared.

## The website

StarBar's web pages at [rossshannon.com/starbar](https://rossshannon.com/starbar/) are separate from the app and use Google Analytics, which you can turn off. Their [privacy page](https://rossshannon.com/starbar/privacy/) explains what that means.

## Changes

If any of this changes, this page changes with it and the release notes say so. StarBar 1.9.0 added the request to Apple for covers, and remembering the last library song Music played.

Questions: [open an issue](https://github.com/rossshannon/StarBar/issues).
