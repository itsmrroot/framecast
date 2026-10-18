# Changelog

## 1.15.2

The editor works more like a video editor.

- **Snapping:** zooms and effects snap to the playhead, cuts, chapters and each other's edges while you drag, with a yellow guide line. Toggle with N or the Snap button; hold ⌘ to drag freely
- **Background music** (Audio panel): add a song; it loops to fill the video, fades in and out, and turns down automatically while you're talking
- **Copy, paste and duplicate** zooms and effects: ⌘C, ⌘V (pastes at the playhead), ⌘D
- **Trim to the playhead:** ⌥[ and ⌥] trim the start or end of the selected zoom, effect or clip
- **Nudge** the selected zoom or effect with ⌥← / ⌥→ (hold ⇧ for a second at a time)
- **Jump between edit points** (cuts, zooms, effects, chapters) with ↑ and ↓; End goes to the end
- **Timeline zoom:** ⌘= / ⌘−, ⇧Z to fit, or pinch on the trackpad
- **Taller timeline:** drag its top edge
- All the new shortcuts are listed in Settings → Shortcuts → Editing

## 1.15.1

- When an update has downloaded, Framecast asks you to restart to use the new version, instead of closing by itself. Choose Restart Now, or Later: the update then installs the next time you quit Framecast

## 1.15.0

