# Timeline QA: Screen Studio split tool vs Framecast 1.8.0

Tested 17 Oct 2026, 21:12–21:40, on the MacBook Pro (built-in display, 1512×982 pt, macOS 27.0.1).
- Screen Studio: the installed, unlicensed build.
- Framecast: 1.8.0.

Both editor windows were set to **Window → Fill**, so they were the same size. Screenshots are in `docs/qa/timeline/`:
- `ss-…` files are Screen Studio.
- `fc-…` files are Framecast.
- `pair-…` files stack the two apps for the same state.

**How the mouse pointer was captured.** My screenshots can't include the mouse pointer. To capture the split pointer, I made a short Framecast recording while hovering both apps' timelines with split mode on. Framecast saves every system cursor image it sees (`cursors/*.png` plus timestamps in `cursor.json`), so the pointer images below are the real bitmaps macOS drew.

## 1. Summary: the 5 most important findings

1. **The two apps split differently.** Screen Studio's split cuts only the lane you click:
   - Clicking the clip lane split the clip, but the zoom and the mask spanning that moment stayed whole.
   - Clicking the zoom lane split only the zoom.
   - Clicking the mask lane split only the mask.

   Framecast cuts the clip, the zoom and the effect together with one click. Framecast's 1.7.0 changelog says it "works like Screen Studio's", but on this point it does the opposite. See `pair-after-cut.jpg`, `ss-split-click-zoom-lane.jpg` and `ss-split-click-mask-lane.jpg`.
2. **Framecast: dragging a title or an image on the video doesn't move it.**
   - The drag only works if you start in the **top-left corner of the video**, where nothing is drawn. From there the title or image then follows the pointer exactly.
   - Cause: in `PreviewOverlays.swift`, `TitleCanvasOverlay` and `ImageCanvasOverlay` apply `.contentShape(Rectangle())` *after* `.offset(...)`. The hit area therefore stays at the layout origin, while the drawing moves.
   - Arrows, shapes and blur use `RegionCanvasOverlay` and move fine. The image's resize handle (placed with `.position`) also works.
   - See `fc-title-drag-on-title-no-move.jpg` and `fc-title-moves-when-dragging-top-left-corner.jpg`.
3. **Framecast: "Cut Silent Pauses" and "Speed Up Silent Pauses 4×" found nothing**, even with two pauses of about 10 s and 5 s. There was no message either.
   - `ActivityAnalyzer.silentRanges` uses `threshold: 0.05` on a waveform that `loadWaveform` normalises as `sqrt(peak / loudestPeak)`. So a pause must be more than 52 dB below the loudest peak.
   - In this recording the quietest bin anywhere was 0.18, about 31 dB below the peak, which is ordinary room noise. A threshold relative to the speech level, or to the noise floor, is needed.
   - See `fc-cut-silent-pauses-no-change.jpg`.
4. **The split pointer looks different.** Both apps show white scissors over the lanes and the normal arrow over the ruler, but:

   | | Screen Studio | Framecast |
   |---|---|---|
   | Orientation | Upright: blades up, handles down | Horizontal SF Symbol: blades pointing right |
   | Size | 32×32 pt | 26×26 pt |
   | Outline | Thin, crisp black | Thick, soft dark halo, clipped flat along the right edge |
   | Finger holes | Hollow | Filled black |

   See `pair-split-pointer.jpg`.
5. **Framecast's paused preview still doesn't draw a newly added image or arrow until the playhead moves.** This is the same problem as bug 4 of the 1.4.0 report, which 1.5.0 lists as fixed. Captions also missed the first spoken sentence.
   - See `fc-image-not-drawn-until-seek.jpg`, `fc-arrow-not-drawn-until-seek.jpg` and `fc-captions-generated-first-sentence-missing.jpg`.

**What works well in 1.8.0:**
- Arrows and shapes.
- Move camera.
- The caption-line scissors.
- Selecting effects by clicking on the video.
- The zoom-lane fold animation.
- Several 1.4.0 problems are fixed:
  - VoiceOver labels ("Stop recording", "Discard recording").
  - The readable Move to Trash alert.
  - Caption language now defaults to English (US).

## 2. Screen Studio split tool: exact behaviour

Test project: "QA-split test", a 45 s display recording.
- 3 automatic zooms: 0:06–0:22 at 4×, plus two short ones at about 0:31 and 0:39.
- A sensitive-data mask from 0:12 to 0:16, placed inside the first zoom.
- A highlight mask from 0:29.5 to 0:33, overlapping the second zoom.

Baseline: `ss-baseline-zoom-and-masks.jpg`.

