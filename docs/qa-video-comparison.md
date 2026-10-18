# Framecast 1.11 vs Screen Studio: video motion, editor colours and split motion

Tested 18 Oct 2026 (01:10–01:30 and 10:17–10:35) on the MacBook Pro (built-in display 1512×982 pt, 120 Hz, macOS 27.0.1).
- Screen Studio 4.0.4 (unlicensed).
- Framecast 1.11.1.

Evidence is in `docs/qa/video/`:
- `pair-…` images put the two apps side by side.
- `ss-…` files are Screen Studio; `fc-…` files are Framecast.
- Per-frame measurements (JSON) are in `docs/qa/video/_work/`.

All "t=" times in screenshot names and tables are seconds in that recording.

## How it was measured, and three limits to know first

1. **Screen Studio would not export.** Export opens "Activate Screen Studio" and asks for an email or licence key (`ss-export-needs-activation.jpg`), so I stopped there as instructed.
   - Instead, I recorded Screen Studio's own editor preview playing the QA2 project at 1× (Preview quality Full, 1080p preview size), using a Framecast display recording at 3024×1964, about 57 fps.
   - So "Screen Studio" numbers come from its real-time preview rendering, not from an exported MP4.
   - Framecast numbers come from its real export, `fc-export.mp4`: H.264 High, 1582×1080, 60 fps constant, 17.1 Mb/s, Studio compression, 2,926 frames over 48.75 s.
   - Timing and easing compare fairly. File size, bitrate and final sharpness don't.
2. **Camera position and zoom per frame** were measured by matching every frame against an unzoomed reference frame (SIFT features plus a similarity fit). This gives the zoom scale and the visible centre for each frame.
   - When Screen Studio's frames are too motion-blurred to match, the table shows "–". That gap is itself evidence of how strong its blur is.
3. **Digital Colour Meter didn't work with my tools.** It stayed at #FCFCFB however the pointer was moved programmatically.
   - Colours were therefore read from pixels: Screen Studio from a 60 fps capture of its editor (BT.709/sRGB), Framecast from full-resolution screenshots.
   - Expect ±3 per channel of encoding error.

**The test script.** It was identical in both apps, driven by the same automated action list (`_work/qa2-script-actions.json`). It recorded the same Finder window ("timeline", filled to the screen, icon view), with the same wallpaper.
- Both apps registered the clicks the same distance apart: 7.31 s, 2.95 s, 3.90 s, 0.52 s and 0.52 s.
- Automation overhead made the "slow" move (step c) about 5 s long, not 2 s.

## 1. Summary: the 5 differences that most make Screen Studio feel smoother

1. **Screen Studio moves the camera ahead of time; Framecast reacts late.**
   - When the cursor raced to the bottom-left while zoomed in (step d), Screen Studio's camera started moving about 0.2 s *before* the cursor did and was at the target as the click happened.
   - Framecast's camera started about 0.45 s *after* the cursor began moving, reached the target's x position 0.31 s after the click, then kept creeping 24 px down for another 0.6 s (until t=39.2).
   - The late start plus the slow drift is the clearest "less smooth" feel (`pair-pan.png`).
2. **Screen Studio front-loads its zooms and hides the fast part in motion blur.**
   - Screen Studio's zoom-in covers 67% of the scale change in 0.19 s (11 frames). Those frames are blurred so heavily that no detail can be matched. A long soft landing follows; it is fully settled at 0.77 s.
   - Framecast uses a symmetric ease-in-out over 0.67 s that starts gently: 19% at 0.1 s, 53% at 0.2 s.
   - Framecast's blur flickers on and off from frame to frame during the zoom (`pair-zoom-in.png`).
3. **Screen Studio's motion blur is strong and continuous; Framecast's is weak and switches off mid-motion.**
   - Screen Studio blurs every moving frame of a pan or swipe in the direction of motion, then fades the blur out smoothly as the camera slows. Sharpness rose gradually from about 260 to 2,000 over 0.15 s while settling.
   - Framecast's pans are sharp. During the step-d pan the blur cut out in a single frame while the camera was still moving fast (sharpness 60 → 957 at t=38.33).
   - On the fast swipe (step f), Screen Studio stays zoomed in and follows the whole swipe under heavy directional blur. Framecast follows only the first half, without blur, then zooms out (`pair-blur.png`).
4. **Framecast's camera wobbles while zooming out.**
   - During Framecast's zoom-out, the visible centre swings right, back left, then right again: x = 374 → 394 → 377 → 395 (in a 791 px-wide measurement) between t=30.27 and t=30.62.
   - That's a visible S-shaped sway of about 14 px in the export.
   - Screen Studio's zoom-out centre moves in one direction only.