**Zoom animation, tuned with research and Screen Studio's measured motion**
- The zoom is now driven by a critically damped spring, stepped every frame. Its curve matches Screen Studio's measurements point for point: about two thirds of the way in 0.2 s, then a soft landing, fully in by 0.77 s
- Because it's a spring, one zoom flowing into another (or changing target mid-zoom) bends smoothly instead of restarting
- Travel zoom-out: when the camera has a long way to go while zoomed in, it eases out a little, pans and comes back in, which is easier to follow than a fast slide at full zoom (the smooth zoom-and-pan path from van Wijk and Nuij's research)

## 1.14.1

- Exports are saved to your Movies folder by default. Pick any folder in the save window as usual, or change the default in Settings → Export
- The export size estimate shows a realistic range (for example "about 110–450 MB"): screen recordings usually come out well below the maximum, at the same quality

## 1.14.0

- **Enhance voice** (Audio panel): one switch cleans up your microphone. It removes rumble, adds clarity, evens out loud and quiet words, and brings the level up. Your original recording isn't changed
- **Zooms follow the whole movement:** an automatic zoom now stays in while you keep moving the cursor after a click (up to 8 s), instead of zooming out halfway through a swipe
- **Record Framecast itself:** Settings → Recording → "Keep Framecast's windows in recordings", for tutorials about Framecast
- Windows reopen on the Space you're on after a recording, instead of on another Space

## 1.13.1

- Fixed: the menu icons didn't show in the released app (apps built with the macOS 26 SDK get text-only menus unless they ask for icons)

## 1.13.0

New tools from the most-requested features for screen recorders (Screen Studio's feedback board and reviews).

- **Text slides:** full-screen title cards for intros, outros and new sections (Effect → Slides). Pick the wallpaper, the blurred video or a colour behind them, and style the text like titles
- **Intro and outro slides add time:** they hold the first or last frame still behind the slide instead of covering your recording
- **Freeze frame:** hold any moment still (Effect → Freeze Frame, or in the clip editor), silently, for as long as you like. Drag its right edge or use the slider to change how long
- **Chapters:** mark where each part starts (Chapters panel or Effect → Chapter Marker), see them on the ruler, and copy a ready-to-paste YouTube chapter list. Flags you marked while recording can become chapters in one click
- **Camera steps aside:** the camera bubble fades when the cursor goes behind it, so it never hides what you're clicking (Camera panel)
- The camera hides during full-screen slides
- Fixed: dragging a title or image on the video lagged behind the pointer
- **Menus like Screen Studio's, with icons:** Framecast (About, Check for Updates, What's New, Website, Send Feedback, Settings), File (New Recording ⌃⌘↩, Record Display / Window / Area / iPhone, After Recording choices, Automatically Create Zooms, Open Recent, Open Project, Open Last Project, Show Recordings, Create Project from Video), Edit Video (split tool, slides, freeze frame, chapters and more), View (every panel ⌘1…8, Show Audio Waveform, Loop Playback, Speaker Notes, Recording Widget, Watch Full Screen) and Window (Reset Window Positions, Start Recording)

## 1.12.1

- Fixed: dragging a title or an image on the video lagged behind the pointer. It now stays exactly under it

## 1.12.0

Tuned to measurements of Screen Studio, recorded frame by frame side by side.

**Smoother recordings**
- Zooms are front-loaded like Screen Studio's: about two thirds of the zoom happens in the first 0.2 s, then it lands softly (0.77 s in all)
- The camera now gets there first: it starts moving as the cursor sets off, heads straight for it, and then holds still, with no slow creep afterwards
- No more sideways sway while zooming out
- Motion blur on every moving frame, in proportion to speed and fading out as the camera slows, with no frame-to-frame flicker
- Automatic zooms now default to 4×, like Screen Studio (change it in the Zoom panel)

**Editor, matched to Screen Studio**
- Clips are Screen Studio's saturated gold, zooms its deeper violet, and blur and spotlight its pink "mask" colour
- Selection is a thin 1 pt outline, with no glow; clips show a light rim when you point at them
- With the split tool on, the lanes gently bob in a slow wave, like Screen Studio's, until you turn it off

## 1.11.1

- Fixed two Framecast icons (and two recording timers) in the menu bar: an old built-in menu bar item was still there next to the new one

## 1.11.0

- The split tool moves like Screen Studio's: turning it on or off makes the timeline lanes dip and spring back, one after another
- Each cut gives its lane the same little bounce
- With the split tool on, the lane under the pointer lifts slightly, so you can see which lane a click will cut
- Timeline colours sampled from Screen Studio and always lit: gold clips (darker top, glowing bottom), bright violet zooms, and pinker titles. Other blocks no longer dim when one is selected
- The filmstrip and waveform inside clips are fainter, so the gold reads clearly

## 1.10.0

**Smoother zooms, no surprise blur**
- Zooms move like a spring: quick to start, gentle to land, in and out. The default zoom is a little faster (0.65 s)
- While zooming in, the camera moves and zooms in one motion, so it no longer keeps sliding afterwards
- Following the cursor is quicker and smoother: a little lookahead, a soft edge zone and no slow drift
- The whole picture no longer blurs when you move the cursor: motion blur only follows real camera movement, and is gentler by default
- The cursor trail only shows on very fast flicks, and is short and faint
- One sharp scaling filter at every zoom level, so text doesn't soften or jump in sharpness mid-zoom

**Editing**
- Type straight into a title on the video: click it (a new title opens ready to type), Return to finish
- Watch your video full screen (button under the preview, or F). Space plays, Esc leaves
- Click the wallpaper around the recording to open the Background settings, as in Screen Studio
- Title styling shows right away, and a new effect is visible as soon as you add it (it used to start invisible at the playhead)
- The look you pick stays highlighted when you change the typeface or colours ("Midnight, edited"), and each change is its own undo step
- The playhead no longer slips back a frame after each edit
- With a blur or spotlight selected, clicking the video can still select another effect
- The on-video editing box only shows while the effect is on screen
- Dragging an effect that starts inside a cut keeps its length

## 1.9.0

**Menu bar**
- Framecast now has a menu bar item, like Screen Studio: new recording, record display / window / area / iPhone, speaker notes, open the last or a recent project, open any project, show recordings, show in Dock, settings, updates and quit, with shortcuts shown next to each
- While recording it shows a red dot and the elapsed time, and the menu has Stop, Pause / Resume, Restart, Add Flag, Show / Hide Controls and Discard
- Turn it off in Settings → General (it stays while the Dock icon is hidden, so you can always reach Framecast)

**Timeline, matched to Screen Studio** (from a side-by-side test)
- The split tool cuts only the lane you click: the clip, a zoom or an effect, not everything at that moment
- New scissors pointer: upright, crisp outline, hollow finger rings
- Splitting shows a red line under the grey hover pin, as in Screen Studio
- Lanes fold by pointing: zooms are open and effects are thin bars; point at the effects and they open while zooms fold
- Hovering the timeline previews that moment in the video and the time display, without moving the playhead
- Bright zooms, white double ring on the selected block, and other blocks of the same kind dim
- Zoom labels read "4×  Auto" (no "2,0×"), clips read "45s", and the shape icon follows the shape

**Fixes**
- Dragging a title or image on the video works from anywhere on it (it only worked from the top-left corner)
- New images and arrows show right away on the paused preview
- Cut / Speed Up Silent Pauses now find pauses in normal room noise, and say so when there are none
- Settings → Shortcuts warns when another app (Screen Studio, for one) already uses a shortcut
- The image picker opens in Pictures

## 1.8.0

New editing tools, picked from what people ask Screen Studio for most.

- **Images over the video:** add a logo, screenshot or sticker (+ Effect → Image). Drag it on the video to place it and drag its corner to resize. Rounded corners and a shadow are optional
- **Arrows and shapes:** point at a button with an arrow (eight directions), or draw a box or circle around what matters. Pick a colour and thickness. They follow the zoom, like blur
- **Move the camera after recording:** for any part of the video, the camera bubble glides to another corner and size, then back. Handy when it covers something
- **Edit by transcript:** after generating captions, the scissors next to a line cuts that part out of the video
- **Remove silent pauses:** Smart Speed → Cut Silent Pauses, or speed them up 4×
- The split tool's pointer is now a pair of scissors

## 1.7.0

**Timeline**
- The split tool works like Screen Studio's: turn it on with the scissors (or S) and it stays on. A red line with a scissors pin follows the pointer, and each click cuts straight through the clip, zooms and effects. Click the scissors again, or press S or Esc, to stop. C still cuts at the playhead
- New colours and light, matched to Screen Studio: gold clips lit from below, dark zooms that glow violet with a double ring when selected, deeper effect colours, a blue playhead pin, a pin that follows the pointer, and a dotted ruler
- Scroll down over the timeline and the zoom lane folds into a thin strip; scroll back up to open it. Lane changes animate smoothly
- Effects show their type and name, like clips and zooms

**Titles**
- Dragging a title on the video is instant: it follows the pointer exactly, with no delay
- Click a title, blur or spotlight on the video to select and edit it

## 1.6.0

**Titles you can style**
- Eight one-click looks: Classic, Midnight, Frosted, Keynote, Bubble, Editorial, Terminal and Poster
- Apple's typefaces: SF Pro, SF Pro Rounded, New York and SF Mono, plus condensed and expanded SF Pro
- Five weights, left / centre / right alignment, and an optional subtitle line
- Text in Apple's system colours or any colour you pick
- Backgrounds: light card, dark card, coloured card, frosted glass that blurs the video behind it, or just the text with a soft shadow
- New titles take the look of the last one, so a video's titles match

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
