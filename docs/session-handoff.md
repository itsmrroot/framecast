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
