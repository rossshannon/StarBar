# Last.fm: how StarBar scrobbles

**Tried against the live service on one day, 2026-11-16**: one sign-in, a "now playing", sixteen Music songs scrobbled and two hearts loved, from a build that took the key and secret out of a 1Password `.env`. "The first live run", near the end, says what was seen. Everything else said about Last.fm's API is from its documentation at last.fm/api, checked on 2026-11-13, and from how other desktop scrobblers are known to work, and is not measured. Where a fact matters, it says which kind it is. "Still to measure" lists what is left; replace each guess here with what was seen, dated, as `docs/spotify.md` does.

The code is in `StarBar/Lastfm/` and `StarBar/Helper/PlayTracker.swift`. The short rules for anyone changing it are in `AGENTS.md`, under "Last.fm".

## What was decided, and why

- **Music is scrobbled once the user connects.** That is the point of the feature, and Music has no Last.fm link of its own.
- **Spotify only when "Scrobble songs played in Spotify" is on, and it is off by default.** Last.fm can link to a Spotify account itself and then scrobbles Spotify on its own servers. Most Last.fm users who use Spotify have that link, and StarBar scrobbling as well would count every Spotify song twice. The checkbox's tooltip says so.
- **Hearts become loved tracks.** A heart set or cleared in StarBar loves or unloves the song on Last.fm, and a song whose heart is already set is loved when it scrobbles. Nothing is ever unloved on its own: a song that simply isn't a favourite says nothing about whether the user loved it on Last.fm. One checkbox, "Love songs on Last.fm when I favourite them", on by default, turns all of it off.
- **Users never enter an API key.** StarBar's key and shared secret are put in at build time, as Spotify's client ID is built in (`SpotifyAuth.builtInClientID`). Asking each user to register an API account was ruled out for the same reason it was for Spotify.
- **No polling of either player.** The one new read of Music is `PlayTracker.Effect.checkPosition`, described below.
- **"Pause Scrobbling" is kept between launches** (`UserDefaults.lastfmPaused`), so an update or a restart doesn't quietly resume it.
- **A hidden dry run** (`lastfmDryRun`) logs what would be sent and sends nothing, with no sign-in, so the whole path can be watched without touching anyone's profile.

## The API as used

All from Last.fm's documentation (2026-11-13).

- **One endpoint**, `https://ws.audioscrobbler.com/2.0/`. Every call StarBar makes is a POST, form-encoded as UTF-8, with `format=json`, and is signed. The method is a parameter (`method=track.scrobble`). `LastfmAPI` builds the requests and reads the answers and is pure; `LastfmClient` sends them over the same injectable transport as `SpotifyLibrary`.
- **Signing.** `api_sig` is the MD5, in lowercase hex, of every parameter except `format` and `callback`, sorted by name, run together as name then value with no separators, then the shared secret. It is not OAuth. **The sort is by the names' UTF-8 bytes, not alphabetical in any locale-aware sense**: in a batch of eleven or more scrobbles, `artist[10]` comes before `artist[1]`, because "0" (0x30) sorts before "]" (0x5D). A signature made in any other order is refused with error 13, and only for batches of more than ten, so it would pass every small test. `LastfmAPITests` pins it.
- **Encoding.** Percent-encoding leaves only letters, digits, `-`, `.`, `_` and `~` alone, so a `+` or `&` in a song's name doesn't arrive as a space or a separator. The signature is over the values before encoding.
- **Errors** come back as `{"error": 9, "message": "..."}`, usually under an HTTP 4xx, so the body is read whatever the status and its code decides (`LastfmAPI.failure(data:response:)`). The codes that matter: 4 authentication failed, 6 invalid parameters, 8 operation failed, 9 invalid session key, 10 invalid API key, 11 service offline, 13 invalid signature, 14 token not authorised, 15 token expired, 16 temporarily unavailable, 26 suspended API key, 29 rate limit exceeded.
- **Numbers sometimes arrive as strings** (`"accepted": "1"`), according to the documentation's own examples, so every number is read either way.
- `track.updateNowPlaying`: artist, track, and album, albumArtist, trackNumber and duration (whole seconds) when known.
- `track.scrobble`: up to 50 at once, as `artist[0]`, `track[0]`, `timestamp[0]` (UTC seconds since 1970, when the song **started**) and the same optional fields. `chosenByUser` is left out, which Last.fm reads as the user's own choice. The answer counts `accepted` and `ignored`, with an `ignoredMessage` code for each (1 artist, 2 track, 3 timestamp too old, 4 too new, 5 daily limit); `scrobble` in it is one object for one scrobble and an array for several.
- `track.love` and `track.unlove`: track and artist. They answer `{}`.

