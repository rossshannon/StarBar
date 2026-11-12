# I Love Stars animation inspection

Inspected the supplied I Love Stars 4.4.1 (build 73) executable and archived interface on 2026-09-21. This was static inspection, not a live reproduction. Executable SHA-256: `ebf762c2b18aa590d7d548e925dc11d2ea86f91b7324bee4c3c06e789aa5d98a`.

## Findings

- The rating strip's `show:` method slides its frame into place while animating `imageRotationDegrees`, using an ease-out curve over 0.5 seconds. `hide:` reverses the presentation and schedules the narrower status-item width after completion.
- The visible reveal is also called from playback notification handling, not only launch. Paused/stopped notifications take the hide path.
- There is a special `initialAnimation` flag when `hidesCompletely` is enabled. That launch path uses a vertical entrance and a 216-degree rotation. On completion it resets both indicators' rotation to zero and clears the flag. Normal horizontal entrance targets 216 degrees with the compact icon retained, or 360 degrees when it hides completely.
- The displayed rating comes from the current track's rating divided by 20, preserving half-star values. Its drawing code separates the integral and fractional portions. The Preferences interface explicitly includes “Enable half-stars ratings”. No forced five-star assignment was found in the traced setup/reveal path; the interface archive declares five as the maximum, not the current value.
- A shared rotated star image is drawn across the rating strip. This version slides the row as a unit while turning the glyphs; it does not use StarBar's independent, staggered per-star travel.

## Evidence locations in the x86-64 executable

| Method | Address | Evidence |
| --- | --- | --- |
| `PFStatusItemController setup` | `0x10001a0ed` | Reads hidesCompletely, sets initialAnimation, reads current rating, schedules playback processing, optionally calls show |
| `updateStarsWithTrack:` | `0x10001aac0` | Reads ratingKind and rating, divides rating by 20, sets indicator value |
| `animationDidStop:finished:` | `0x10001ac77` | Resets initial rotation and clears initialAnimation; delays sizeDown after hide |
| `animateWithName:targetFrame:rotationDegrees:duration:timingFunctionName:` | `0x10001ad7e` | Animates frame origin, image rotation and alpha |
| `hiddenFrame` | `0x10001b244` | Vertical entrance for animateVertically or initialAnimation; horizontal offset otherwise |
| `show:` | `0x10001b35a` | 69-point width, 216/360-degree rotation target, 0.5-second ease-out |
| `processiTunesNotification:` | `0x10001c809` | Playback-state decision chooses show/hide and updates the rating |
| `KITRatingIndicatorCell performImageRotation` | `0x100003ad3` | Rotates the common star image; multiples of 72 degrees share the upright appearance |
| `p_drawInteriorWithFrame:inView:` | `0x10000402d` | Reads integer and fractional rating, draws full/partial stars and remaining dots |

Temporary disassembly and the annotation script are under `tmp/ilovestars-inspection/`. No old executable code or assets were copied into StarBar.

## StarBar behaviour

StarBar uses the current song's actual rating, including half stars and unrated dots. The approved transitions are:

| Change | Animation |
| --- | --- |
| First library song after launch or Music quitting | The item widens and stays empty for at least 0.15 seconds, then the stars roll into place over 1.0 seconds |
| Add-to-library button to a rateable song | The same 1.0-second rollout |
| Different ratings on successive library songs | Changed glyphs retract or grow in place over 0.2 seconds; full/half stars blend |
| Library song to an Apple Music-only song, including deletion from the library during playback | Stars shrink and the heart fades (0.2 s), the item narrows while empty and waits for the menu bar's slide (0.35 s), then the add button and heart fade in (0.2 s); total 0.75 seconds |
| Music quits | Return to the compact stopped dot and rearm the next entrance |

Music sends a bare `Player State: Stopped` between some songs. Measured gaps were 50–131 ms, so a stopped notification cannot distinguish a song change from the end of a queue. The display session lasts until Music quits: hold the previous strip over missing-track updates and disable stale rating actions. No stop timer or additional Music polling is used.

Manual rating edits take effect immediately. Animation never writes intermediate values to Music. Reduce Motion bypasses transitions. Each animation starts its clock on the first display callback: synchronous Music reads have delayed that callback by 198–261 ms, which previously consumed the entire 0.2-second rating transition before any frames were drawn. From there each frame counts the time since the one before, but at most two frames' worth, so a held main thread pauses a transition instead of skipping part of it (see the last section).

## Heart overlay and the first fixed allocation

Both heart appearances use one independent right-aligned view. Menu-bar images reserve an empty heart slot with `drawsFavorite=false`; other consumers keep their usual embedded outline.

On macOS 27, the visible menu-bar resize moves the heart even when local view and presentation-layer coordinates remain almost unchanged. A standalone native status item reproduced about 60 pixels of leftward movement, including with standard animation controls disabled, intrinsic sizing, and a custom view. Preview images and local inset tests alone did not expose this.

