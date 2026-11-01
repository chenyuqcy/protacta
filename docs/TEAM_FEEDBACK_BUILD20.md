# Build 20 — a quieter origami interface

Implemented 1 November 2026 in response to the Capstone team's request for a simpler main flow and Chenyu's IMG_8375 screenshot.

The approved premium catalog, real model imagery, graphite/off-white/green palette and all existing courses are preserved. The shared testing document's participant slots were blank when read; this is a response to team feedback, not a claim of independent learner validation.

## Entry

- Large object preview, paper/step metadata and one Start/Continue button.
- Removed the horizontal origami picker, header library button, prominent practice/alignment buttons and visible restart button.
- View options holds the separate origami library, alternate views, restart and paper tools. The original routes and saved progress remain available.

## Learning

- Three main actions: Back, Next and Help. During playback, Next becomes Pause; a paused fold resumes before advancing.
- Help holds replay, speed, precise scrubbing, written guidance, read aloud, explanations, all steps and the two paper workflows. Opening Help pauses the current animation; closing it preserves the pose. Actions that leave Help run only after dismissal while the app is active.
- The help rows have full-width tap targets, including the space between the label and chevron.
- Hints, replacement and position lock are grouped in view options. Voice remains an optional compact control. Existing touch and voice-only AR fullscreen modes are retained.

## AR and solo use

- AR remains the visual teaching experience. Speech controls the same animated guide.
- The placement screen calls the object a 3D reference beside the learner's paper; tabletop placement does not register to a deforming physical sheet.
- Phone setup gives three short instructions: support the phone, frame the workspace, choose touch or voice. Opening setup starts no camera or microphone.
- Actual A4 guidance, experimental PTC2 checks and the learner-confirmed complete Dart flow retain their existing boundaries. No new general fold grading is implied.

## Verification and release

See `output/team-feedback-build20-2026-11-01/` for Xcode results, screenshots, signed artifact and deployment receipts. The first run identified outdated UI selectors and a real empty-space tap-target issue in Help; these were corrected and the affected journeys rerun.

Latest results per distinct named case across the retained runs: **22 native logic cases and 26 Simulator UI cases passed**. Two tablet-specific cases were skipped on the phone and are not counted as passed. This was scoped regression coverage, not the entire historical suite. Initial failures, subsequent selector changes, the Help tap-target repair and successful reruns are retained in the output logs and `validation-summary.json`.

Phone and iPad layout checks cover the clean entry, current-action controls, Help navigation, pause/scrub/replay/speed, saved progress, the complete learner-confirmed Dart flow, paper-guide recovery and selectable AR fullscreen. AR previews explicitly say **NO LIVE CAMERA**. Normal home → origami → home navigation also passed.

A signed Release 0.1.0 (20) passed strict signature verification and was installed on the iPhone 17 Pro Max. An independent installed-app query reports Build 20. Automatic foreground launch was refused because the phone had locked; the installed update can be opened manually after unlocking. No TestFlight upload was performed for this iteration.

The retained artifact's Swift source hashes match the current application tree. Physical speech, supported-phone usability, real-paper learning and hand-edge occlusion acceptance remain pending. The UI change does not claim to fix the existing hand-edge defect.

## Next learner check

Ask a beginner to find Start, pause/replay a difficult move through Help, and set up the phone independently. Record assistance, hesitation, physical completion and elapsed time. Compare the supported-phone setup with the earlier hand-held attempt. Voice recognition, occlusion quality and real-paper learning are separate physical gates; simulator results do not close them.

The team also asked for a more practical application. Existing towel, product and equipment tutorials remain available; use a short real towel task as the next everyday trial before expanding the catalog further.
