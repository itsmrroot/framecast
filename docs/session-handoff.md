# Session handoff — Framecast QA with Claude

Saved Sat 17 Oct 2026, 21:10 (Vienna). This file lets a new chat continue exactly where this one stopped.

## How to resume in a new chat

Paste this:

> Read `~/Desktop/Projects/framecast/docs/session-handoff.md` (and `next-task-brief.md` next to it), then continue with "Next task". Use computer use on my Mac.

## Done so far

1. **Screen Studio vs Framecast comparison.**
   - Report: `docs/screen-studio-comparison.md`
   - Screenshots: `docs/screen-studio/`
2. **Hands-on QA of Framecast 1.4.0.**
   - Report: `docs/qa-report.md` (31 bugs ranked by severity, 12 UX suggestions, untested areas, cleanup list)
   - Screenshots: `docs/qa/`
   - Raw notes (93 lines, everything observed in order): `docs/qa-session-log.md`
3. **Cleanup after the QA.**
   - All 8 of my test projects and all 7 test exports were moved to the Trash, using Framecast's own Move to Trash.
   - `~/Movies/Framecast` now holds only your recordings:
     - 16.10 at 14:22
     - 16.10 at 19:03
     - 17.10 at 09:22 (made before the QA started, treated as yours)
   - The `Exports` folder is empty.

## Current state of your Mac

All Framecast settings are restored:
- After-recording action: Create project
- Countdown: 3 s
- Frame rate: 60 fps
- Auto zoom: on
- Hide desktop icons: on
- Keystrokes: off
- Mic: MacBook Pro Microphone
- Camera: off
- System audio: off
- Opens to: Recording toolbar
- Appearance: Dark
- Dock icon: shown
- Flag shortcut: ⌃⌥⌘F

Still for you to do:
- **Saved area size.** Framecast's Area → Saved list has a "551 × 310" entry. There's no UI to delete it.
- **System-audio "Selected apps…".** One app was ticked before the QA; it's now empty, and I don't know which app it was.
- **TextEdit.** An unsaved "Untitled" document is open. Close it and choose Delete.

## Next task (not started yet)

Your brief is saved word for word as `docs/next-task-brief.md`:
1. Screen Studio's split tool in detail, including which lanes a cut affects.
2. Side-by-side timeline look of Screen Studio and Framecast, with screenshots in `docs/qa/timeline/`.
3. Tests of the Framecast 1.8.0 features.

The report goes to `docs/qa-timeline-report.md`.

**Check first:** the installed Framecast is **1.4.0**, and the brief tests **1.8.0** features (Image, Arrow/shape, Move camera, caption-line scissors, Cut Silent Pauses, folding Zooms strip). Install 1.8.0 before starting, or tell the next chat to test what's there and mark the missing features "not present in installed build".

## Working tips learned (for the next chat)

**Seeing Framecast's floating windows**
- The toolbar, countdown pill, control bar, pickers, export widgets and speaker notes are hidden from screenshots.
- Read them with `app_screenshot` (window id from `app_list_windows`) and the accessibility tree, and describe them in words.
- Menus (NSMenu) and normal windows do show in screenshots.