**Turning it on and off**
- **On:**
  - Click the scissors button at the far left of the transport row, below the preview. Its tooltip reads "Split clip ⌥", meaning hold Option for a temporary split (`ss-split-tooltip.jpg`).
  - Or use the command palette (⌘K) → "Toggle split", which has no shortcut (`ss-command-palette-split.jpg`).
  - S does nothing in Screen Studio. C ("Split slice at current time") cuts at the playhead without turning the tool on.
- **While on:** the button gets a lavender rounded-square background with a lavender icon (`ss-split-button-on.jpg`).
- **Off:**
  - Click the scissors again (works).
  - Press Esc (works, `ss-split-off-after-esc.jpg`).
  - It does **not** turn off after a cut: it stayed on through three cuts.
  - Holding ⌥ couldn't be checked, because my tools can't hold a modifier while hovering.

**Pointer while hovering** (captured bitmaps, `ss-split-pointer-x8.png`)
- White scissors, upright, with a thin (about 1 pt) crisp black outline.
- 32×32 pt, with the hotspot in the centre (16,16). The finger holes are hollow.
- **The same scissors over the clip, zoom and masks lanes.** It flickers back to the arrow for about 40 ms when crossing the gap between the clip and zoom lanes.
- **Over the ruler it is the normal arrow**, even though the red line still shows there.

