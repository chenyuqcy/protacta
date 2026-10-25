# Protacta Simulator demonstration — 2026-10-26

Delivered locally in `/Users/adrian/Desktop/QCRI/Protacta_Demo_Videos_2026-10-26/`:

| File | Duration | Format |
| --- | --- | --- |
| Protacta_Prototype_Demo_90s.mp4 | 90 s | 1920×1080 |
| 01_Origami_3D_portrait.mp4 | 23 s | 1080×1920 |
| 02_Everyday_Skills_portrait.mp4 | 26 s | 1080×1920 |
| 03_AERIS_Manual_portrait.mp4 | 22 s | 1080×1920 |
| 04_Synthetic_Paper_Flow_portrait.mp4 | 24.067 s | 1080×1920 |

All five are silent H.264/yuv420p MP4 files at 30 fps, with English presentation
text and a persistent Simulator label. The folder also contains four raw captures,
speaker notes, optional SRT captions, a preview, a contact sheet and verification
metadata. `Protacta_Demo_Ready_To_Share.zip` contains the five presentation videos
and supporting text/images; raw footage is available separately in the full folder.

## Demonstrated behavior

- Native Dart 3D folding, replay, view changes, help and final reference.
- Illustrated T-shirt, square-knot and tie lessons from the everyday-skills hub.
- AERIS virtual concept-product guidance: release gate, cover and filter removal.
- Explicitly synthetic paper direction confirmation, hidden cues, recovery and
  frozen manual comparison. This is not footage from a live phone camera.

Everyday lessons do not demonstrate object-specific CV. AERIS does not establish
real-appliance registration. No microphone, cloud AI, fold-grading accuracy or
learning-outcome result is represented. Physical A4 acceptance remains pending.

## Capture provenance and verification

Actual iPhone 17 Simulator / iOS 26.5 footage, captured with `simctl recordVideo`
while XCTest drives the app. The captured app Info.plist reports Build 7. No
production application source changed for this task. The pre-capture HEAD was
`ec290a3c3de69900ad9e10b21a4a26c396e0bc49`; the production source baseline is
`739f2c01696750891441a8dc8a198df72eba80f7`.

Evidence is under ignored `output/demo-video-2026-10-26/`:

- `capture-run01`: completed origami and everyday recordings. The whole UI test
  later failed while entering AERIS exploration; the partial AERIS take is excluded.
- `capture-run02`: AERIS guided flow and synthetic paper flow captured successfully;
  the selected capture test passed. Manifests include events and source snapshots.
  A retry of the Explore parts tap still did not reveal exploration controls, so
  the footage and captions use only verified guided cover/filter interactions.
  This media task did not fix that app behavior.
- `NoOptIn.xcresult`: an ordinary invocation without a capture request deliberately
  skipped the capture test (1 skip, 0 failures). The recording opt-in is single use.
- `qa/raw-decode-and-build.json`: all four selected raw clips decoded completely
  with 30-fps normalization and empty error logs. A direct raw-to-null check
  emitted non-monotonic DTS warnings from Simulator variable frame timing; final
  presentation encodes use constant frame timing.
- `exports/Protacta_Prototype_Demo_90s_work/media_verified.json`: five complete
  delivery decodes passed, 30 fps verified, MP4 faststart verified, hashes saved.
  The master is exactly 2700 frames / 90 seconds. Root visually reviewed the
  42-image contact sheet across all 14 cuts and representative full-resolution
  frames, including the synthetic comparison. This was sampled visual QA, not a
  real-time watch of every frame.

The original Foliafold and AERIS projects were not edited. Only the recording
harness, generated project registration and media tooling were added here.

## Reproduction

See `tools/demo_video/README.md`. Preserve prior capture directories. Simulator
fixtures and rendered demo footage must remain separate from physical acceptance.
