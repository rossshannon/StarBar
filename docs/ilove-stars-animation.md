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
| Library song to an Apple Music-only song, including deletion from the library during playback | Stars shrink over 0.15 seconds, followed by a late badge fade; total 0.35 seconds |
| Music quits | Return to the compact stopped dot and rearm the next entrance |

Music sends a bare `Player State: Stopped` between some songs. Measured gaps were 50–131 ms, so a stopped notification cannot distinguish a song change from the end of a queue. The display session lasts until Music quits: hold the previous strip over missing-track updates and disable stale rating actions. No stop timer or additional Music polling is used.

Manual rating edits take effect immediately. Animation never writes intermediate values to Music. Reduce Motion bypasses transitions. Each animation starts its clock on the first display callback: synchronous Music reads have delayed that callback by 198–261 ms, which previously consumed the entire 0.2-second rating transition before any frames were drawn.

## Fixed heart and menu-bar allocation

Both heart appearances use one independent right-aligned view. Menu-bar images reserve an empty heart slot with `drawsFavorite=false`; other consumers keep their usual embedded outline.

On macOS 27, the visible menu-bar resize moves the heart even when local view and presentation-layer coordinates remain almost unchanged. A standalone native status item reproduced about 60 pixels of leftward movement, including with standard animation controls disabled, intrinsic sizing, and a custom view. Preview images and local inset tests alone did not expose this.

The approved workaround keeps a 132-point allocation for both active modes. `MenuBarStripLayout` right-aligns the changing contents inside it, leaving 64 points unused on the left in the add-button state. The stopped dot keeps its compact allocation. The pointer and pending spinner use the same right-aligned origin; the unused space does not add or favourite a song. Pending-state changes explicitly refresh the padded image.

A native screen recording using the production collapse renderer and fixed canvas held the outline heart at the same pixel coordinate in every measured transition frame. Ross then confirmed the installed version looked good. This screen-space check is required for future changes to the layout; the browser preview is useful for glyph timing but cannot validate macOS menu-bar placement.
