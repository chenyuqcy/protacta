# Protacta native development app

An isolated startup app derived from Foliafold 1.0.1 Build 11. The original
`/Users/adrian/Desktop/QCRI/origami_ar_demo` project is not modified.
The source snapshot and SHA-256 hashes are in `docs/FOLIAFOLD_BASELINE.json`.

Current prototype identity: **Protacta 0.1.0 (4)**,
`org.realitycore.protacta.prototype`, iPhone and iPad, iOS 17 minimum.
This is a local development identity, not an App Store listing or migrated
Foliafold purchase entitlement.

## Complete-course practice prototype

**Practice the complete Dart** provides ten actions, local progress, comparison
notes, help and a 3D reference that returns to the same practice action. Only
the learner's explicit confirmation advances this session. Voice can read the
current action/help or open its 3D reference; saying Next step does not certify
or confirm the physical action.

The printed-paper Plan B uses four QR codes on the paper itself to establish
position and direction. The practice sheet is bundled with a print/share entry;
see `docs/DART_PRACTICE_SHEET.md`. All four codes must be visible, with white
A4 paper on a plain dark mat. The known flat region supports planar cues before
actions 1 and 3-7. When paper lifts, markers disappear, tracking becomes limited,
or observations become stale, cues hide. Other actions retain their 3D/manual
path. A marker on the table is not treated as a paper anchor.

**Check my step** compares the visible silhouette after actions 2-6. Outcomes
are scoped visible match, compare/adjust the outline, or cannot judge. State 2
has the same silhouette as a new sheet and cannot establish a center crease.
Hidden layers, crease pressure, arbitrary objects and nonplanar wings are not
evaluated. Progress saves bounded text summaries, not photos, live pose or camera
coordinates. Both teaching content and thresholds await physical-paper review.

Build 4 adds **See this comparison** after an accepted camera check. A temporary
grayscale image, reference outline and softly highlighted comparison areas come
from the same checked frame. The learner can inspect the frozen view, read the
action's draft comparison notes or replay that same action in 3D. It does not
advance the course or identify which hidden fold caused a difference. Returning
to the camera clears the image and starts fresh registration; action changes,
rescan, tracking loss, camera failure, backgrounding and exit also clear it.
Normal use keeps only the bounded image in memory and never saves a photo.

## First-fold natural-boundary prototype

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

Build 3 fixes shadow ambiguity and pixel-center sampling in the outline checker.
It also adds opt-in Debug local camera sampling and a separate offline evaluator.
Normal practice and Release builds do not expose photo recording. See
`docs/LOCAL_VALIDATION_CAPTURE.md` and `docs/VALIDATION_DATA_FORMAT.md` before
collecting real samples; synthetic fixtures are never physical acceptance.
Build 4's frozen comparison, lifecycle checks, final visual review and unsigned
Debug/Release builds are recorded in `docs/VALIDATION_VISUAL_FEEDBACK.md`.

Source folders retain the historical PaperSteps names. Regenerate after adding
Swift files or resources:

```sh
python3 scripts/generate_xcode_project.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios/Protacta.xcodeproj -scheme Protacta -destination 'generic/platform=iOS Simulator' -derivedDataPath output/DerivedData build
```

For the focused automated checks, choose an available simulator UDID:

```sh
scripts/test_first_fold.sh SIMULATOR_UDID
scripts/test_dart_practice.sh SIMULATOR_UDID logic
scripts/test_dart_practice.sh IPHONE_SIMULATOR_UDID phone
scripts/test_dart_practice.sh IPAD_SIMULATOR_UDID tablet
python3 -m unittest discover -s scripts/tests -p 'test_evaluate_practice_validation.py' -v
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

The engineering objective is the single complete-course MVP in
`docs/BUILD_PLAN_2026-10-25.md`. Complete-course code and synthetic checks are
prototype evidence. Real-paper registration, actual tutorial review, independent
correct/incorrect/unclear samples and the beginner pilot remain acceptance gates.
The user chose to continue local development and defer physical testing on
25 October 2026; Build 4 follows that choice.
Progress and evidence are maintained in `docs/PROGRESS.md`.