5. **Zoom depth and the split tool's "alive" feel.**
   - Screen Studio's automatic zoom defaults to **4×**, Framecast's to **2×**, so Screen Studio's zooms feel more dramatic.
   - In the editor, Screen Studio's lanes keep gently bobbing (±1 pt, period about 0.85 s, lanes out of phase) for as long as the split tool is on.
   - Framecast 1.11 does one dip-and-spring when the tool turns on, then the lanes stay still.

## 2. Recording and export comparison

### 2.1 Basics

| | Screen Studio (preview capture) | Framecast 1.11 (export) |
|---|---|---|
| Source recording | 3024×1964, recorded at 120 Hz | 3024×1964 HEVC, 120 Hz nominal (about 57 fps average) |
| Measured output | about 57 fps capture of a 1520×1020 px preview | 1582×1080, 60 fps constant, 17.1 Mb/s H.264 High |
| Dropped or repeated frames during zooms and pans | Not measurable (the capture's own timing varies) | None found: steady 1/60 s steps through every tracked zoom and pan |
| Default automatic zoom level | **4×** | **2×** |
| Zoom springs (project file) | screen stiffness 125, damping 12, mass 1.5 (cursor the same); motion blur 1.0 | zoomTransition 0.65 s, motionBlur 0.3, cursorSmoothing 0.55 |
| Zooms created for 6 clicks | 2: clicks 2–6 merged into one "click group" zoom | 2: same grouping |

### 2.2 Zoom-in (click 1)

Progress = (scale − 1) / (target − 1). Frame 0 is the first frame that moves. "–" means the frame is blurred too much to match.

| t after start (s) | 0.017 | 0.033 | 0.050 | 0.067 | 0.100 | 0.150 | 0.191 | 0.250 | 0.333 | 0.400 | 0.500 | 0.600 | 0.670 | 0.770 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Screen Studio** | 0.004 | 0.019 | 0.050 | – | – | – | 0.666 | 0.81 | 0.913 | 0.953 | 0.983 | 0.993 | 0.996 | **1.000** |
| **Framecast** | 0.001 | 0.018 | 0.049 | 0.090 | 0.191 | 0.362 | 0.47 | 0.663 | 0.825 | 0.903 | 0.965 | 0.992 | **1.000** | 1.000 |

- **Timing relative to the click:**
  - Screen Studio starts zooming 0.66 s before the click and is at 99.9% when the click happens.
  - Framecast starts 0.59 s before the click and settles 0.06 s after it.
  - Both aim the zoom to land on the click.
- **Duration:**
  - Screen Studio: 46 frames, 0.77 s.
  - Framecast: 40 frames, 0.67 s.
- **Shape:**
  - Screen Studio: a near-instant start (0 → 67% in 0.19 s) and a long exponential tail; the last 10% takes 0.4 s.
  - Framecast: a classic smooth S-curve.
  - Neither overshoots: the maximum measured scale was 4.003 and 2.000.
- **Level reached:** 4.00× and 2.00×.

Evidence: `pair-zoom-in.png` (Screen Studio t=9.94–10.70, Framecast t=27.45–28.10).

### 2.3 Zoom-out (end of zoom 1)

| t after start (s) | 0.033 | 0.10 | 0.20 | 0.25 | 0.30 | 0.40 | 0.50 | 0.60 | 0.67 | 0.90 |
|---|---|---|---|---|---|---|---|---|---|---|
| **Screen Studio** (progress left) | 0.967 | – | 0.283 | 0.20 | 0.11 | 0.042 | 0.016 | 0.006 | 0.003 | **0** |
| **Framecast** | 0.965 | 0.679 | 0.311 | 0.203 | 0.130 | 0.051 | 0.018 | 0.004 | **0** | 0 |

- **Shape:**
  - Screen Studio drops 72% in 0.2 s, all blurred, then lands softly; settled at about 0.9 s.
  - Framecast is smooth and finishes in 0.67 s.
- **Framecast's centre sways** sideways during its zoom-out (x 374 → 394 → 377 → 395, at t=30.27–30.62); see finding 4.
- **Neither overshoots.**

### 2.4 Panning while zoomed in

- **Step c (slow move right):** neither app panned.
  - Both zoomed out about 2.3–2.6 s after click 1 and zoomed back in at click 2.
  - So "follow continuously vs only near the edges" could only be measured on steps d and f.
- **Step d (fast move to the bottom-left, then click):**

| | Screen Studio | Framecast |
|---|---|---|
| Camera starts | about 0.2 s **before** the cursor moves | about **0.45 s after** the cursor starts moving |
| Moving frames | 0.62 s, every frame heavily blurred | 0.57 s; blurred for the first 0.3 s only |
| Arrives | at the click (t=20.85) | x 0.31 s after the click; y keeps drifting 24 px for 0.6 s more |
| Overshoot or wobble at the stop | none; 3 px soft tail over 0.3 s | no overshoot; slow drift |

Framecast camera centre (x, y at half resolution) per frame for step d:

| t | 38.03 | 38.10 | 38.20 | 38.30 | 38.40 | 38.50 | 38.60 | 38.80 | 39.00 | 39.20 |
|---|---|---|---|---|---|---|---|---|---|---|
| x,y | 544,178 | 491,204 | 409,246 | 337,282 | 286,308 | 254,324 | 236,334 | 236,342 | 236,345 | 236,346 |

Screen Studio's frames are unmatchable from 19.93 to 20.55 (blur). Then: 198,389 → 184,396 (20.65) → 175,400 (20.80) → 172,401 (21.12). Data: `_work/ss_pan.json`, `_work/fc_pan.json`.

- **Step e (three quick clicks close together):** both apps kept the existing zoom.
  - Each made one small pan to the group and no new zoom.
  - Framecast's pan took about 0.9 s, with a slow creep at the end (t=42.0–42.9).
- **Step f (fast swipe, no click):**
  - Screen Studio follows the whole swipe at 4×, with strong directional blur on every moving frame; only the cursor stays sharp (`ss-swipe-blur.png`).
  - Framecast pans up-right with the first half of the swipe (sharp frames, `fc-swipe.png`), ignores the down-left half, then zooms out. Only the zoom-out frames are blurred (`fc-zoomout-blur.png`).
  - Text is sharp again in Screen Studio about 0.15 s after it stops; in Framecast instantly, because the pan was never blurred.

### 2.5 Sharpness at rest, and the cursor

- **Text at rest:** `pair-sharpness.png` shows 100% crops of a zoomed text area.
  - Framecast at 2× is crisp (Laplacian variance 1,489).
  - Screen Studio's preview at 4× is softer (339), because 4× upscales the source about 2× in the preview.
  - This isn't an export-to-export comparison (see limit 1).
- **Cursor:**

| | Screen Studio | Framecast |
|---|---|---|
| Size | large: 48 px setting, the macOS Tahoe set | 1.6× setting, outline style |
| Smoothing | spring (stiffness 125, damping 12, mass 1.5) | 0.55 |
| Sharp when zoomed | vector cursor, sharp even on blurred frames | sharp |
| Click effect | none by default | ripple |
| Trail | none seen | none seen in these frames |

## 3. Editor colours

Both editors at the same size (Window → Fill, 1512×949 pt), dark mode. Colours are sRGB hex sampled from pixels (see limit 3). "Top / middle / bottom" go down through each block.

| Element | State | Screen Studio | Framecast 1.11 | Other differences | Screenshot |
|---|---|---|---|---|---|
| Timeline background | – | #0C0B0E | #0A090E | Same. Framecast lanes sit in dashed wells; Screen Studio has none | `ss-clip-hover-editor.png`, `fc-split-off.jpg` |
| Clip block | none selected | top #82510F · mid #B16E10 · bottom #BD7711 | top #816138 · mid #957542 · bottom #A5824A | **Framecast's gold is much less saturated (tan/khaki).** Screen Studio's blue channel is about 0x0F, Framecast's about 0x40. Heights: Screen Studio 48 pt, Framecast 48 pt; corner radius about 8 pt in both | `ss-clip-hover-editor.png` vs `fc-split-off.jpg` |
| Clip rim | none | thin bottom rim only on hover: #CFC0AB | bottom rim #B08B57 always on | Screen Studio shows a light rim when the pointer is over the clip; Framecast has no hover state | same |
| Clip | selected | 1 pt light outline (#CDC1AB); the block doesn't change | 2 pt near-white ring #FFF6E3, a dark outer halo (#362923), and the block lightens to #8D7141–#B38F53 | Framecast's selection is heavier | `ss-clip-selected-editor.png`, `fc-clip-selected-editor.jpg` |
| Zoom block | none selected | top #3A1EE7 · mid #5A40F3 · bottom #6F53EB, rim #8C73E4 | top #4939CF · mid #5B4FD9 · bottom #6E62E0, rim #7E73DC | Close. Screen Studio's top is deeper, more saturated blue-violet | `ss-zoom-selected-editor.png`, `fc-zoom-selected-editor.jpg` |
| Zoom | selected | bottom rim lightens to #B8A8EC; thin light ring | 2 pt white ring #FBFAFF, top highlight #897EE4, violet halo #433D63; white end handles | Framecast's ring and glow are much stronger | same |
| Mask / effect | none selected | pink mask: top #792F49 → bottom #8B3955 | blur effect: teal #1E3E4B / #264852 (a thin strip when the zoom lane is open) | Framecast colours each effect type; Screen Studio has one pink mask lane | `ss-mask-selected-editor.png`, `fc-effect-selected-editor.jpg` |
| Mask / effect | selected | thin light ring; the lane grows to about 49 pt | white 2 pt ring + white handles; the effects lane opens and the zoom lane folds to a strip | – | same |
| Playhead | – | pin and line #492EF5 | #4B3FE7 | Same | – |
| Hover pin and line (split off) | – | grey round pin #2B2A38, grey line | grey pin, grey line | Same | `fc-split-hover-ruler.jpg` |
| Split line + pin | split on | about 1 px red line (#C4535A); grey round pin while hovering; gold scissors pin (#DFA44A) once cut | red line #BC6844 / Theme.blade #C4545A; gold scissors pin follows the pointer | Framecast shows the scissors pin while hovering; Screen Studio only after a cut | `ss-split-cut-closeup.png`, `fc-split-hover-zoom-lane-lifted.jpg` |
| Lane labels | – | "Zooms" / "Masks" only beside a folded lane, grey (about #6E6E73) | "Zooms" / "Effects", Theme.textDim (white at 55%) | Similar | – |
| Block labels | – | faint title ("Clip", "Zoom") at about 30% white; value ("56s ⊙ 1x", "4× Auto") white | faint title textFaint (32% white); value white | Same scheme | – |
| Glow / shadow | – | no glow; flat blocks | always-on soft glow under the clip and zooms; a stronger halo when selected | Framecast's "always lit" look isn't in Screen Studio | – |

**Exact changes for Framecast to match:**
1. **Clip gradient.** Change `Theme.clipGradient` to top #82510F → bottom #BD7711, i.e. (0.510, 0.318, 0.059) → (0.741, 0.467, 0.067).
   - Selected: keep the same fill (don't lighten it).
   - Remove the always-on bottom rim. Show a 1 pt #CFC0AB rim only on hover.
2. **Zoom gradient.** Change `Theme.zoomGradient` to top #3A1EE7 → bottom #6F53EB, with a 1 pt rim #8C73E4.
   - Selected: rim #B8A8EC.
3. **Selection ring.** Replace the 2 pt white ring and halo with a 1 pt light outline (#CDC1AB on clips, #B8A8EC on zooms).
   - Drop the dark/violet outer halo and the always-on glow.
4. **Masks.** If a mask/blur lane is kept, use pink #792F49 → #8B3955 to match Screen Studio's "Masks".
5. **Scissors pin.** Show it only after a cut, not while hovering. While hovering, keep the grey round hover pin with a red line.

## 4. The split tool's motion, frame by frame

**Screen Studio** was captured at 60 fps by Framecast (`QA2-ss-editor-capture`). The capture showed the split button clicked at t=17.55 (on), 19.23 (off), 20.91 (on), Esc at about 22.4, on again at 24.15, then lanes hovered and a cut at 33.24. The top edge of each lane was tracked per frame (`_work/ss_edge.json`).

**Framecast 1.11 couldn't be captured the same way.** Framecast hides its own windows while it records, and macOS's ⌘⇧5 recorder needs a system interface my tools can't control. So Framecast's motion comes from still screenshots plus its source (`TimelineView.swift`, `LaneMotion`), which defines the timing exactly.

| Moment | Screen Studio (measured) | Framecast 1.11 |
|---|---|---|
| Split turns **on** | 3 frames (0.05 s) after the click, every lane **dips 1 pt down**, then keeps **bobbing ±1 pt continuously** for as long as split stays on. Period about 0.85 s; the zoom lane lags the clip by about 0.1 s and the mask lane moves opposite, so it looks like a slow wave (`ss-split-f0004-on-dip-down.png`, `ss-split-f0031-bob-up.png`, `ss-split-f0053-bob-down.png`) | Each lane does one keyframed dip: 7 pt down in 0.11 s (lane *n* delayed 0.01 + 0.045·*n* s), then a spring back (response 0.4, damping 0.55, about 0.5 s) with a small overshoot. Then the lanes are **still** (`fc-split-on-dip-frame.jpg`, `fc-split-on-settled.jpg`) |
| Split turns **off** | The bobbing stops; lanes return to rest within 1–3 frames (t=19.21–19.26). No dip on off (`ss-split-off-f0003-settled.png`) | The same dip-and-spring as for "on" |
| Hovering in split mode | Lanes don't lift. Moving onto the mask lane **expands the masks to full blocks and folds the zoom lane into a thin "Zooms" strip**, a smooth transition of about 0.3 s (`ss-split-hover-mask-lane-expands.png`). Red line, grey round pin | The lane under the pointer **lifts 3 pt** with a soft shadow (spring 0.25 s) (`fc-split-hover-zoom-lane-lifted.jpg`). The scissors pin follows the pointer. The effects lane is a thin strip until an effect is selected |
| The cut | Pieces appear **0.27 s after the click** (t=33.51), separated by a gap of about 3 pt. The scissors pin appears fully formed (no drop-in, no flash, no bounce); the playhead jumps to the cut. The idle bob continues (`ss-split-cut-closeup.png`, `ss-split-cut-f0016-pieces-appear.png`) | The lane gets the same dip-and-spring "kick" on every cut (code: `cutTick`). Cuts apply on the next frame |
| Pointer | Upright white scissors with a thin black outline (32 pt) over every lane; the arrow over the ruler | Horizontal SF Symbol scissors over the lanes; the arrow over the ruler (see the timeline report) |

**To match Screen Studio:**
- Replace the one-shot 7 pt dip with a continuous ±1 pt idle bob while split is on: about 0.85 s period, lanes phase-offset by about 0.1 s.
- Make "off" stop the motion instead of kicking again.
- Drop the 3 pt lift on hover, and the per-cut bounce.
- Fold the zoom lane when the pointer moves onto the mask/effects lane.

## 5. Other things that looked odd or broken in Framecast

- **Framecast can't record its own editor.** Starting a recording moved all Framecast windows off the current Space, so screen-recording tutorials of Framecast itself aren't possible.
- **The editor window jumps Spaces.** After a recording, Framecast's editor windows stayed on another Space. Bringing them back took Window → Fill or the app switcher.
- **The camera doesn't follow the second half of a swipe.** It followed the up-right half and ignored the down-left half (step f).
- **Zoom-out sway:** see finding 4.
- **Inconsistent blur during zoom-in:** sharpness alternates between frames (42 → 2,847 → 436 at t=27.50–27.55), which reads as flicker.
- **Shortcut clash:** with both apps open, Screen Studio and Framecast both use ⌘⇧2 and ⌥⌘3 (as noted before).

## 6. What I trashed, and settings changed and restored

**Moved to the Trash with Finder** (recoverable until you empty the Trash):
- `~/Screen Studio Projects/QA2-screen-studio.screenstudio`
- `~/Movies/Framecast/Recording 2026-10-18 at 01.18.55.framecast` (QA2-framecast)
- `~/Movies/Framecast/Recording 2026-10-18 at 01.22.50.framecast` (QA2-capture-ss-preview, unusable: the Claude window covered the preview)
- `~/Movies/Framecast/Recording 2026-10-18 at 01.26.49.framecast` (QA2-capture-ss-preview-2)
- `~/Movies/Framecast/Recording 2026-10-18 at 10.21.31.framecast` (QA2-ss-editor-capture)
- `~/Movies/Framecast/Recording 2026-10-18 at 10.25.22.framecast` (QA2-fc-editor-capture: actually recorded Screen Studio by mistake)
- `~/Movies/Framecast/Recording 2026-10-18 at 10.27.08.framecast` (a failed attempt to record Framecast's editor; auto-named)
- `docs/qa/video/fc-export.mp4` (the QA2 export, 104 MB) and two temporary frames (`_tmp_fc3.png`, `_tmp_sscap5.png`)

**Not touched:**
- Your Framecast recordings from 16.10 (14:22, 19:03) and 17.10 (09:22).
- The Screen Studio project "Built-in Retina Display 2026-10-18 00:30:04", which existed before I started.

**Settings:**
- **Framecast microphone:** MacBook Pro Microphone → No microphone for the test → **restored to MacBook Pro Microphone**.
- **Screen Studio:**
  - Toolbar: no device changes. Its toolbar already showed No camera / No microphone / No system audio when I started.
  - View → editor sidebar and timeline: turned off for one capture, then turned back on.
  - Full screen: I put the editor into full screen once and then quit the app. If Screen Studio reopens in full screen, press ⌃⌘F.
  - Timeline zoom slider: moved, but only inside the trashed QA2 project.
- **Digital Colour Meter:** set to "Display in sRGB" and hex values, then quit. It will remember sRGB + hex.
- **Apps:** both are now closed. Framecast and Screen Studio weren't running when this task started.

**Left on disk for evidence** (delete when done): `docs/qa/video/_work/`, with per-frame JSON data and working frames.
