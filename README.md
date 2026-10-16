# Framecast

A native macOS screen recorder inspired by Screen Studio. Record your screen, and Framecast turns it into a polished video automatically: smooth zooms on your clicks, a crisp animated cursor, a nice background with padding and shadow, and an optional webcam bubble.

Built with Swift, SwiftUI, ScreenCaptureKit, AVFoundation and Core Image (Metal). Requires macOS 15 or later.

## Build & run

```bash
scripts/build-app.sh          # builds build/Framecast.app (release)
open build/Framecast.app
```

On first use, macOS asks for **Screen & System Audio Recording** permission (plus Camera and Microphone if you turn them on). After granting screen recording, quit and reopen Framecast.

The build script signs with your Apple Development identity when one is installed, so permissions survive rebuilds. Recordings are stored in `~/Movies/Framecast`.

> Without full Xcode installed, the script builds against the macOS 26 SDK from the Command Line Tools. The macOS 27 SDK's SwiftUI needs Xcode's macro plugins.

## Features

**Recording**
- Record a full display, a single window (with a thumbnail picker), or a dragged area
- System audio, microphone and webcam, each saved to its own file and kept in sync
- 3 s or 5 s countdown, pause/resume, restart, cancel
- Floating control bar and a menu bar timer, both hidden from the recording
- Global shortcut **⌘⇧2** to start or stop from anywhere
- Option to hide desktop icons
- 30 or 60 fps HEVC capture at native Retina resolution
- The cursor is recorded as data (position, clicks, cursor shape), not burned into the video, so it can be restyled later

**Editor**
- Automatic zoom generated from click clusters, with smooth log-space easing
- The camera follows the cursor using a dead zone and spring damping
- Manual zooms: click the zoom lane to add one, drag to move, drag the edges to resize; set the level and choose between following the cursor and a fixed focus point
- Smoothed cursor, size control, high-res vector arrow, motion blur, ripple/ring click effects, a press animation, and hide-when-idle
- Backgrounds: macOS wallpapers, 16 gradients, solid colours, or your own image, with optional blur
- Padding, rounded corners, shadow strength and softness
- Aspect ratios: Auto, 16:9, 4:3, 1:1, 9:16, 3:4
- Webcam bubble: circle, rounded or square; four positions; size; mirror; border; shrinks while zoomed
- Timeline: filmstrip, split (S), cut, trim by dragging clip edges, per-clip speed from 0.5× to 8× with pitch preserved
- Volume for system audio and microphone
- Undo/redo, style presets, a default style for new recordings
- Import existing videos and edit them the same way

**Export**
- MP4 in H.264 or HEVC, 720p / 1080p / 1440p / 4K, at 24/30/60 fps, three quality levels
- Animated GIF
- Show in Finder, copy to clipboard (paste straight into Slack, Mail and similar apps), or open

## Editor shortcuts

| Key | Action |
| --- | --- |
| Space | Play / pause |
| S | Split clip at playhead |
| Z | Add zoom at playhead |
| ⌫ | Delete selected zoom, or cut the selected clip |
| ← / → | Step one frame |
| ⌘Z / ⇧⌘Z | Undo / redo |
| ⌘E | Export |

## Architecture

```
Sources/Framecast/
  App/        App entry, window management, menu bar, headless self-tests
  Recording/  ScreenCaptureKit capture, camera/mic capture, cursor recorder,
              shared RecordingClock (aligns every stream at t=0, removes pauses),
              countdown / area selection / control bar overlays, global hotkey
  Project/    Codable project model, library, presets, EditMap (source ↔ edited time),
              auto-zoom generator
  Render/     CursorPath (spring-smoothed), CameraPath (zoom + follow),
              RenderModel (immutable render snapshot), FrameRenderer (Core Image compositor),
              AVFoundation custom video compositor + composition builder
  Export/     MP4 (AVAssetReader → AVAssetWriter) and GIF export
  UI/         SwiftUI home screen, editor, timeline, inspector, export sheet
```

The same custom `AVVideoCompositing` compositor renders both the live preview (through `AVPlayer`) and the export, so what you see is exactly what you get. Cuts and speed changes are applied with an `AVMutableComposition`. Zooms, cursor effects and styling are drawn per frame by `FrameRenderer`, which works in output pixels, so effects stay sharp at any zoom level.

A project is a folder (`*.framecast`) containing `screen.mov`, `webcam.mov`, `mic.m4a`, `cursor.json`, the cursor images, and `project.json` holding the edits and style.

## Self-tests

```bash
# Render pipeline: builds a project from any video with simulated cursor/clicks, exports MP4 + GIF
build/Framecast.app/Contents/MacOS/Framecast --selftest <video.mov> <outDir>

# Capture pipeline: records the main display for N seconds (with a pause), then exports
build/Framecast.app/Contents/MacOS/Framecast --recordtest 3 <outDir>

# Open a project folder directly in the editor
open build/Framecast.app --args --open <folder.framecast>
```
