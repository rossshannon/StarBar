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
| First library song after launch or Music quitting | Stars roll into place over 1.0 seconds |
| Add-to-library button to a rateable song | The same 1.0-second rollout |
| Different ratings on successive library songs | Changed glyphs retract or grow in place over 0.2 seconds; full/half stars blend |
| Library song to an Apple Music-only song, including deletion from the library during playback | Stars shrink and the heart fades (0.2 s), the item narrows while empty and waits for the menu bar's slide (0.35 s), then the add button and heart fade in (0.2 s); total 0.75 seconds |
| Music quits | Return to the compact stopped dot and rearm the next entrance |

Music sends a bare `Player State: Stopped` between some songs. Measured gaps were 50–131 ms, so a stopped notification cannot distinguish a song change from the end of a queue. The display session lasts until Music quits: hold the previous strip over missing-track updates and disable stale rating actions. No stop timer or additional Music polling is used.

Manual rating edits take effect immediately. Animation never writes intermediate values to Music. Reduce Motion bypasses transitions. Each animation starts its clock on the first display callback: synchronous Music reads have delayed that callback by 198–261 ms, which previously consumed the entire 0.2-second rating transition before any frames were drawn.

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
