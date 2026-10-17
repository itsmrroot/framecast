You're helping me QA and compare two Mac screen recorders: Screen Studio (reference) and Framecast (my app, the one I'm building). Use computer use to drive both apps. Work carefully and take screenshots as evidence.

## Ground rules
- Don't delete, rename or modify any existing recordings in Screen Studio or in ~/Movies/Framecast. Make your own short test recordings (10–20 s) and name them starting with "QA-".
- When finished, move only your own QA- test projects to the Trash (both apps), and tell me which ones you trashed.
- Don't change app settings unless a step needs it; if you do, note the original value and put it back at the end.
- Don't buy, sign in, or accept anything. If an app asks for a licence, permission or update, stop and tell me.
- Save screenshots to ~/Desktop/Projects/framecast/docs/qa/timeline/ (create the folder) with descriptive names, e.g. ss-split-hover.png, fc-split-hover.png.
- Write your report to ~/Desktop/Projects/framecast/docs/qa-timeline-report.md.

## Part 1: Screen Studio's split tool (most important)
Make a Screen Studio test recording with some clicks, so it has automatic zooms. In the editor add at least one mask/blur and one other effect, positioned so a zoom AND a mask both span the same moment in the middle of the clip. Then:
1. Turn on the split/scissors tool. Describe exactly how it's turned on (button, shortcut) and how it's turned off (click again? shortcut? Esc? after one cut?).
2. Hover the timeline. Screenshot it, zoomed in if possible. Describe the pointer: its shape (scissors? crosshair?), colour, size and outline, and whether it changes over different lanes (clip lane, zoom lane, mask lane, ruler, empty space).
3. Describe the cut indicator: the vertical line (colour, thickness, how far down it reaches) and any pin or badge at the top (shape, colour, icon).
4. Click to cut at a moment where the zoom and the mask both span. Then answer precisely:
   - Did the clip split?
   - Did the zoom split into two zooms, or stay as one?
   - Did the mask/effect split, or stay as one?
   - Can you cut by clicking the zoom lane or the mask lane, or only the clip lane?
   Screenshot before and after the cut.
5. After a cut, what marks the cut point (a scissors pin in the ruler? a gap?). Can you select and delete one of the two pieces? Does the timeline close up (ripple) when a piece is deleted?
6. Do the lanes animate or move when the split tool turns on or off, or while you hover? Describe any smooth movement.

## Part 2: Timeline look: Screen Studio vs Framecast
Open a Screen Studio project and a Framecast project of similar length, at the same window size. Screenshot both timelines in each state:
- nothing selected
- a clip selected
- a zoom selected
- an effect/mask selected
- split tool on and hovering
- scrolled down inside the timeline (does the zoom lane shrink to a thin strip?)
For each pair, list concrete differences: colours (give approximate hex values if you can), gradients and "light" (glow, rims, highlights), corner radius, lane heights, spacing, label text and fonts, ruler style (ticks, dots, labels), the playhead (pin, colour), hover indicator, and selection style (rings, borders). Put the side-by-side screenshot filenames next to each difference.

## Part 3: Test these Framecast 1.8.0 features
Make a Framecast test recording (with the mic on, and speak a few sentences), open it in the editor and check:
1. Split tool (scissors under the video, "Split" above the timeline, or S): over the timeline the pointer should turn into white scissors with a dark outline. Report whether it does, on which lanes, and whether it stays on until you click again or press S/Esc.
2. Effect → Image: pick any PNG/JPEG (e.g. from ~/Pictures). Drag it on the video and resize it with the corner handle. Does it follow the pointer exactly, with no lag? Does it stay where you dropped it?
3. Effect → Arrow or shape: try arrow (several directions), box and circle, plus colour and thickness. Do they follow zooms? Can you move and resize them on the video?
4. Effect → Move camera (only if a webcam is available): does the bubble glide to the chosen corner and size and back?
5. Click a title, image, blur or arrow directly on the video. Does it get selected?
6. Drag a title on the video. Is there any delay between the dashed frame and the text?
7. Captions → Generate, then press the scissors next to one line. Is that part removed from the video, and does the timeline close up?
8. Smart Speed → Cut Silent Pauses and Speed Up Silent Pauses 4×. Does it find the pauses? Does it cut words off?
9. Scroll down inside the timeline. Does the zoom lane fold into a thin "Zooms" strip smoothly, and come back when you scroll up?
For each item: Pass / Fail / Partly, steps to reproduce, and a screenshot of any problem.

## Report format (docs/qa-timeline-report.md)
1. Summary: the 5 most important findings.
2. Screen Studio split tool: exact behaviour, especially which lanes a cut affects (clip only, or zooms and masks too).
3. Timeline differences table: Area | Screen Studio | Framecast | Screenshot(s).
4. Framecast 1.8.0 test results (items 1–9).
5. Anything else that looked broken or odd.
6. What you trashed and any settings you changed and restored.
