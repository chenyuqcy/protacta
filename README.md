# Protacta native development app

An isolated startup app derived from Foliafold 1.0.1 Build 11. The original
`/Users/adrian/Desktop/QCRI/origami_ar_demo` project is not modified.
The source snapshot and SHA-256 hashes are in `docs/FOLIAFOLD_BASELINE.json`.

Current prototype identity: **Protacta 0.1.0 (1)**,
`org.realitycore.protacta.prototype`, iPhone and iPad, iOS 17 minimum.
This is a local development identity, not an App Store listing or migrated
Foliafold purchase entitlement.

## Current milestone

The free Classic Dart lesson has a **Guide on my paper** entry. On a supported
device it uses a single ARKit camera session, bounded on-device Vision work,
paper-boundary candidates and a projective mapping to draw the center crease,
the target edge and an arrow on a visible flat sheet.

The person confirms the guide's direction because a blank rectangle cannot
establish semantic orientation. Subsequent nearby detections preserve corner
identities. Lost, stale, cropped, ambiguous or discontinuous observations hide
the folding cues and require a fresh direction check. Recognized hands near
the sheet conservatively reject the observation; this does not guarantee
detection of every occluder. Backgrounding and camera failure invalidate the
registration and pending authorization work.

This first milestone does **not** grade a fold, identify a real A4 sheet with
certainty, track arbitrary deformation, or support later folded shapes. A
rectangle candidate can also be a book or screen. Use one whole A4 sheet on a
clear table and verify the highlighted TOP edge. The learner explicitly
confirms completing the center crease and continues in the existing 3D lesson.
Animation progress and camera registration remain separate.

Existing 3D lessons, tabletop model placement, local learning progress and
English voice controls remain in the fork. Product identifiers and test
fixtures are isolated from Foliafold.

## Build and test

Source folders retain the historical PaperSteps names. Regenerate after adding
Swift files or resources:

```sh
python3 scripts/generate_xcode_project.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Protacta.xcodeproj -scheme Protacta -destination 'generic/platform=iOS Simulator' -derivedDataPath output/DerivedData build
```

For the focused automated checks, choose an available simulator UDID:

```sh
scripts/test_first_fold.sh SIMULATOR_UDID
```

The `Protacta-StoreKit` scheme uses a local, prototype-namespaced test fixture.
The ordinary scheme does not use that fixture. Simulator-only synthetic UI
fixtures require a Debug build and both `--ui-testing` and
`--paper-guide-fixture`. They visibly say **NOT A LIVE CAMERA**; the argument
cannot enable the fixture in a Release build or on a physical device.

## Physical acceptance

Open Classic Dart and Guide on my paper. Allow camera access, keep a whole flat
sheet visible, confirm the highlighted TOP direction and try movement,
rotation, changing distance, partial occlusion and removal. Check that cues
disappear on uncertainty, that a new direction is requested after loss, and
that returning from Settings/background can restart the camera. Repeat on
iPhone portrait and iPad portrait/landscape. Confirm that the opaque tabletop
model never appears in real-paper mode.

No camera frames, detected hands or microphone audio are uploaded. The
current alignment thresholds and 350 ms observation lifetime require device
latency and accuracy measurements. Synthetic-image tests and simulator
screenshots do not establish physical acceptance.

## Next stages

The active goal is the single complete-course MVP in
`docs/BUILD_PLAN_2026-10-25.md`. After real-paper acceptance, author the complete
course checkpoint coverage, collect correct/incorrect/unclear samples, add
limited visual checking and reviewed correction, then run the beginner pilot.
Progress and evidence are maintained in `docs/PROGRESS.md`.
