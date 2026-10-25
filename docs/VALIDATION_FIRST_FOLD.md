# First-fold validation record

25 October 2026. Software milestone only; the active complete-course MVP goal
is not complete.

| Evidence | Result | Scope |
| --- | --- | --- |
| FirstFoldLifecycle.xcresult | 81 passed, 0 failed, 0 skipped | 78 logic/synthetic-Vision cases and 3 iPhone Simulator UI cases |
| TabletGuide.xcresult | 4 passed, 0 failed | iPad Simulator direction, loss/recovery, background, reference and landscape controls |
| TabletScreenCapture.xcresult | 1 passed | Repeat of the landscape case with full-screen capture and control-frame bounds |
| device-build.log | BUILD SUCCEEDED | Generic iOS Release compile, code signing disabled; no installation |

Evidence lives in `output/first-fold/`; source hashes and bundle identity are in
`validation-receipt.json`. Earlier initial/regression runs are retained as
history. They are not added to the counts above. The Release bundle excludes
the local StoreKit fixture. The Debug synthetic UI fixture cannot run on a
physical device or in a Release build.

The main test groups cover projective interior points, coordinate origins and
portrait/landscape/aspect-fill transforms; invalid geometry; stale/out-of-order
events and session cancellation; direction continuity and loss; camera request
tokens; existing teaching progress and voice actions; Vision candidate/hand
policies; bounded queue admission; and actual blank/synthetic-sheet pixels
through the Vision worker. No synthetic sample establishes real-paper accuracy.

Independent review found and corrected camera authorization being invalidated
by registration reset, tabletop taps placing an opaque model in paper mode,
and incomplete camera/background recovery. These changes have regression cases.

The simulator UI captures explicitly say NOT A LIVE CAMERA. Portrait,
landscape and the return to the real 3D reference player were inspected.
`preview-synthetic-ipad.png` is the final landscape capture. XCUIApplication's
landscape screenshot crop was unsuitable for review; XCUIScreen full-display
capture preserves the actual landscape layout. Earlier cropped captures are
retained but are not the final preview.

The device inventory reported no available iOS connection. Physical camera
permission behavior, processing latency versus the 350 ms lifetime, paper
movement/deformation, real occlusion and independent alignment error remain
device gates. The source's conservative rectangle/hand thresholds are not
measured guarantees. Later-course CV checks and learner outcomes have not been
implemented or evaluated at this milestone. Later complete-course prototype
work is recorded separately in VALIDATION_FULL_COURSE.md.