**Clicking**
- Instant synthetic clicks (under 8 ms) aren't recorded as clicks in recordings. For "clicks with auto zoom", use mouse down, wait 150 ms, mouse up.
- In SwiftUI alerts (for example Framecast's "Move to Trash?"), ordinary clicks on the red button didn't register. Pressing the button through the accessibility tree (`app_click` with its element index) works.

**Switching tool modes**
- Full-screen tools (`computer_batch`, display clicks) fail while an `app_*` lock is held. Call `app_release` first.
- `app_*` calls need an `app_screenshot` of the window first.

**Coordinates**
- On this Mac, screenshot/frame coordinates ≈ macOS points × 0.907 (frame 1372×891 for a 1512×982 pt display).

**Keyboard**
- The keyboard layout is German, so the tool can't send the US "/" key. ⌥⌘/ shortcuts can't be tested this way.
- Synthetic ⌥ (Option) held during hover doesn't reach the app's hover state.

**Files**
- In the device shell, `~/Movies/Framecast` is mounted as `$HOME/mnt/Framecast` and the project as `$HOME/mnt/framecast`.
- ffmpeg, ffprobe and python3 are available there for checking exports.
- For anything to go in the Trash, use Finder (⌘⌫) or the app's own Move to Trash. The shell can't delete without asking.

**Framecast project format**
- `*.framecast` folder containing `project.json` (name, notes, clips, zooms, effects, flags), `cursor.json`, `screen.mov` and `mic.m4a`.

**Permissions**
- Already granted, with no prompts seen: Screen Recording, Microphone, Speech Recognition.
- Camera was never used.

**Captions**
- Captions on synthetic speech (espeak through the speakers) returned "No speech was found".
- For the caption tests, speak real sentences yourself during the recording.


## Update — 18 Oct 2026, 01:10

**Also done since:** timeline QA of Screen Studio's split tool vs Framecast 1.8.0 → `docs/qa-timeline-report.md` (screenshots `docs/qa/timeline/`). Key results: SS cuts only the clicked lane; FC title/image drag hit-area bug (PreviewOverlays contentShape after offset); Cut Silent Pauses threshold too strict; pointer differences. QA projects from that round were trashed; SS camera and FC camera restored. An unsaved TextEdit doc "Framecast Editing Tool Test" may still be open (discard it).

**Current task (started 01:10):** `docs/next-task-brief-2.md` — Framecast 1.11 vs Screen Studio: identical recordings + exported video measurements, editor colours with Digital Color Meter, split-motion frame by frame. Output: `docs/qa-video-comparison.md`, evidence in `docs/qa/video/`. Name everything QA2-…

**Extra tips learned:**
- Framecast records the real system cursor bitmaps into `<project>.framecast/cursors/*.png` with times in `cursor.json` (`shapes`, `shapeInfo`) — the way to capture pointer shapes, since screenshots omit the pointer.
- Screen Studio projects live in `~/Screen Studio Projects/`; its in-app delete is permanent, so trash with Finder.
- While Framecast records with the camera on, macOS's "Ring Light Helper" overlay blocks synthetic clicks in parts of the screen; use keyboard or keep camera off.
- Clicking alert buttons: use app_click with the AX element index if a plain click doesn't register.
- ⌘Q is blocked for my tools; quit via the app menu → Quit.

## Progress on brief 2 (saved 01:28, 18 Oct) — resume from here

**Done so far**
- Folder `docs/qa/video/` created (temporary frames in `docs/qa/video/_work/`, delete when done).
- Scene: Finder window "timeline" (docs/qa/timeline) maximised (Window → Fill), icon view, wallpaper unchanged.
- Same scripted ~25 s run (exact action list saved in scratchpad as script.json; regenerate from the brief) recorded in both apps:
  - **Screen Studio** project `~/Screen Studio Projects/QA2-screen-studio.screenstudio` (56 s, recording started a few s before script). Its project.json: 2 auto zooms, **4×**, type follow-click-groups: 6.63–9.61 s and 13.93–24.81 s (source time). Springs: mouseMovement & screenMovement stiffness 125, damping 12, mass 1.5; motionBlurAmount 1; cursor size 48, set macos-tahoe, clickEffect none. Clicks in recording/mouseclicks-0.json (mouseDown at 7.29 s, 14.59 s, 17.53 s, …). Raw video = recording/channel-1-display-0-0000.mp4 + 0001…0029.m4s (concatenate), 3024×1964.
  - **Framecast 1.11** project `~/Movies/Framecast/Recording 2026-10-18 at 01.18.55.framecast` named QA2-framecast (48.8 s). Zooms: 2× auto, 27.44–30.64 s and 34.75–45.83 s; clicks at 28.04, 35.35, 38.29, 42.19, 42.71, 43.23 s. Note: Framecast only made 2 zooms for 6 clicks; first zoom merged? (check). FC mic was MacBook Pro Microphone → set to **No microphone** for the test; **restore to MacBook Pro Microphone** at the end.
- **fc-export.mp4** in docs/qa/video: H.264 High, 1582×1080, 60/1 fps constant, 2926 frames, 48.75 s, 17.1 Mb/s (Studio compression).
- **Screen Studio export is blocked**: Export opens "Activate Screen Studio" (needs email/licence) → stopped as instructed (`ss-export-needs-activation.jpg`). Workaround: recorded Screen Studio's editor preview playing at 1× with Framecast:
  - Capture 1 `QA2-capture-ss-preview` (01.22.50.framecast) is useless — Claude window covered the full-screen preview.
  - Capture 2 `QA2-capture-ss-preview-2` (`~/Movies/Framecast/Recording 2026-10-18 at 01.26.49.framecast/screen.mov`, 3024×1964, ~57 fps avg, 73 s): preview visible at points x≈170–930, y≈150–660 (left part of the screen; Claude window covers x>975). Preview playback started ≈ capture t=3 s.
- Screen Studio state: editor open on QA2-screen-studio, sidebar+timeline shown (were toggled off/on and are back on). Screen Studio camera: still "MacBook Pro Camera" (unchanged this time; toolbar showed No camera/No mic/No system audio before recording).

**Still to do**
1. Measure from capture 2 (SS) and fc-export.mp4 (FC): zoom-in/out frames & scale per frame, pan lag, blur, sharpness crops, cursor; make pair-zoom-in.png, pair-pan.png, pair-blur.png, pair-sharpness.png. Use opencv on the device shell (python3 has cv2, numpy, PIL; ffmpeg is /usr/bin/ffmpeg in the device shell).
2. Part 2 colours (Digital Colour Meter granted) with both editors same size.
3. Part 3 split motion: Framecast-record the SS editor while toggling split (scissors at bottom-left of SS transport) and the same in FC; 60 fps frame stepping.
4. Write docs/qa-video-comparison.md.
5. Cleanup: trash with Finder → QA2-screen-studio.screenstudio; FC projects 01.18.55 (QA2-framecast), 01.22.50 (QA2-capture-ss-preview), 01.26.49 (QA2-capture-ss-preview-2) and any later QA2 captures; fc-export.mp4 stays (it's evidence) unless user wants it trashed — brief says trash QA2 exports, so trash fc-export.mp4 too or ask. Delete docs/qa/video/_work temp files. Restore FC mic → MacBook Pro Microphone. Quit Framecast? (it was not running at start of brief 2.)

## Part 1 results (saved 10:25, 18 Oct) — measurement done
Data in docs/qa/video/_work/*.json (per-frame scale/centre/sharpness), images pair-zoom-in.png, pair-pan.png, pair-blur.png, pair-sharpness.png, ss-/fc- stills.
- SS capture offset: capture t = SS source t + 3.32 s. SS clicks (source): 7.288, 14.587, 17.533, 21.433, 21.958, 22.483. FC clicks: 28.04, 35.35, 38.29, 42.19, 42.71, 43.23.
- Zoom level: SS 4× vs FC 2×. Both start zoom-in ~0.6–0.66 s before click and land at the click. No overshoot in either.
- Zoom-in progress (scale fraction): SS 5% @50ms, 67% @0.19 s (frames 4–11 unmatchable = heavy motion blur), 91% @0.33, 99% @0.57, settled 0.77 s (46 fr). FC 5% @50ms, 19% @0.1, 53% @0.2, 77% @0.3, 90% @0.4, 97% @0.5, settled 0.67 s (40 fr). SS = much faster front, longer soft tail; FC = smooth ease-in-out, symmetric.
- Zoom-out: SS 1.0→0.28 in 0.2 s (blurred), 5% left @0.38 s, settled ~0.9 s. FC 50% @0.14 s, 5% @0.4 s, settled 0.67 s. FC camera centre wobbles ±7 px (half-res) during zoom-out (x 374→394→377→395 at 30.27–30.62).
- Step c: neither app panned (both zoomed out ~2.3–2.6 s after click 1, zoomed in again at click 2).
- Step d pan (zoomed): SS camera starts ~0.2 s before cursor moves (anticipates click target), 0.62 s fully blurred, at target by the click, ~0.3 s soft tail of 3 px. FC camera starts ~0.45 s after cursor starts, reaches target x 0.31 s after click, y keeps creeping 12 half-px for 0.6 s more (39.2). FC blur on first 0.3 s then switches off abruptly mid-motion (sharpness 60→957 in one frame at 38.33).
- Step e: both merged all clicks into the existing zoom (one pan, no new zoom).
- Step f swipe: SS follows the whole swipe at 4× with strong directional blur on every moving frame, cursor stays sharp; then zooms out. FC follows only the first (up-right) half, frames sharp (no blur on pans), then zooms out with blur on zoom-out frames only.
- Sharpness at rest: FC 2× crisp (Laplacian var 1489); SS 4× preview softer (339) — SS preview is 2× upscale of source; not an export comparison.
- FC settings: cursorSize 1.6, smoothing 0.55, motionBlur 0.3, zoomTransition 0.65, clickEffect ripple. SS: cursor 48, springs stiffness 125/damping 12/mass 1.5, motionBlurAmount 1, click effect none.
- fps: FC export 60 CFR, no dropped/duplicated frames found in tracked windows; SS capture ~57 fps avg (capture limitation).
Next: Parts 2+3 via Framecast captures of each editor (sample colours from frames + DCM spot checks), then report, cleanup.