### Signing in: the desktop flow, by polling

Last.fm has no OAuth. Its desktop flow:

1. `auth.getToken` answers a token, good for 60 minutes and for one session.
2. The user approves it at `https://www.last.fm/api/auth/?api_key=KEY&token=TOKEN`, which StarBar opens in an `ASWebAuthenticationSession`, so the password goes to Last.fm's own page and never through StarBar.
3. `auth.getSession` with the token answers `{"session": {"name": ..., "key": ..., "subscriber": 0}}` once the user has approved, and error 14 until then. Error 15 means the token expired, 4 that it is no good.

StarBar asks `auth.getSession` every `LastfmAccount.pollInterval` (2.5 s) while the page is open, for at most `pollLimit` (10 minutes), and closes the page itself when the session comes. If the user closes the page, one last ask is made in case they allowed access first.

**Why it polls rather than waits for a callback.** Last.fm's web flow takes a `cb` parameter, a page to send the browser to with the token, but its documentation doesn't say whether `cb` may be a custom URL scheme such as `starbar://`, and an approval page that went nowhere would leave the user stuck. The desktop flow's documentation says the token stays good after an error 14, so asking until it is approved is the documented way. **It held on 2026-11-16**: the first live sign-in came through by polling, with no error logged. How many asks went before the session came was not logged then; the line "Last.fm allowed access on ask N" says so now.

**The session key never expires**, by the documentation. It ends only when the user removes StarBar under Applications in their Last.fm settings, which a call then reports as error 9. It is kept as a 0600 JSON file per API key in `Application Support/Lastfm`, inside the app's container (`FileLastfmSessionStore`), and not in the Keychain, for the reason `docs/spotify.md` gives: every ad hoc update brought up a Keychain prompt.

## When a play counts

`PlayTracker` decides, one per player, and is pure: it is told what the player said and what time it is, and answers with what to do (`.nowPlaying`, `.scrobble`, `.checkPosition`). `PlayTrackerTests` covers it. The rule is Last.fm's: a song longer than 30 seconds counts once it has played for half its length or four minutes, whichever is sooner; one with no known length counts at four minutes.

- **"Played" is time spent playing.** A pause doesn't count and a seek neither adds nor takes away. Only time StarBar saw counts: a song already halfway through when StarBar opens starts from zero.
- **Two clocks.** The wall clock (`Date`) gives only the time a play started, which is what Last.fm is sent. Time played is measured on `ProcessInfo.systemUptime`, which stops while the Mac sleeps and never jumps when the clock is set, so a Mac that sleeps mid-song doesn't scrobble the song on waking.
- **A play survives a pause and the bare Stopped** that Music sends between songs, and is replaced when the player names another song.
- **"Now playing"** is sent 2 s into each stretch of playing, so skipping through a run of songs doesn't announce each one. It is never kept or retried: the next song says it again. Seen once, 2026-11-16: a song that started at about 17:13:45 was "Scrobbling now" on Last.fm's site in a screenshot taken at 17:14:07. How long Last.fm shows it without a scrobble is not known.
- **The last play scrobbled** is kept with the queue, per player (`PlayTracker.Earlier`), so a song still playing when StarBar opens again isn't scrobbled twice.

