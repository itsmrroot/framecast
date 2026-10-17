# Changelog

## 1.5.0

Fixes from a full hands-on test of 1.4.0, plus a few things that make recording easier.

**Recording**
- Every click is recorded, even a quick trackpad tap, so click effects and automatic zooms never miss one
- The ▾ menu next to Start can no longer start a recording by accident, and the button shows what happens next ("then: Export & copy")
- Menus show a ✓ next to the current camera, microphone, system audio, after-recording action, aspect ratio, preview quality and speed
- Area recording: typed sizes apply when you leave the field (not only on Return), keep the aspect lock, and record at exactly the size shown. Saved sizes can be removed, and there's a note field
- Window recording works like Display and Area: pick a window, name it, then press Start. Search windows, and pick windows on other Spaces
- Restart and Discard ask for a second click after the first 10 seconds, so one misclick can't throw away a long take
- Cancelling the countdown takes you back to the toolbar you started from
- Device mode looks for iPhones and iPads only when you choose it, and says what to do if none is connected
- Selected-apps audio: Cancel really cancels, and you can add apps that aren't running yet

**Editing**
- The timeline shows edited time: removed parts close up, sped-up clips get shorter, and the ruler matches the time under the preview
- The paused preview updates right away when you add or move an effect
- Smart Speed no longer leaves tiny clips that are hard to select
- The timeline grows to show every effect lane
- Preview quality: Quarter, for long 4K projects
- Each inspector panel and Settings tab opens at the top
- Effect labels are readable in light mode

**Captions**
- The language defaults to your Mac's language
- Progress shows each part as it's transcribed, and when nothing is recognised you see what the recognizer reported

**Export**
- File names use "14.13" instead of "14:13", which Finder showed as "14/13"
- Save panels open in the folder you last used (your Exports folder at first)
- "Export complete" closes by itself after a few seconds unless you point at it
- After "Export and save to file", cancelling the save panel respects "Open quick export widget"
- The export sheet shows a size estimate for GIFs, and Esc no longer closes it from inside a menu
- The editor's quick-export message sits at the bottom of the preview and shows the percentage

**Everywhere**
- Settings → Reset: Return now cancels; resetting takes a click
- VoiceOver reads proper names for the recording controls, countdown, ▾ menu, timeline items and more
- Clicking the Dock icon brings Framecast's open windows forward
- The update window opens centred on the window you opened it from
- Settings is taller, so nothing is cut off
- Shortcuts show the keys of your keyboard layout, and keys that can't be named are refused
- The speaker notes shortcut is shown in the ⚙ menu
- "Move to Trash" confirmations are easier to read

## 1.4.0

- Name a recording and add a note about why you made it, before you record (home screen, display picker or area selector). Notes show on library cards and in the editor
- "Start recording ▾": choose what happens after recording (create project, export and copy to clipboard, or export and save to a file) and whether zooms are created
- The display picker shows the display's resolution and refresh rate
- System audio from all apps, only the apps you choose, or none
- Move and resize blur and spotlight areas right on the video, and drag titles anywhere
- Effect, zoom and clip editors in a cleaner style: "← Close … editor", "Focus the timeline on the start", Disable with an explanation, and full-width Remove buttons
- Dock menu: new recording, record display, open last project, recent projects, show in Dock and settings
- Motion blur no longer softens the picture while the camera settles after a zoom

## 1.3.4

- Recording toolbar: camera, microphone, system audio, folder and ⚙ now light up when you point at them

## 1.3.3

- Framecast now opens straight to the recording toolbar, ready to record. Prefer the home window? Settings → General → When Framecast opens
- Open the home window any time from the toolbar's folder button or ⚙ menu → Open Framecast Window
- Clicking the Dock icon shows the toolbar, or the home window if the toolbar is already open

## 1.3.2

- Six new wallpaper categories drawn by Framecast: Aurora, Waves, Glass, Radiant, Midnight and Mesh (8 each, created the first time you open them)
- "Pick random wallpaper" picks from the category you're viewing
- The home screen header no longer wraps when an update is available

## 1.3.1

- Timeline blocks are lit like real objects: glowing gold clips, vivid indigo zooms and gradient effect blocks, with centred labels
- Wallpapers in a compact grid with categories, and favourites (right-click a wallpaper to add it)
- Quieter waveform: silent stretches are left clean

## 1.3.0

- Cinematic motion blur on the whole screen while zooming and panning, plus Focused and Smooth animation styles (new Animation panel)
- Crop the recording: drag a box with handles, pick an aspect, and the cursor, zooms and effects follow
- Cursor styles (Classic, Thin, High contrast, Warm, Touch), rotation (fixed, tilt or follow), remove shakes, stop moving at the end, loop back to the start, and no more cursor flicker
- Command palette (⌘K) with every editor command, and ⌘1–⌘7 to switch panels
- Timeline: audio waveform, blade tool (scissors button or hold ⌥), cut markers, a preview before adding a zoom, and "Apply speed to all clips" with 16× and 24× speeds
- Recording: hover a display to confirm before recording, an editable area with handles, typed sizes, aspect presets and saved sizes, and a skippable "Get ready" countdown with a 10-second option
- Speaker notes / teleprompter (⌥⌘/ to show, ⌥⌘. to scroll), hidden from the recording
- Directional shadow, inset border, custom two-color gradients with a hue slider, random wallpaper, Reset buttons on sliders
- Quick export to clipboard (⌥⌘C) or file (⌥⌘S), more frame rates (10–60 fps), loop playback, instant zooms, start zooms early, and a Disable toggle for effects
- Fixes: the export window cut off "Web (Low)", Settings showed two selected tabs, and the recording toolbar now sits in the middle of the screen

## 1.2.0

- New app icon
- Light and dark mode: a sun/moon button and Settings → General → Appearance
- Crash-safe recordings: an interrupted recording is still playable and is recovered on the next launch
- More reliable pause and resume: no stale screen after resuming, sound stays in sync
- A refused camera or microphone no longer blocks recording
- Clicks on Framecast's own controls are no longer recorded as clicks (no stray zoom at the end)
- Cancelling an export no longer hangs
- Safer updates: verified downloads, and the app is put back if an update fails
- Caps Lock no longer disables editor shortcuts, and ⌘Z while typing undoes the text
- Many smaller fixes from a full code review

## 1.1.0

- Recording toolbar with Display, Window, Area and Device (iPhone/iPad)
- Live camera preview while recording
- New Settings window: General, Recording, Editing, Quick export, Shortcuts, Advanced
- Customizable global shortcuts and recording flags
- Quick export widget after recording
- Redesigned editor: icon rail, preview quality, playback speed, J/K/L, C and X shortcuts

## 1.0.2

- Drag-to-Applications DMG installer

## 1.0.1

- Build fixes

## 1.0.0

- Effects (blur, spotlight, titles, hide cursor, camera layouts), captions, keystrokes, smart speed
- Self-updating from GitHub releases
