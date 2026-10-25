# Protacta engineering progress

Goal: implement the complete-course startup MVP in BUILD_PLAN_2026-10-25.md.
Status: physical gate blocked by unavailable iOS devices. The ten-action practice
prototype and local validation tools are implemented; real-paper review, device
acceptance, independent samples and beginner outcomes remain unproved.

## Build 3: check reliability and real-validation preparation

- Fixed gray shadows outside the expected silhouette being ignored. Narrow
  white/dark interpolation footprints are distinguished from actual gray areas,
  preserving clear visible-error feedback instead of collapsing it to unknown.
- Corrected raw normalized image coordinates to pixel centers (`x * width - 0.5`).
- Added explicit Debug-only local camera capture with same-frame image, hash,
  step, semantic pose and processing timestamps; lifecycle changes cancel work.
  No photo is saved in normal use, and simulator drawings cannot become physical
  evidence. See LOCAL_VALIDATION_CAPTURE.md.
- Added independent paper-width error, three-way outcome and timing reports;
  PNG integrity, split leakage, candidate versions and unfinished exports are
  checked. Human labels stay separate. See VALIDATION_DATA_FORMAT.md.
- 168 App logic/synthetic tests and 24 Python tests passed. The actual native
  exporter output was accepted by the offline evaluator as one explicitly
  synthetic contract fixture, not real accuracy or learning evidence.
- New phone/tablet capture UI cases passed. An old iOS 18 simulator launch
  crashed once in CoreRE/CoreMedia; the case passed on an isolated rerun. The
  original failure is retained and physical stability remains a gate.

See VALIDATION_CHECKER_AND_CAPTURE.md and GOAL_ACCEPTANCE_AUDIT.md.

## Complete-course prototype

Protacta 0.1.0 (2) adds a separate ten-action Dart practice session, explicit
learner confirmation, previous/restart, local progress, authored comparison/help
and a 3D reference that returns to the same practice action. Animation, user
confirmations and camera summaries remain separate. Voice reads the current
practice action/help or opens its 3D reference; Next step does not confirm paper.

Printed-paper Plan B uses four QR IDs on the sheet, independent code-corner
checks, a single in-flight 4 Hz worker and camera/step/viewport/generation guards.
The A4 sheet is bundled with a print/share entry. Stale, missing, duplicate,
occluded or unsupported observations hide cues. Camera checks compare only an
experimental white-paper/dark-mat silhouette and never advance the course.

| Action | Planar cue before action | Outline check after action |
| --- | --- | --- |
| 1 | Starting flat sheet | Manual / 3D |
| 2 | Manual / 3D | Outer boundary only; center crease unknown |
| 3-6 | Candidate flat starting states | Experimental visible silhouette |
| 7 | Flat starting hinge cue; hide on lift/loss | Manual / 3D |
| 8-10 | Manual / 3D | Manual / 3D |

Teaching notes and support assumptions remain draft until reviewed with actual
paper. Lower-sheet codes do not prove that every part of the sheet is planar.
White occluders and hidden layers may be indistinguishable in an outline image.
Progress stores bounded text summaries, not photos or live camera coordinates.
See VALIDATION_FULL_COURSE.md and PHYSICAL_VALIDATION.md.

Current software validation: 144 logic/synthetic-Vision tests, 5 iPhone UI cases
and 7 iPad UI cases passed. Generic iOS Release build 2 compiled without signing;
no installation or real-camera acceptance is established. The final UI captures
were visually reviewed, including button contrast and persistent fixture labels.

## Earlier first-fold milestone

- Isolated development app and prototype bundle/product/progress namespaces.
- Recoverable Git baseline from 85 Foliafold Build 11 source/resource files.
- On-device rectangle detection with a bounded single-frame worker, raw-image
  coordinate handling, conservative hand/candidate rejection and generation checks.
- Projective mapping, coordinate conversion, direction confirmation, identity
  continuity and stale/invalid registration hiding.
- Single-session real-paper mode, visible center crease and target/action cues,
  camera permission/recovery, background invalidation and learner confirmation.
- Existing 3D reference and tabletop modes remain separate.
- Focused logic, synthetic Vision and simulator UI tests with explicit fixture labels.
- Complete Classic Dart state/checkpoint coverage draft in CLASSIC_DART_COVERAGE.md,
  explicitly awaiting real-paper review.

## Earlier first-fold validation

- 78 logic and synthetic-Vision tests plus 3 iPhone Simulator UI tests passed.
- 4 iPad Simulator UI tests passed; the landscape case was repeated to verify
  bounds and capture a correct full-display screenshot.
- Generic iOS Release compilation passed with signing disabled; the bundled
  StoreKit test fixture is excluded. No installation is established.
- Source hashes confirm the 85 original Foliafold baseline files are unchanged.

See VALIDATION_FIRST_FOLD.md and output/first-fold/validation-receipt.json.

## Next acceptance gate

- [ ] Real iPhone paper detection and portrait mapping.
- [ ] Real iPad portrait/landscape mapping and camera recovery.
- [ ] Measure processing latency against the observation lifetime.
- [ ] Test paper movement, occlusion, ambiguous backgrounds and folded-sheet rejection limits.
- [ ] Record independent point/line errors and reacquisition, without labeling candidate confidence as accuracy.

The device inventory at the local check reports no available iOS connection.
No device installation, camera measurement or real-fold acceptance has occurred.

## Subsequent goal work

- [ ] Physically review the complete Classic Dart course and candidate checkpoints.
- [ ] Produce real correct, incorrect and unclear examples with session-separated evaluation data.
- [x] Implement experimental checkpoint-specific outline comparison and draft help.
- [x] Add Check my step separately from animation, voice and user confirmation.
- [x] Implement the complete ten-action practice flow.
- [ ] Review/correct teaching content with real paper and validate supported checks independently.
- [ ] Run the exploratory beginner comparison.

Numerical registration limits and proposed 3%/1-second product targets remain
validation targets. A first-fold technical demo is not the complete MVP.