The first workaround kept a 132-point allocation for both active modes and right-aligned the add button inside it, leaving 64 points unused on the left. Ross later asked for that space back.

## Giving the space back (2026-09-23)

Measured with a standalone probe that draws StarBar's glyphs in its own status item, placed among other apps' items, and recorded across the whole menu bar at 60 frames a second:

- Narrowing a status item draws it at its **old left edge**, then slides it and every item to its left into place over about 0.33 s. A single 132 → 68 point change moved the heart 52 points left and back. The app's window frame is correct within about 16 ms; moving the window to its final place at once made no difference on screen, so the menu bar animates its own copy of the item.
- Narrowing a little on every display frame kept the heart within a few points at 1.5 s (steady speed) or 2 s (eased), but it jiggled by a pixel as the system fell behind, and the badge's left edge was visibly clipped. Rejected on sight.
- A separate status item for the heart kept the heart perfectly still, but macOS does not keep two items together (another app's icon landed between them in the first test). Rejected: the stars and heart must be one item.
- Widening in one step moved the heart at most 3.5 points for about a frame.

The approved collapse therefore hides the change. The stars shrink away and the heart fades over 0.2 s at the full width; the item narrows once while nothing is visible; after 0.35 s, once the slide has finished, the add button and heart fade in over 0.2 s, already where they stay. The add button is never shown at the full width first.

In the first live try, Music sent no track and then the same song again while the collapse was still waiting for its first frame (the first frame waits behind synchronous Music reads; 0.6 s in the next try). That update replaced the display without animation and narrowed the item in one step. A running transition now survives updates that change nothing on display.

Native screen recordings remain the only valid check for menu-bar placement; the browser preview and local view coordinates cannot show the system's slide.

## A hitch in the rollout (2026-11-12)

Ross sometimes saw a hitch as the stars rolled in when he started a song in Music. It was looked for twice on his Mac (macOS 27.2, one 60 Hz display, Reduce Motion off, the strip on): first in the system log, then in 19 timed trials, and once more on the installed build after the change was merged.

### What the log held

The log keeps StarBar's lines for about 13 hours, so it held two rollouts of build 447, neither from the stopped dot:

- **Music's repeat of a notification was read in the middle of a rollout.** A library song was started in Music while Spotify was followed. Music sent an empty `playerInfo`, then Playing, then Playing again for the same song 0.79 s later. The repeat was held while the bottom strip moved, as it has been since 2026-11-03, and passed on 0.67 s later, when the strip was still. By then the stars had been rolling for about 0.46 s of their second. The menu bar's reads for the repeat took 124 ms before its next log line, seven frames at 60 Hz, and the strip's refresh came after that. Each transition followed the wall clock after its first frame, so the stars will have moved on by that much in a single frame. This was read from the log, not filmed.
- The other rollout, from the add button after a library change, had nothing on the main thread during it.
- A collapse that started while the display was asleep drew its first frame 45,749 s later, in the second the display woke. Frames are only asked for while the display is on.

### The trials

Each trial quit Music, opened it again and played one library song by persistent ID, so that the stars rolled out from the stopped dot; times below are from the play command. With Spotify paused on a song, StarBar follows Spotify once Music has quit, and the same trial rolls out from Spotify's heart. The notifications are StarBar's own log lines, the Apple Events on its main thread come from a debug log stream, and ten trials were recorded natively (the menu bar, 2 pixels a point, 60 frames a second) and the leading star followed frame by frame. 1.9.0 (build 449) ran as installed. The builds with the changes ran from the build folder, which no permission prompt covers but which makes the item the leftmost status item; only the last trial, after the merge, was of an installed copy (build 455).

**What Music sends for the first song of a launch.** Never one Playing notification alone. In 18 cold starts it announced the song paused and then playing in 12, a Paused naming no song and then Playing in 4, and a notification with no state and then Playing in 2; in three or four it then repeated Playing 0.3 to 0.6 s later. It also announces a library change: 1.1 s after the play in two trials, 2.6 to 3.1 s after in five others.

**Every roll starts late.** Each of those notifications replaces the player record, and the reads that follow run 0.5 to 1.2 s without a gap (20 to 40 Apple Events). The rollout is started by the first of them and its first frame waits for the rest: 0.23 to 0.61 s after the item widens, in the eight rolls from the stopped dot that logged it, so the stars began to move 0.56 to 1.25 s after the play. That is a late start, not a hitch, since nothing has been drawn yet, and nothing here changes it. It is the largest delay left.

**The hitch is a read that lands after the first frame.** One natural trial of six on 1.9.0 had it: Music announced a library change 1.14 s after the play, and the re-read 0.3 s later took 16 Apple Events and 266 ms, starting no more than 0.58 s into the roll (the first frame cannot have come before the first reads ended); the repeat of Playing, which the strip had held for 0.94 s, took another 16 and 244 ms at the roll's end. The other five had no read in the roll.

**Both events forced into the roll.** A helper waited for Music's Playing notification, posted `com.apple.iTunes.libraryChanged` 0.35 s later and the same notification again, unchanged, 0.6 s later. Two trials on each build, one of each recorded:

| | 1.9.0 (449) | With the changes (5788c99) |
| --- | --- | --- |
| Reads of Music once the first frame could draw | two bursts of 16 Apple Events, 238 to 252 ms each: the library re-read 0.70 and 0.88 s after the rollout was started, the repeat 1.31 and 1.50 s after, when the strip was still | none until 31 and 48 ms after the last frame, then 32 Apple Events in 0.52 s |
| The rollout's own line | not logged by 1.9.0 | 62 frames in 1.017 s, 0 late, longest gap 19 ms; 61 frames in 1.016 s, 1 late, longest gap 33 ms |
| Longest run of frames with the leading star still (recording) | 15 frames, 250 ms | 1 frame |
| The star's move on the next frame | 51.5 pt | 6.0 pt |

One-frame runs are the recorder dropping a frame: they appear about once in 15 frames in every recording, including those whose own line says none was late. By the recording's line-up with the log, the 15 frames are the library re-read's 248 ms of reads. When 1.9.0 drew its first frame is inferred from the end of its first reads, since it logs nothing for a rollout.

**Left to Music.** Six natural rolls from the stopped dot with the changes (two before the re-reads waited, and all six with a six-frame wait after the widening, not nine): 61 or 62 frames in 1.000 to 1.017 s, none late, and no Apple Event between the first frame and the last. One of them met a repeat of Music's own, held from 0.53 s after the play until 30 ms after the roll's last frame. A roll from Spotify's heart met a repeat and a library change of Music's own; both waited, and the reads began 26 ms after its last frame (83 frames in 1.383 s, 1 late).

**The wait after the item widens.** From Spotify's heart, 1.9.0 drew a star over the icons to the right of the item for 7 and 8 frames in two recordings, starting on the frame the item widened. With the nine-frame wait, two recordings showed none, the first star coming within 3 pt of the next icon for one frame in one of them. The places differed, though: 1.9.0's item sat between two other apps' icons and the new build's was the leftmost. So the installed build was recorded once more, in 1.9.0's place: again no star over the icons to the right, the first star showing 11 frames (0.18 s) after the widening with its right edge 6.5 pt short of the next icon. The menu bar was still sliding the item then. The star started about 12 pt to the right of where a roll from the stopped dot starts it, and the icon on the item's left went on moving for about ten more frames, so the whole slide takes about 21 frames, 0.35 s, much as a narrowed item's does. The slide moves the way the roll does, and the roll's own line shows nothing of it: 82 frames in 1.383 s, 2 late with the longest gap 33 ms, both 0.13 s in, while Spotify's heart faded. Waiting out the whole slide would hold the stars back another 0.2 s; that has not been tried. From the stopped dot no star was out of place on any build, in five recordings, because the first frame came later than any wait.

**Not explained, and limits.**

- One roll from Spotify's heart had 5 late frames, none longer than 34 ms (80 frames in 1.400 s). A read of the whole Music library on a background thread, 9.7 s long, ended during it, and the log stream dropped lines, so its count of no Apple Events in the roll is a lower bound.
- What was held runs as soon as the motion ends, back to back: a re-read and a repeat together took 0.52 s. Nothing is moving then but the sleeve's tilt, which catches up. They could be merged into one read, since each replaces the player record.
- No trial had a Playing notification arrive after the roll's first frame. It is not a repeat of a Paused one, so it would be read at once and pause the roll.
- A StarBar opened while Music is paused on a song rolls the stars out at launch (62 frames in 1.009 s, none late, 0.73 s after it was opened); a play after that rolls nothing, the stars being there already.
- The forced events are synthetic. The natural trials above show Music sending the same two by itself.

### What changed

- A repeat now waits for the menu bar's transition as well as the strip (`RepeatedUpdateHold`, at most 2 s).
- The re-read after a library change, and the one 2 s after Music launches, wait for both in the same way (`iTunesRadioStation.motionHoldsBackAReread`, `readPlayerAgainWhenStill`).
- A transition's time is stepped like the strip's (`MenuBarAnimationTiming` on `SteppedTimeline`), so anything else that holds the main thread pauses the stars where they were drawn.
- The stars wait 0.15 s after the item widens (`StarRollout.settleDuration`), for the menu bar's own slide of the wider item: three to four frames from the stopped dot on 2026-10-22, seven and eight from Spotify's heart on 2026-11-12. A new song's first frame usually comes later than that anyway, so the wait is only seen when it is needed, which is after Spotify's heart has faded.
- Every transition logs how it was drawn when it ends (`FrameCadence`): frames, late frames, the longest gap and where in the transition it fell, and how long the first frame waited.
- The tests that draw a transition set Reduce Motion off for themselves (`MenuBarRatingControl.reduceMotion`), so they run on CI, whose runners have it on.
