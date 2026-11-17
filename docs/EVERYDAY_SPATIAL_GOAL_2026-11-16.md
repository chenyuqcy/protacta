# Everyday 3D and AR goal

User-confirmed scope, 16 November 2026: finish the selectable **everyday-life**
lessons. Electrical appliances, gearmotors and aircraft engines are excluded.
Keep the existing origami flow intact. Build 32 is the local development candidate
in `org.realitycore.protacta.prototype`; it is not an App Store release.

## Completion contract

Every lesson must have its own complete 3D shape, a continuous movement for each
action, pause/replay/slow motion and a draggable timeline, studio and tabletop AR,
voice controls, manual action confirmation and saved progress. Test geometry,
actual rendered meshes, navigation and physical device behavior separately.
Do not count an animation ending as proof the learner completed a real task.

| Lesson | Complete sequence | Real-object guidance scope |
| --- | --- | --- |
| Towel | Left third, right third, fold strip in half (3) | Three corners of a flat rectangular towel; manual width, length and orientation calibration |
| T-shirt | Left side, left sleeve, right side, right sleeve, hem fold, final fold (6) | Left/right hem and left outer shoulder seam of a flat short-sleeve shirt; approximate authored body shape |
| Flat bedsheet | Long edges, short edges, narrow rectangle, final packet (4) | Three corners of a flat sheet on a level surface; not fitted sheets |
| Square knot | First cross, tuck, opposite cross, tuck, tighten (5) | Complete tabletop rope reference; no automatic registration or tension simulation |
| Four-in-hand tie | Cross, wrap behind, cross front, neck loop, front loop, tighten, position (7) | Complete tabletop ribbon reference; no on-body or automatic tie tracking |

All 25 authored actions already existed at the start of this goal. The new work
must improve and verify them, rather than count existing code as new delivery.

## Stages and acceptance

1. **Inventory and continuity** — sample all five meshes over every action;
   preserve endpoints and eliminate sudden tube/ribbon frame flips. Confirm
   each object stays recognizable throughout the lesson.
2. **Shared everyday player** — expose the timeline directly in AR; maintain the
   exact paused pose when opening Help, leaving AR or cancelling calibration.
   Keep UI compact and voice-only fullscreen free of playback controls.
3. **Manual flat-object overlay** — opt-in three-point capture for cloth only,
   with named points and a small diagram; hide the model during capture. Reject
   stale tracking, incorrect corner order, different planes and invalid spans.
   Commit only after all points validate. Keep previous placement on cancel.
   Start the aligned reference flat, without changing saved confirmations.
   Offer a translucent guide and lock placement. Moving the item requires
   realignment. Automatic cloth recognition/deformation tracking is not claimed.
4. **Local verification** — focused native tests for all 25 actions and
   registration math; Simulator UI tests for all five courses, timeline, mode
   changes, cancellation, resume and tablet layout. Label simulated camera
   layouts explicitly. Build a signed iPhone candidate after these checks pass.
5. **Physical acceptance** — install the candidate and test all five courses.
   For cloth, compare the three starting landmarks, then every action before and
   after. Check fixed-camera/hand-edge behavior, placement stability, interruption,
   voice commands, progress resume and re-alignment after moving the real item.
   Record failures before further release. Keep this stage open without evidence.

## Why three points

ARKit's raycast maps a chosen screen location to a detected physical surface.
This supplies coordinates, not garment recognition. We require a detected
horizontal plane for calibration, then fit authored X/Z dimensions to the
learner-selected landmarks. The material can be translucent so fabric remains
visible. Shape mismatch and fabric thickness still require physical validation.

