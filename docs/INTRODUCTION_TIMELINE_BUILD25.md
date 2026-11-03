# Build 25 — fold timeline, quick tour and branding

The normal origami lesson again exposes a draggable fold timeline. Inspecting
any point pauses playback and preserves the current step; continuing finishes
the same movement. The same control appears for a placed tabletop AR reference.
Compact and voice-only fullscreen layouts retain their existing controls.
The Help sheet's timeline and slow/replay tools remain available.

The first normal launch presents a three-page Quick tour: choose a lesson,
try an interactive fold preview, and learn about optional AR/voice controls.
Red arrows point out the controls and movement direction. Skip and Get started
persist completion separately from lesson progress. About → Quick tour reopens
it. The previews start no camera, microphone, recognition session or real lesson.
Content scrolls with Dynamic Type, the controls have accessibility labels, and
page transitions respect Reduce Motion.

The user-supplied ProTacta artwork is integrated as the app icon and a home-header
mark alongside the readable app name. The source artwork and colours are
preserved; icon production crops the standalone mark and fits it without
stretching onto an opaque square background for iOS masking.

## Validation

Evidence is kept under ignored `output/intro-timeline-build25-2026-11-03/`.

- Seven `LearningControllerTests` passed, covering paused-pose persistence,
  switching/restoring lessons, completion/restart, access and tabletop lifecycle.
- Five distinct iPhone Simulator UI cases passed: direct forward/backward scrub,
  resuming the same fold and AR/3D transitions; Help/speed/replay compatibility;
  clean voice-only fullscreen; Skip/relaunch/replay; and three-page completion
  with an interactive preview and no permission alert.
- The initial run had two test-assumption failures. A native slider exposes a
  31-point accessibility frame inside its 44-point layout row; reachability is
  checked rather than requiring a button-sized native frame. The existing test
  raced a second tap against the 0.35-second Simulator animation; it now pauses
  deterministically through the exposed timeline. The focused rerun passed.
  App playback duration and fold behaviour were unchanged by these test repairs.
- The final branded Release 0.1.0 (25) build passed strict signature verification.
  Its 1024 × 1024 app icon has no alpha channel. The home/introduction replay
  case passed again with the new header assets; the exported home screenshot
  was visually reviewed alongside the icon and introduction/lesson screens.

These are software and layout checks. Real camera alignment, microphone
recognition, physical folding and hand-edge quality have not been revalidated
by this UI change. Build 24 remains the verified external TestFlight release.

## Delivery

The final branded app is retained at `FinalBrand/Protacta.app` within the evidence
folder, with source, asset and executable hashes in
`final-branded-build-receipt.json`. The earlier unbranded app and first interrupted
installation attempt remain separate historical evidence.

The final app installed successfully on the paired iPhone 17 Pro Max. An
independent installed-app inventory confirmed Protacta 0.1.0, build 25, in the
same installation container returned by the installer. Normal foreground launch
succeeded with no fixture or capture arguments. Receipts are `install-final.json`,
`installed-protacta-verified.json` and `launch-final.json`.

This build was not uploaded to TestFlight; the external group still uses Build 24.