**Cut indicator while hovering** (`ss-split-hover-line-closeup.jpg`)
- A 1 px red line (about #C4535A) runs from the ruler straight down through every lane to the bottom of the timeline. It follows the pointer with no visible lag.
- At the top is the **same dark grey round hover pin** used outside split mode (about #2B2A38). Only the line turns red; there's no scissors badge while hovering.
- The transport time shows the hovered time (for example 0:13.29), and the preview scrubs to it.

**Cutting at 0:13.5, where the zoom and the mask both span** (`ss-split-before-cut.jpg` → `ss-split-after-cut.jpg`, `ss-split-after-cut-zoom-not-split.jpg`)
- **Did the clip split?** Yes, into 14 s + 31 s.
- **Did the zoom split?** No, it stayed one block (0:06–0:22).
- **Did the mask split?** No, it stayed one block.
- **Can you cut on the zoom or mask lane?** Yes, but each lane cuts only itself:
  - A click on the zoom lane at 0:18 split that zoom in two and left the clip alone: no new pin, no clip cut (`ss-split-click-zoom-lane.jpg`).
  - A click on the mask lane at 0:31.5 split only the highlight mask (`ss-split-click-mask-lane.jpg`).

**After a cut**
- **Cut mark:** a gold teardrop pin with a scissors icon (about #DFA44A) on the ruler. The two clip pieces sit edge to edge with a hairline gap.
- **Selecting a piece:** with split off, clicking a piece selects it. It gets a white border and white end handles, the other piece dims, and the inspector switches to "Close Slice editor" (Speed, Cursor settings, Remove slice) (`ss-clip-selected-full-window.jpg`).
- **Deleting a piece:** Delete (or Remove slice) removes it, and **the timeline closes up**: 45 s became 30.3 s. In `ss-after-delete-ripple.jpg`:
  - The pin moves to 0:00 and shows a "13s" badge for the removed time.
  - A zoom that overlapped the removed part is cut short, with a fade at its start.
  - The overlapping mask is trimmed.
- ⌘Z restores the piece.

**Motion**
- Turning split on or off changes only the button tint. The lanes don't move.
- While hovering, the lanes animate:
  - Moving onto the masks lane folds the zoom lane into a thin strip labelled "Zooms" (about 16 pt) and expands the masks to full blocks labelled "Mask" (about 49 pt).
  - Moving back onto the zoom lane reverses this.
  - It's a smooth transition of about 0.3 s. Mid-frame: `ss-lane-fold-animation-midframe.jpg`; end: `ss-split-hover-masks-lane-zooms-fold.jpg`.
- Scrolling over the timeline does nothing (`ss-scrolled-down.jpg`). In Screen Studio the folding is driven by hover, not by scrolling.

## 3. Timeline differences

Colours were sampled from the screenshots, so they're approximate (JPEG). Sizes are in points. Both windows were the same size (Fill).

| Area | Screen Studio | Framecast 1.8.0 | Screenshot(s) |
|---|---|---|---|
| Background | Near-black #08090D | #0A090E (same) | `pair-nothing-selected.jpg` |
| Header | No toolbar row. Scissors sit in the transport row | Extra row: Split / Zoom / Effect ▾ / Smart Speed ▾ / delete, plus a hint text line | `pair-nothing-selected.jpg` |
| Lane background | None: blocks float on black | Dashed-outline "wells" (#101012, border #19181E) behind the zoom and effect lanes | `pair-nothing-selected.jpg` |
| Clip colour and light | Gold gradient, dark top #865E23 to bright bottom #B98230 ("lit from below"), no waveform | Similar gold #866230 → #B98846, plus a waveform drawn across the clip | `pair-nothing-selected.jpg` |
| Clip size | About 48 pt tall, corner radius about 8 | 60 pt tall, corner radius about 8 | `pair-nothing-selected.jpg` |
| Clip label | Faint "Clip", then "45s ⊙ 1x" | Faint "Clip", then "59.1s ⊙ 1×" (one decimal) | `pair-nothing-selected.jpg` |
| Zoom colour | **Bright** indigo gradient #4D33EA (top) → #7964F1 (bottom) | **Dark** indigo #272264 → #2D277D. Much darker and lower contrast | `pair-after-cut.jpg`, `pair-zoom-selected.jpg` |
| Zoom lane height | About 49 pt open, about 16 pt folded | 40 pt open, 14 pt folded | `pair-scrolled-down.jpg` |
| Zoom label | Faint "Zoom", then "🔍 4×  🖱 Auto" | "🔍 2,0×" only: no "Zoom" title, no Auto/Manual, and a decimal comma from the system locale | `pair-after-cut.jpg` |
| Masks / effects | One "Masks" lane, pink gradient #7D3A5D → #9D4A74, labelled "Mask". Folds to a thin bar | One "Effects" lane with a colour per type: title #6A3549, blur #336475, image #40356D, circle #723926, move camera green. 34 pt chips with icon and name | `pair-effect-selected.jpg` |
| Lane labels | "Zooms" / "Masks" appear beside whichever lane is folded | "Zooms" appears only when the lane is compacted. No effects label | `ss-split-hover-masks-lane-zooms-fold.jpg`, `fc-scrolled-down.jpg` |
| Ruler | "0:05" labels every 5 s with a dot halfway between, grey text | The same scheme (dotted ruler), very close match | `pair-nothing-selected.jpg` |
| Playhead | Blue-violet #492EF5 round pin and line | #4B3FE7 round pin and line (same) | `pair-nothing-selected.jpg` |
| Hover indicator (normal mode) | Grey round pin plus grey line. Preview scrubs and the transport shows the hovered time | Grey dot pin plus grey line. **No scrubbing; the transport time doesn't change** | `ss-split-off-after-esc.jpg`, `fc-split-off-after-esc.jpg` |
| Split mode: hover | Red line, grey round pin (no scissors badge while hovering) | Red-orange line (#BC6844) with a **gold scissors pin that follows the pointer**. Header hint: "Click anywhere on the timeline to split · S or Esc to stop" | `pair-split-hover.jpg` |
| Split button | One lavender square (scissors) | Scissors under the video **and** a "Split" text button, both lavender. Neither has a tooltip | `ss-split-button-on.jpg`, `fc-split-button-no-tooltip.jpg` |
| Split pointer | Upright white scissors, thin crisp black outline, 32 pt, hollow finger rings | Horizontal white SF Symbol, thick soft dark halo **clipped flat on the right edge**, 26 pt, filled finger holes | `pair-split-pointer.jpg` |
| What a click cuts | Only the lane under the pointer | Clip, zoom and effects together | `pair-after-cut.jpg` |
| Cut mark | Gold teardrop scissors pin on the ruler. After deleting a piece, it shows the removed time ("13s") | Gold teardrop scissors pin (same look). No removed-time badge seen | `ss-after-delete-ripple.jpg`, `fc-after-caption-cut-closes-up.jpg` |
| Clip selected | 2 pt white border, white bar handles at both ends, other pieces dimmed | Same white border and handles, other pieces dimmed. Close match | `pair-clip-selected.jpg` |
| Zoom selected | White double ring (outline plus an outer ring with a gap). Other zooms dimmed | Violet glowing double ring plus white handles. Other zooms **not** dimmed | `pair-zoom-selected.jpg` |
| Mask / effect selected | White double ring. Other masks dimmed | Single white ring plus handles. Others **not** dimmed | `pair-effect-selected.jpg` |
| Scrolled down | Nothing happens. Folding is hover-driven | The zoom lane folds into a 14 pt "Zooms" strip with a spring animation. Needs a big scroll (see 4.9) | `pair-scrolled-down.jpg`, `fc-zoom-lane-folding-midframe.jpg` |
| Lane animation trigger | Hovering a lane | Scrolling | `ss-lane-fold-animation-midframe.jpg`, `fc-zoom-lane-folding-midframe.jpg` |

## 4. Framecast 1.8.0 test results

Test project: "QA-1.8 speech", 59 s, camera and mic on.
- TextEdit read three sentences aloud with the Mac's voice: at about 0:25, 0:40 and 0:52.
- The gaps between them were silent: about 10 s and 5 s.

| # | Feature | Result |
|---|---|---|
| 1 | Split tool | **Partly** |
| 2 | Effect → Image | **Partly** (add and resize work; moving fails) |
| 3 | Arrows and shapes | **Pass** (one display problem) |
| 4 | Move camera | **Pass** |
| 5 | Click to select on the video | **Pass** (title, image, blur) |
| 6 | Title drag | **Fail** as users will try it |
| 7 | Caption-line scissors | **Pass** (caption generation itself is Partly) |
| 8 | Smart Speed: silent pauses | **Fail** |
| 9 | Zoom lane folds on scroll | **Partly** |

**1. Split tool — Partly.**
- What works:
  - It turns on with the scissors under the video, the "Split" button, or S, and stays on through cuts.
  - It turns off with the scissors again, S, or Esc (`fc-split-on-with-s.jpg`, `fc-split-off-after-esc.jpg`).
  - The pointer is white scissors with a dark outline over the clip, zoom and effects lanes. Over the ruler it's the arrow, as in Screen Studio.
- Problems:
  - The scissors are horizontal, soft-edged and clipped on the right edge (`fc-split-pointer-x8.png`).
  - One click cuts every lane (`fc-split-after-cut-all-lanes.jpg`), unlike Screen Studio.
  - Neither split button has a tooltip.
- To reproduce: open a project, press S, hover each lane, click the clip lane where a zoom and an effect overlap.

**2. Effect → Image — Partly.**
- What works:
  - The image is added at the playhead for 3 s. It has size, corners and shadow controls.
  - Clicking it on the video selects it.
  - The corner handle resizes it live with no lag (`fc-image-resize-mid-drag.jpg`). It grows around the centre, so the handle drifts away from the pointer while dragging.
- Problems:
  - **Dragging the image does nothing** (3 tries, `fc-image-drag-does-not-move.jpg`).
  - Starting the drag in the video's top-left corner does move it. It then follows the pointer exactly and stays where it's dropped (`fc-image-moves-when-dragging-top-left-corner.jpg`). The cause is the hit-area problem in finding 2.
  - The newly added image wasn't drawn on the paused frame until the playhead moved (`fc-image-not-drawn-until-seek.jpg`).
  - The file picker opens in ~/Movies/Framecast (the recordings folder), not Pictures.

**3. Arrows and shapes — Pass, with one display problem.**
- Each of these updated instantly: arrow directions ↖, ←, ↑, then Box, Circle, blue colour, thickness 12 (`fc-arrow-direction-left.jpg`, `fc-shape-box.jpg`, `fc-shape-circle-blue-thick.jpg`).
- The shape stays on the same content through a zoom (`fc-arrow-follows-zoom.jpg`).
- Moving and resizing on the video both work and follow the pointer (`fc-arrow-moved-mid-drag.jpg`).
- Problems:
  - A new arrow isn't drawn until the playhead moves (`fc-arrow-not-drawn-until-seek.jpg`).
  - The timeline chip keeps the ↗ arrow icon after switching to Box or Circle (its label does update).
  - Once, during a drag, a macOS camera menu ("No camera / MacBook Pro Camera / iPhone / Desk View") popped up over the preview (`fc-camera-menu-popped-during-drag.jpg`). It's probably from the macOS camera Ring Light helper that appeared while the camera was recording, not Framecast.

**4. Move camera — Pass.**
- Effect → Move camera at 0:40 (4 s, top-left, 33%). The bubble glides from the bottom-right to the top-left: caught mid-glide at 0:40.3 (`fc-move-camera-mid-glide.jpg`).
- It holds there, then returns to the bottom-right after 0:44 (`fc-move-camera-back-after.jpg`).

**5. Click to select on the video — Pass for title, image and blur.**
- With nothing selected, clicking each one on the paused video selected it and opened its editor (`fc-title-selected-by-click.jpg`, `fc-image-selected-by-click.jpg`).
- I didn't try selecting the arrow this way, because it was already selected while I edited it.

**6. Title drag — Fail as users will try it.**
- Dragging the title card itself never moved it (4 tries, `fc-title-drag-on-title-no-move.jpg`).
- Dragging from the video's top-left corner moved it. The text and the dashed frame then moved together with **no delay** (`fc-title-moves-when-dragging-top-left-corner.jpg`).
- So the 1.7.0 "instant drag" works; only the grab area is in the wrong place (finding 2).

**7. Caption-line scissors — Pass. Caption generation — Partly.**
- Generate made 4 lines in about 2 s, with the language defaulting to English (United States).
- **It missed the first sentence** ("Welcome to this short test…", 0:25–0:29), although its level matched the others (`fc-captions-generated-first-sentence-missing.jpg`).
- Scissors on "so the silence can be removed later" (0:43.6):
  - That part was removed (59.1 s → 56.3 s).
  - The clip split with a pin at the cut, the timeline closed up, and the list dropped to 3 lines (`fc-before-caption-cut.jpg` → `fc-after-caption-cut-closes-up.jpg`).
- Captions have no lane on the timeline.

**8. Smart Speed: silent pauses — Fail.**
- Both "Cut Silent Pauses" and "Speed Up Silent Pauses 4×" left the timeline unchanged, with no message (`fc-smart-speed-menu.jpg`, `fc-cut-silent-pauses-no-change.jpg`).
- It found none of the pauses (cause in finding 3), so whether it would cut words off couldn't be judged.
- It should at least say "No silent pauses found".

**9. Zoom lane folds on scroll — Partly.**
- A gentle scroll (2 mouse-wheel notches) did nothing (`fc-scrolled-gently-no-fold.jpg`).
- A bigger scroll folded the lane smoothly into the "Zooms" strip (`fc-zoom-lane-folding-midframe.jpg`, `fc-scrolled-down.jpg`). Scrolling up brought it back.
- Cause: `installScrollMonitor` ignores events with `|scrollingDeltaY| ≤ 2`. A classic mouse wheel sends about 1 line per notch, so a normal wheel needs a fast spin. Consider reacting to any downward scroll, or to the accumulated delta.

## 5. Other things that looked broken or odd

- **Clashing global shortcuts.** Screen Studio and Framecast both register ⌘⇧2 and ⌥⌘3. With both apps running, ⌘⇧2 opened Screen Studio's "Finish recording?" dialog. Framecast should detect the clash, or let the user know in Settings → Shortcuts.
- **Camera Ring Light overlay.** While Framecast recorded with the camera on, macOS showed its "Ring Light Helper" overlay, which blocked clicks in the lower-right of the screen. That's a system feature, but worth knowing about when recording with the camera.
- **⌘W didn't close an editor window** once; the red close button did.
- **Clicking the ruler** sometimes didn't move the playhead on the first click.
- **Zoom labels** use the system decimal comma ("2,0×"), while speed labels use "1×".
- **Fixed since 1.4.0:**
  - The control bar's VoiceOver labels now read "Stop / Pause / Restart / Discard recording".
  - The Move to Trash alert has a clear blue button and explains that the item can be restored.
  - Caption language now defaults to English (US).

## 6. What I trashed, and settings I changed

**Moved to the Trash** (recoverable until the Trash is emptied):
- Screen Studio: **QA-split test** (`~/Screen Studio Projects/QA-split test.screenstudio`, 45 s). I moved it with Finder, because Screen Studio's own delete says "This action cannot be undone" and doesn't use the Trash.
- Framecast:
  - **QA-1.8 speech** (`Recording 2026-10-17 at 21.21.13.framecast`, 59 s, contains the image overlay).
  - **QA-pointer** (`Recording 2026-10-17 at 21.33.40.framecast`, 60 s).

  Both were moved with Framecast's Move to Trash.

The recordings ran longer than the 10–20 s asked for, because stopping took a while. Your Framecast recordings (16.10 at 14:22 and 19:03, 17.10 at 09:22) weren't touched, and no exports were made.

**Settings changed and restored:**
- **Screen Studio camera:** MacBook Pro Camera (default) → Don't record camera → **back to MacBook Pro Camera**. Mic and system audio were already off and weren't changed.
- **Framecast camera:** turned on for "QA-1.8 speech", then **back off**. The mic stayed on (MacBook Pro Microphone), as it was. Nothing else in Framecast was changed.
- **Screen Studio padding:** I bumped the padding slider by accident while trying to resize the timeline. I reset it right away, and it only affected the QA project, which is now in the Trash.
- Framecast wasn't running when I started, so I quit it at the end. Screen Studio is still open with its toolbar closed.

**Left for you:** TextEdit has an unsaved document "Framecast Editing Tool Test" (the text the Mac read aloud). My tools aren't allowed to press "Delete" in the save sheet, so please close it and choose Delete.
