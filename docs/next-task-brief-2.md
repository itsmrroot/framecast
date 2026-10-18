# Brief (18 Oct 2026, 01:10): Framecast 1.11 vs Screen Studio — video, editor colours, split motion

You're helping me make my Mac screen recorder Framecast (version 1.11) match Screen Studio. Use computer use to drive both apps, measure carefully, and write a report with evidence. Don't change any code; just test, measure and report.

## Ground rules
- Don't delete, rename or change any existing recordings or projects in either app. Name everything you create "QA2-…".
- When you finish, move only your own QA2- projects and exports to the Trash with Finder (Screen Studio's own delete is permanent), and list what you trashed.
- Don't change app settings unless a step says so. If you do, note the original value and restore it at the end.
- Don't buy, sign in, accept terms, or install anything. If something asks, stop and tell me.
- Both apps use ⌘⇧2 and ⌥⌘3. Quit one app while recording with the other, so shortcuts don't clash.
- Save screenshots and extracted frames in ~/Desktop/Projects/framecast/docs/qa/video/ (create it). Use names like ss-…, fc-…, pair-….
- Write the report to ~/Desktop/Projects/framecast/docs/qa-video-comparison.md.
- ffmpeg at /opt/homebrew/bin/ffmpeg (or scrub in QuickTime). Digital Color Meter (sRGB, hex) for colours.

## Part 1: Record the same thing in both apps and compare the video
1. Identical scene: Finder window with many files, maximised; same wallpaper and position both times.
2. ~25 s script: rest 2 s; click file top-left, wait 2 s; slowly move right (~2 s), click, wait 2 s; quickly to bottom-left, click, wait 3 s; three quick clicks in the middle; big fast swipe, no click; rest 3 s.
3. Defaults: auto zoom ON, cursor smoothing default, camera off, mic off. Framecast: toolbar → Display → Start recording. Projects "QA2-screen-studio" and "QA2-framecast".
4. No edits. Export MP4, 1080p, 60 fps, highest quality to docs/qa/video/ as ss-export.mp4 and fc-export.mp4.
5. Measure: fps/resolution/bitrate, dropped/repeated frames; zoom-in duration, per-frame scale curve, overshoot, start vs click, level; zoom-out same; panning follow/lag/overshoot with per-frame camera position for step c; close clicks; swipe motion blur; sharpness crops; cursor size/smoothing/trail/click effect; overall feel. Side-by-sides pair-zoom-in.png, pair-pan.png, pair-blur.png, pair-sharpness.png.

## Part 2: Editor colours
Same window size. Digital Color Meter hex for clip/zoom/mask-effect blocks (top/middle/bottom/rim), selected ring, timeline bg, ruler text and dots, playhead pin/line, hover pin/line, split line and scissors pin, lane labels, block label text — unselected and selected. Glow/shadow, corner radius, lane heights, spacing. Table: Element | State | SS hex | FC hex | Other differences | Screenshot. Then exact changes for Framecast.

## Part 3: Screen Studio's split motion
Record (⌘⇧5 or Framecast, 60 fps) SS editor while toggling split, hovering lanes, cutting clip lane → ss-split-motion.mov. Frame by frame: what moves on/off (direction, points, frames, easing, bounce, delays), hover changes, lane folding speed, cut moment (separation, pin drop, flash), pointer per lane/ruler. Same for Framecast 1.11; key frames ss-split-f###.png, fc-split-f###.png.

## Report (docs/qa-video-comparison.md)
1. Top 5 differences that make SS feel smoother. 2. Recording/export tables. 3. Colours table + exact changes. 4. Split motion frame by frame. 5. Other Framecast issues. 6. Trashed + settings restored.