**A song that starts again is a new play**, and neither player says when that happens (measured for Music in `AGENTS.md`'s track announcement section, and for Spotify in `docs/spotify.md`). Three things catch it:

1. **A position in an update.** Spotify's notification carries one. Far behind where the play should be and near the start is a restart; far behind and not near the start is a seek back; far ahead is a seek forward.
2. **`.checkPosition`.** When a Music song should have ended a few seconds ago and Music has announced nothing else, the scrobbler reads Music once: the position, whether it is playing, and whether it is the same song. That is the only read of a player's position the scrobbler makes. It waits while the strip or the menu bar is moving, as the station's own re-reads do. After three reads in a row that settle nothing, it stops asking until Music's next notification, so a Music stuck "playing" is never polled.
3. **The strip's restart watch**, which posts `.musicSongDidRestart`. It runs only while track announcements are on.

**Known limits, accepted.** A restart part-way through a song counts only if one of those catches it, so Music's Previous at 3:00 of a 4:00 song, with announcements off, is one play rather than two. A Spotify song on repeat is one play unless Spotify posts when it loops, which has not been measured; Spotify is never asked for its position.

## The queue, retries and failures

What is waiting is a `ScrobbleQueue` per user, a 0600 JSON file in `Application Support/Lastfm`, written off the main thread. It holds scrobbles, oldest first, hearts to send, and the last play scrobbled per player. **Nothing leaves it until Last.fm has answered for it.** A scrobble more than 14 days old is dropped rather than sent, since Last.fm's documentation says it ignores those, and so is the oldest past 5,000.

`LastfmScrobbler` sends one request at a time: scrobbles first, oldest first, in batches of 50, then hearts. What each failure does:

| Failure | Codes | What happens |
|---|---|---|
| `.network` | no answer | Kept. Tried again after 1, 5, 15 and then every 60 minutes; at once on the next scrobble, a wake from sleep, the network coming back, a new sign-in or a launch |
| `.temporary` | 11, 16, 29, or HTTP 5xx | The same |
| `.sessionInvalid` | 9 | The sign-in is dropped and Preferences asks the user to connect again. **The queue is kept**, for when the same user connects again |
| `.credentialsRejected` | 10, 13, 26 | Nothing more is sent until the app opens again or the account changes. The queue is kept |
| `.refused` | anything else | Last.fm will never take it, so it is dropped, with an error in the log, and sending carries on |

Last.fm's guidance is to retry only on 11 and 16 and on no answer. StarBar adds 29, the rate limit, because waiting is the answer to it too.

**A batch that succeeded leaves the queue whether Last.fm accepted or ignored each scrobble**: an ignored one would be ignored again. A success whose summary can't be read is taken as all accepted, because the scrobbles reached Last.fm and sending them again would double them.

**Disconnect deletes the queue; a rejected session keeps it.** Disconnect is the user saying to stop, and Preferences and the privacy policy say it deletes what was kept. A session Last.fm rejected is usually the user removing access by mistake or Last.fm resetting it, and connecting again should lose nothing.

## Hearts

A heart set or cleared in StarBar (`LastfmScrobbler.userDidSetHeart`) is queued as a love or unlove and sent after the scrobbles. A newer change for the same song replaces one still waiting, so a heart set and cleared while offline sends only where it ended up.

A song whose heart is already set is loved as it scrobbles, read once through `LastfmSources.isFavorited`: the heart of Music's own track (from the copy the heart belongs to, `PlayingTrack.favoriteTrack`), or for Spotify the user's copy in Music when one is matched, else the Spotify like when signed in. An unknown answer loves nothing. Songs loved this way are remembered for the launch (256 of them), so a favourite played again isn't loved again.

## The key and the secret

- **The API key** is public by design: it is in every request and in the approval page's address. It is kept out of the repository all the same, beside the secret, so that the two come from one place and can't drift apart (Ross keeps both in one 1Password Environment, 2026-11-13).
- **The shared secret** signs requests and is not in the repository either.
- **Where a build finds them.** `build.sh` takes `LASTFM_API_KEY` and `LASTFM_SHARED_SECRET` from the environment, then from the lines of those names in an env file, each value from the first place that has it: the file `STARBAR_SECRETS_FILE` names, `.env` beside the script, `.env` in the main checkout when the build is in a git worktree of it (so one file serves every worktree), then `~/.config/starbar/secrets.env`. A file is read and never sourced. It conceals both, writes `build/StarBarSecrets.xcconfig` (0600) with the settings `STARBAR_LASTFM_KEY` and `STARBAR_LASTFM_SECRET`, and passes that file to `xcodebuild` with `-xcconfig`. `Info.plist` holds them under `LastfmAPIKey` and `LastfmSharedSecret`, and `LastfmCredentials.current()` reveals them. The release workflow sets both variables from repository secrets; pull request builds run without them on purpose, since their logs are public and their code is anyone's.
- **A `.env` mounted by 1Password is a named pipe**, not a file: 1Password passes the Environment's variables to whoever opens it and nothing is stored on disk. Opening it waits until 1Password is unlocked and the read approved, which lasts until 1Password locks again, and 1Password's documentation doesn't say what a locked or declined read does. So the script never opens one itself: a helper does, and copies its lines into a pipe of the script's own, where the read is given up after `STARBAR_ENV_WAIT` seconds (60 at a terminal, 10 otherwise) and the build goes on without Last.fm. Without that, a build nobody is watching, such as one a Remote Control session runs with the screen locked, would wait for ever. Such a file isn't meant to be read by two processes at once. **It met 1Password on 2026-11-16**: a `./build.sh --install` run by hand in a worktree took both values from the `.env` 1Password mounts in the main checkout, and the installed copy signed in to Last.fm with them. Only a read that 1Password answered has been seen. A locked 1Password, a declined read and a build with nobody there are still covered only by the check below, which drives the reader with a pipe of its own, released late and never released.
- **Never on a command line or in a log.** CI logs are public, a failed build prints its whole log, and anything in a process's arguments can be read by other processes. So the script does the work with shell builtins, hands the values to Xcode through the file rather than as build settings on the command line, and takes the concealed values out of `xcodebuild`'s log before printing any of it, since `xcodebuild` echoes the settings it read from an `-xcconfig` file. The pad is in the public repository, so a concealed value is as good as the value.
- **The check.** All of this is in `Scripts/lastfm-credentials.sh`, which `build.sh` sources, so that `Scripts/test-lastfm-credentials.sh` can run the same functions with made-up values: an env file's quotes and line endings, the order of the sources, a worktree, the xcconfig's contents and mode, that nothing printed holds a value plain or concealed, the log's redaction, and both pipes. `./build.sh --test` runs it first, under `/bin/bash`, so CI runs it on every push under macOS's bash 3.2, which is where `read -t`, process substitution and the second pipe could differ from the bash it was written with. Every case runs in an empty temporary folder with `HOME` pointed there, so it never opens a real `.env`, and a case still running after its limit fails rather than hangs. Its worth was checked on 2026-11-13 by putting 18 bugs into the library one at a time (no redaction, a printed value, a wrong pad, a read with no time limit, a helper left behind, and so on): each failed it. Do the same for a case added there.
- **What the concealment is worth.** Each value's bytes are XORed with a fixed 16-byte pad and stored as hex. That keeps it out of `strings` and out of a search of the bundle for the secret, and nothing more: anyone with the binary and this repository can recover it. Every desktop scrobbler ships its secret in some form. What it lets someone do is sign requests as StarBar: scrobble to their own account under StarBar's name. Acting for any user also takes that user's session key, which the secret doesn't give.
- **Overrides.** The hidden defaults `lastfmAPIKey` and `lastfmSharedSecret` replace the built-in ones, for someone with an API account of their own or for a build made without StarBar's. A secret alone pairs with the built-in key; a key alone pairs with the built-in secret, which belongs to another key, so Last.fm refuses every signature (error 13). Sessions are kept per API key.

## The dry run

With `lastfmDryRun` on, the scrobbler runs as if signed in, as the user `dry-run`, and everything goes to `DryRunLastfmSender`, which logs one line for each request it would have sent ("Last.fm dry run: would scrobble ...", and the same for "now playing" and loves) and answers as Last.fm would. No key, secret or sign-in is needed, and nothing touches the network. It has its own queue file, under the `dry-run` user.

```bash
defaults write com.rossshannon.starbar lastfmDryRun -bool true
# quit StarBar and open it again, play some songs, then:
/usr/bin/log show --last 30m --predicate 'process == "StarBar"' | grep -i "last.fm"
defaults delete com.rossshannon.starbar lastfmDryRun
```

Read the default back with `defaults read`, not from the plist file, which is written later (see `AGENTS.md`). `log` on its own is a zsh builtin, hence the full path. The log keeps StarBar's lines for about half a day.

To try one copy without touching the default, which every copy of the app shares, pass it as a launch argument: `open -n -g <the built StarBar.app> --args -lastfmDryRun YES`. **Tried once, 2026-11-13, on macOS 27**: a worktree's Release build run that way beside the installed copy logged "Last.fm queue now for dry-run, 0 waiting" and "Last.fm scrobbler started, active", stayed up for 70 s with nothing playing, and opened neither Music nor Spotify. No song played, so no "would scrobble" line, and no queue file, has been seen yet. Search the log for "Last.fm", with the dot: a worktree named for the feature puts "lastfm" in LaunchServices' lines too.

## Testing beside another scrobbler

Two scrobblers on one account double every play, and a scrobble can't be taken back from StarBar (Last.fm's site can delete one by hand). So:

1. Start with the dry run, and compare its log with what the other scrobbler sends.
2. Then either pause the other app while StarBar runs live, or connect StarBar to a second Last.fm account made for testing.

Never run both live on the same account.

## The first live run (2026-11-16)

One sign-in and the evening that followed it, on the Mac the dry run was tried on, with a Release build of this branch installed (1.9.0, build 465), which ran from 17:11 to about 21:14 and again from 21:16. All of it was read afterwards, from the app's log, its folder, Music, and three screenshots of the profile on Last.fm's site; nothing was played or posted for it.

- **The build had both values.** Its `Info.plist` held `LastfmAPIKey` and `LastfmSharedSecret`, 64 characters each, which is 32 concealed bytes, and `build/StarBarSecrets.xcconfig` was 0600. To see which build is installed without printing either value, read their lengths.
- **Sign-in.** "Last.fm scrobbler started, inactive" at launch, then "signed in to Last.fm as ..." and "Last.fm queue now for ..., 0 waiting" 104 s later, with the session file written 0600. So `auth.getToken`, the approval page and a polled `auth.getSession` work on the real service, signatures included. Not seen: how many asks went before the session came, and what the approval page did afterwards.
- **Now playing.** The first song, which started at about 17:13:45, was "Scrobbling now" on Last.fm's site in a screenshot taken at 17:14:07. That build logged nothing for a "now playing" that worked, so what showed the entry was StarBar's was that the Mac's other scrobbler wasn't running. `LastfmClient` logs "Last.fm now playing set" since.
- **The scrobble.** The song was 298.9 s long. "queued a scrobble: Sade, Smooth Operator, from music, 1 waiting" came between one and four seconds after its halfway point (Music's position, read twice afterwards with the time taken to the second, put the song's start two seconds apart). "Last.fm took 1 scrobbles and ignored 0" followed 0.26 s later, and the queue file was written 0600 with nothing waiting. **That build's log can't say whether the 1 was read from Last.fm's answer**: an answer that worked but whose summary can't be read is counted as accepted too, in the same words. The call worked either way, an HTTP 2xx with no `error` in it, and an unreadable summary is logged as an error since.
- **The profile, 46 minutes on.** A screenshot of Recent Tracks taken at 17:59:52 showed eleven songs since the sign-in, the first of them the song above, each once, with no other entry between them. **The time on each is when the song started, not when it was scrobbled**: "Hey Jude" (about 7:10 long) was seven minutes before the next song, where the moments the two were scrobbled would be about five and a half minutes apart, and the other gaps were three to five minutes, as songs played back to back give. So a song following another is tracked as a new play, and `timestamp` arrives as sent. None was shown as loved.
- **Titles arrive as Music has them**: "Yesterday (Remastered 2009)" and "Hey Jude (Remastered 2009)" were listed under those names. Nothing is folded before a scrobble.
- **The log, four hours on.** Read at about 21:05 and again at about 21:13: sixteen "queued a scrobble" lines between 17:16:16 and 21:09:58, each "from music", and each followed within a second by "Last.fm took 1 scrobbles and ignored 0" and "1 accepted, 0 ignored, 0 waiting". No line said Last.fm couldn't be reached, or had refused or rejected anything, so no retry has run. Nothing is logged for a position read, so whether one was made isn't known.
- **Songs streamed from the Apple Music catalogue scrobble as library songs do.** Asked by name and artist afterwards, Music had no library track for nine of the first fourteen songs, and none of the other five had a play counted that day, so what played was the catalogue's track in each case, as far as that shows.
- **A heart set in StarBar is loved at once.** At 21:03:15 and 21:04:01 a heart was clicked in StarBar for the song playing: "queued a Last.fm love: ..., 1 waiting", then "Last.fm loved: ..., 0 waiting" 0.19 s and 0.15 s later. A screenshot of the profile taken about then showed the second song with its heart filled while it was still "Scrobbling now", so a love shows on the site for a song not yet scrobbled. The first song was left within a minute and never scrobbled, and Last.fm answered for its love the same way.
- **A song hearted and then scrobbled is loved once.** The second song scrobbled at 21:05:56, two minutes after its heart was set, and Music read it as a favourite afterwards. No "for a favourite as it scrobbled" line followed: the click had already counted it as loved for this launch.
- **A favourite loved as it scrobbles has not run.** No scrobble brought that line, and none was owed one, as far as can be told: of the fifteen other songs, the five with a copy in the library were not favourites when Music was asked that evening, and the rest had no copy to ask about. A catalogue track's own heart can't be read once it has stopped playing. One song on the profile showed as loved with no love for it in the log ("Movin' Out (Anthony's Song)", not in the library), so Last.fm had it loved already.
- **Two quiet stretches.** Nothing was scrobbled between 18:06:25 and 19:19:12, or between then and 21:05:56. That build logs nothing when a song starts, so its log can't say whether anything played. Music's library can, in part: no library track had a play or a skip counted in either stretch, and a skip was counted at 19:16:40 and at 21:03:11, each just before the scrobbles and hearts pick up again, which is what playing starting again looks like. A stream of a song that isn't in the library leaves no such trace, so a missed scrobble of one isn't ruled out. Builds since log "Last.fm now playing set" two seconds into every song, which would show one.
- **A relaunch keeps the sign-in.** The copy was quit at about 21:14 for another test and opened again at 21:16:03: "Last.fm scrobbler started, inactive", then "signed in to Last.fm as ..." and "Last.fm queue now for ..., 0 waiting" half a second later, read from the session file, and the next song was scrobbled and accepted at 21:20:54. A song that reached its halfway point while the copy was away would be missing from the profile; none was looked for.
- **The log.** Every line above is at the default level, so `log show` has them without `--info`. Search for "Last.fm", and read it the same day.

Not exercised, as far as is known: a heart cleared (an unlove), a favourite loved as it scrobbles, a pause, a restart and the position read, the queue's retries and anything offline, an error of any code, a batch, Disconnect, Pause Scrobbling, and Spotify. The two quiet stretches may each have begun with a pause; nothing shows it.

To see what Music itself counted, ask it for the library tracks whose `played date` or `skipped date` is later than a time, and read only the properties wanted: never `location` or `properties`, which make it announce a library change (see `AGENTS.md`). In AppleScript `since` is a reserved word, so the time needs another name.

## Still to measure

- How many asks of `auth.getSession` go before a session, and does Last.fm ever mind one every 2.5 s? The first sign-in worked; "Last.fm allowed access on ask N" counts them from now on.
- What does Last.fm's approval page do once access is allowed: does it stay open, and does anything try to send the browser on? The same line says whether the page was still open when the session came.
- Does error 9 arrive as an HTTP 403, and do the other errors come under the statuses expected?
- Do numbers in the answers arrive as strings, as numbers, or both?
- How long does Last.fm show a "now playing" before it lapses without a scrobble?
- Does Spotify post a notification when a song loops on repeat?
- Does a batch of more than ten scrobbles sign correctly (the `artist[10]` ordering) on the real service?