- [Apple: placing objects and handling 3D interaction](https://developer.apple.com/documentation/arkit/placing-objects-and-handling-3d-interaction)
- [Apple: material transparency](https://developer.apple.com/documentation/realitykit/physicallybasedmaterial/blending-swift.property)

## Verification record (Build 31 baseline)

- **Implemented:** all five lessons retain full 3D/AR playback; AR gains the
  visible timeline; the three flat-cloth lessons gain manual calibration,
  named-point diagrams, a translucent guide and tracking/error recovery.
- **Geometry corrected:** parallel-transported knot/tie frames remove abrupt
  upright twists. Cloth dimensions are applied before hinge rotations, so a
  differently proportioned real item does not stretch its raised flaps.
- **Core native tests:** 68 passed, 0 failures. Actual mesh creation, every
  action's continuity, scaled-cloth rigidity, registration math, course/session
  state and playback are covered in `output/everyday-upgrade-20261116/FinalNative.xcresult`.
- **Signed build:** local 1.0 (31), `org.realitycore.protacta.prototype`, verified
  with `codesign --verify --deep --strict`. Receipt and executable hash are in
  `output/everyday-upgrade-20261116/candidate-build31.json`.
- **iPhone Simulator UI:** all seven cases passed across the original run and
  the corrected-menu rerun. Coverage includes five-course AR scrubbing/return,
  explicit practice progression, cancellation, backgrounding, unsupported AR,
  voice-only presentation and recovery. First-run menu dismissal tapped an
  obscured button; the test now taps outside and verifies the unchanged pose.
  Receipts: `PhoneUI.xcresult` and `PhoneUIRetry.xcresult` in the output folder.
- **Visual review:** reviewed five lessons' first-action middle/target images
  and three calibration panels. No clipped controls or broken meshes observed.
  This does not establish later-action visual quality or physical alignment.
- **iPad Simulator UI:** both the five-course AR case and portrait/landscape
  rotation check passed with no failures (`TabletUI.xcresult`).
- **Device:** installed and independently verified `bundleVersion: 31` on the
  paired iPhone 17 Pro Max; launch succeeded. Receipts: `install.json`,
  `device-apps-after.json`, `launch.json` and `candidate-build31.json` in the output
  folder. The initial locked-phone attempt is retained in its own log.
- **Physical acceptance:** pending. First requested check is towel timeline
  playback on the real phone. Cloth-to-object fit, hand boundaries, all 25 real
  actions and real voice still require user feedback. The overall goal is active.

## Full-course review and Build 32 follow-up

- The full-course flow passed for all five lessons: all 25 actions, explicit
  confirmation, completion, close/reopen and the restored final pose.
  `FullCourseReview.xcresult` contains 65 named screenshots, including the
  midpoint and target of every action. Exports are in `full-course-screenshots`.
- Visual review of the sampled towel, shirt, sheet and square-knot poses found
  no missing surfaces, obvious detached pieces or clipped controls. Cloth is
  still an authored hinged reference, not a fabric simulation. Same-color
  layers are subtle in a resting pose; orbiting/playback remains important.
- The tie review found incorrect front-band threading at action 5, inherited
  by 6–7, and an exposed narrow tail at completion. The route now puts the
  descending wide blade behind the front band; the tail follows its back
  through the keeper. Two complete collar surfaces replace the thin triangles.
  Teaching reference: [The Tie Bar four-in-hand guide](https://www.thetiebar.com/how-to-tie/four-in-hand).
- Re-rendering exposed an extra 180-degree roll during action 6. Removing the
  cross-section sign reversal corrected it while retaining temporal and
  neighbouring-ring continuity. A dedicated sampled regression guards against
  this unnecessary twist. The final action-6 middle image shows the broad face.
- `TieFinal.xcresult`: all 13 knot/tie geometry tests, four actual RealityKit
  mesh/controller tests and the tie UI flow passed. New surface tests verify
  front-band depth, full-width tail concealment and collar coverage. The updated
  middle/target screenshots are in `tie-final-screenshots`. The final tie is
  still an open teaching reference, not a photorealistic tensioned cloth knot.
- Completed lessons now retain their final model pose: Start position is
  disabled and Help scrubbing/calibration are unavailable until the learner
  explicitly goes back or starts again. This prevents a flat model appearing
  under a completed-course label.
- Calibration now explains why Set point is unavailable: tracking recovery or
  missing detected surface. No sample is invented by the Simulator fixture.
- `CompletionFix.xcresult`: 16 focused native tests and two UI tests passed,
  including completed-state behavior and cancellation without losing progress.
  These overlap earlier native coverage and must not be added as unique tests.
- **Current signed/device candidate:** 1.0 (32), development bundle
  `org.realitycore.protacta.prototype`. Final Release build and strict signature
  verification passed. Installed on the paired iPhone 17 Pro Max; an independent
  app inventory returned `bundleVersion: 32`, and the launch receipt returned
  success. Receipts are in `output/everyday-upgrade-20261116/build32`; current
  executable hash and aggregate verification are in `candidate.json`. The
  Build 31 receipt is retained as `candidate-build31.json` and its app as
  `Build31.app`. Installation and launch do not satisfy physical acceptance.

## Physical acceptance checklist

Use the same installed build for the checks below. A successful install is not
a successful physical test. Mark only behavior actually observed on the phone.

| Course | Continuous playback / scrub | AR placement / hands | Real-item fit | Resume / voice |
| --- | --- | --- | --- | --- |
| Towel, 3 actions | Pending | Pending | Three flat corners, pending | Pending |
| T-shirt, 6 actions | Pending | Pending | Hem corners + left shoulder, pending | Pending |
| Flat bedsheet, 4 actions | Pending | Pending | Three flat corners, pending | Pending |
| Square knot, 5 actions | Pending | Pending | Tabletop reference only | Pending |
| Four-in-hand, 7 actions | Pending | Pending | Tabletop reference only | Pending |

For each cloth course: lay the item flat on a level surface; enter AR, choose
More → Align with my item, then capture the three named points in order. Check
the flat outline first. Scrub each fold slowly and compare its before/after
shape. The reference stays at the calibration location; if the cloth moves,
realign it. Test hand occlusion and moving away/back separately. For both knot
lessons, compare the 3D reference beside the real cord/tie; it does not track
the real strands or fit a person's body.

## Final audit: physical feedback required

The Build 31 implementation turn, Build 32 correction/install turn and the
following completion audit all reached the same remaining gate: learner
feedback using the actual phone and objects. The final read-only code audit
found no further definite local defect to repair. Completed local tests are
not being rerun as a substitute for physical acceptance.

A fresh device copy (`build32/device-ar-diagnostic.json`) contains a Build 32
sample at `2026-11-16T18:30:24Z` with `placed: true`, `trackingReady: true` and
`manualObjectAligned: false`. The app process was independently observed live
as PID 22256 in `build32/processes-audit.json`. This is evidence of an AR
placement session, but the shared diagnostic has no course identifier. It
cannot prove towel playback, cloth registration, hand-edge quality or speech
acceptance. The pending first question remains the towel scrub/next-action
check. The goal is awaiting those physical observations before it can complete.

## Subsequent local interface work

At the user's request, the five everyday courses were exercised in the Simulator;
see `SIMULATOR_WALKTHROUGH_2026-11-16.md`. A subsequent design pass produced local
candidate Build 33; see `INTERFACE_REFINEMENT_2026-11-16.md` for changes, receipts
and remaining checks. This does not replace the physical acceptance above, and
Build 32 remains the last verified installation on the user's iPhone.

The next local pass produced **Build 34**, with five real-model catalog portraits
and scaled cloth thickness/closed edges. It passed 29 geometry tests and four
Simulator UI cases, including all 13 cloth actions and five-course AR-layout
transitions. See `EVERYDAY_MATERIAL_REFINEMENT_2026-11-16.md`. This does not close
the physical acceptance checklist or change the last verified iPhone build.

On 2026-11-17, **Build 35** added per-action framing and explicit paused-fold
focus. Nine Simulator tests passed across iPhone and iPad. Signed installation
and independent iPhone inventory verification confirm version 1.0 (35), replacing
Build 32 as the last verified installed candidate. The first launch was blocked
by the phone's lock screen; physical interaction acceptance is still pending.
See `EVERYDAY_STEP_FOCUS_2026-11-17.md` and `output/step-focus-20261117/`.
