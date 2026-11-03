# Build 26 — teammate whiteboard follow-through

The user supplied a team whiteboard on 3 November 2026 and asked for the app to
be upgraded around it. The numbered notes concern branding, home sections,
step sliding, guide stability, introduction, phone setup, other categories and
future Help. The sketches suggest browsing by activity or material; they do
not define authentication, a profile data model or specific new towel-art steps.

| Team idea | Current implementation |
| --- | --- |
| Branding | Build 25's supplied ProTacta icon and home mark are preserved. |
| Sections on the home page | All / Origami / Everyday / Equipment filters; Origami first; grouped clothes/linens, knots/ties and object/equipment cards. |
| Sliding through a step | Build 25's visible fold timeline remains. Dragging pauses the same fold without confirming a physical action. |
| Stabilise the guide | Everyday/equipment references now start locked, with Adjust / Done. Tracking loss or locking cancels transform gestures; a new begin is required before a changed event can move the reference. |
| Introduction | The skippable first-run tour and its red arrow/interactive preview remain; it can be reopened from Help. |
| Explore phone setup | Visible home entry, a phone/stand/workspace sketch, separate Tabletop AR and Paper guide instructions, and recovery guidance. |
| Finish other categories | The existing five everyday courses / 27 authored movements retain their 3D and tabletop AR flows and now have clear home groups. No unreviewed towel-art procedure is invented. |
| Help, future | Added global playback, AR recovery, voice and mode guidance, with setup and tour actions. General AI conversation remains deferred. |

## Stability changes and limits

Origami already has placement locking and freshness/anchor checks. No new
depth thresholds or person-segmentation tuning are inferred from this whiteboard.
The shared everyday/equipment controller previously accepted pan/pinch/rotation
whenever tracking was ready. It now requires explicit Adjust. Locked models
still accept deliberate part-selection taps. Scale limits, authored geometry,
animation offsets, world anchors and current lesson progress are preserved.

Each transform gesture now records its own active begin. Missing fresh camera
data or a usable pan hit clears that gesture; locking and tracking loss clear
all active transform state. A later changed event cannot reuse old offsets.
This is protection against accidental movement and stale gestures, not a
measurement of physical tracking accuracy or a solution to hand-edge flicker.

Tabletop AR remains manually placed. The natural-paper guide is limited to a
flat A4 centre crease, with separate experimental PTC2 printed-paper support.
The new setup and Help pages start no camera, microphone or recogniser. They do
not certify framing, stand safety, paper registration or real task completion.

## Validation and delivery

Evidence and final build/device receipts are retained under ignored
`output/team-upgrade-build26-2026-11-03/`.

- **34 native tests passed**, including placement size/tracking/handoff, fresh
  gesture gating, everyday/equipment scene state, origami frame health and
  lesson-progress preservation.
- **Nine iPhone Simulator UI cases passed**, covering category filtering and
  return paths, phone-setup modes, global Help → setup/tour, everyday/equipment
  Adjust / Done with preserved partial poses, all five everyday AR round trips,
  the origami fold timeline, introduction replay and equipment detail controls.
- Source captures of the home, setup and Help screens, plus labelled AR
  fixtures, were visually reviewed. The fixtures have no live camera.
- Signed Release 0.1.0 (26) passed strict signature verification and is retained
  at `Final/Protacta.app`. `retained-build-receipt.json` pins source/assets and
  the executable hash. The final install succeeded on the paired iPhone 17
  Pro Max; an independent installed-app query verified build 26 and matched the
  installer's new application container. Automatic foreground launch was refused
  by iOS because the phone had locked. Open Protacta after unlocking; no device
  interaction or physical AR result is inferred from the installation.

No TestFlight upload was performed. Build 24 remains the verified external beta
release. Live hand-edge quality, camera/gesture recovery and learner outcomes
remain separate physical acceptance gates.
