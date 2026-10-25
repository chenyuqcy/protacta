# Classic Dart: complete-course coverage draft

**Draft, 25 October 2026 — awaiting real-paper review.** This document maps the
existing authored course to proposed observations, checkpoints and recovery.
It is not a record of successful physical folding, camera acceptance, approved
teaching content or implemented computer-vision checking. No new capture or
learner results were collected for this document.

The product goal remains one complete course, including real-object guidance
and selected fixed-view checks. A successful first-fold overlay is a technical
milestone, not completion of that MVP. Every action below needs a usable teaching
and recovery path, including actions that remain manual with a 3D reference.

## Source and state conventions

The active authored course is `PaperLesson.steps` in
[LessonContent.swift](../ios/PaperSteps/LessonContent.swift), with preparation
state **0** and **10 actions, IDs 1–10**. Geometry is
`PaperGeometry.frame(step:progress:)` in
[PaperGeometry.swift](../ios/PaperSteps/PaperGeometry.swift). In this document,
state N means the resting result after action N, sampled at `progress: 1`;
state 0 is the original prepared A4 sheet. The next action is N+1. An animation
between endpoints does not establish that the real paper followed that motion.

The source specifies white A4 paper without cutting or glue. Its virtual sheet
is 0.210 by 0.297 metres. Those model dimensions do not prove that a camera
rectangle is A4, paper or the learner's intended object. Image aspect ratio alone
also cannot establish physical dimensions under perspective.

The current `supportsCurrentPaperGuideStep` in
[LessonController.swift](../ios/PaperSteps/LessonController.swift) permits the
first-flat-sheet demonstration at source steps 0/1. This gate is an instructional
entry point: it does **not** mean the folded result of action 1 is registered or
recognized. The current rectangular detector, direction confirmation and
registration are not a course-state recognizer. All additional checks and folded
state registrations described below are proposals.

## Coverage of all eleven states

“Candidate” means an observation worth investigating with real samples, not a
reliable detector or a validated rule. Even a candidate flat state must be
re-registered after a fold; the original rectangle's corners and mapping must
not silently carry over to its changed outline.

| Completed source state | Resting paper expected by the authored lesson | Next source action | Real-paper observation and candidate check | Guidance and recovery |
| --- | --- | --- | --- | --- |
| **0 — Start with a blank sheet** | Whole sheet flat; a short edge is at the top; left/right follow the nose-up view. | **1 — Make the center crease:** left long edge onto right long edge, match corners, press. | **C00 preparation / alignment candidate:** whole boundary, sufficient visibility, approximate rectangularity and user-confirmed TOP direction. This does not verify material, absolute size or an existing crease. | Current first-fold overlay may show the centre line, moving edge and direction while the starting sheet remains flat and confidently registered. Hide it when correspondence is lost; show the 3D action while the person folds. |
| **1 — Make the center crease** | The sheet is folded lengthwise in half, with its left half brought onto its right. | **2 — Open the sheet:** unfold and smooth flat; keep the centre crease top to bottom. | **C01 half-fold candidate:** ask the person to lay the folded result flat. A known-side view might show matched exposed corners and a doubled long boundary. An ordinary rectangle alone cannot prove that two layers exist or that hidden edges align. | Replay the fold and the opening motion in 3D. A half-sheet reference would need its own state template and side convention; it is not supported by the current full-sheet guide. Keep manual confirmation available. |
| **2 — Open the sheet** | Whole sheet reopened; the centre crease remains as a guide. | **3 — Fold the left corner:** top-left corner inward, original top edge beside the centre crease without crossing. | **C02 reopened preparation candidate:** full boundary and direction can support positioning. A clearly visible centre crease could become a separate, future observation. The boundary itself cannot certify that the centre crease was made correctly. | Candidate flat-state registration for the next left-corner cue. Ask the learner to inspect/confirm the centre crease; offer the action-1 replay. If the crease cannot be seen, return “cannot assess the crease,” not success. |
| **3 — Fold the left corner** | Top-left flap pressed down; the first diagonal begins the nose. | **4 — Fold the right corner:** repeat on the right to make matching corner folds. | **C03 left-corner candidate:** reviewed visible polygon, nose point, relevant flap edge and its relation to the centre reference. Distinguish a left corner fold from a rotated or mirrored right fold. | Candidate contour/landmark registration can place the right-corner cue after reacquisition. If the centre reference or flap edge is hidden, limit feedback to what is visible and offer a fixed-view retake or 3D comparison. |
| **4 — Fold the right corner** | Both upper corners folded inward; paired triangular flaps form the broader pointed nose. | **5 — Narrow the left side:** upper-left sloping edge to centre, keep the nose pointed, flatten. | **C04 paired-corner candidate:** nose and exposed fold-edge positions; visible gap/overlap and rough side symmetry. Symmetry is evidence about visible geometry, not proof of equal hidden layers or crease strength. | Candidate flat-state outline and left-side action cue. Re-register the new shape; preserve a deliberate orientation reference. Replay only the relevant corner fold if adjustment is needed. |
| **5 — Narrow the left side** | A second left-side fold narrows the nose; right side remains at the preceding stage. | **6 — Narrow the right side:** bring upper-right sloping edge to centre and match left. | **C05 narrowed-left candidate:** an intentionally asymmetric outline and identifiable exposed left edge. Do not reject it merely for not matching the final symmetric shape. | Candidate right-side cue after confirming the current state. If a wrong-layer fold creates a similar outline, classify it as unjudgeable unless the necessary layer is actually visible; use the 3D layer highlight. |
| **6 — Narrow the right side** | Both narrowing folds complete; two long exposed edges should meet evenly near the centre and the nose remains pointed. | **7 — Close the body:** lift the paper; left half underneath right on centre crease, nose layers outside. | **C06 narrowed-pair candidate:** flat resting outline, nose point, exposed meeting edges and visible side balance. A photo cannot establish which hidden layers will end up outside after the next movement. | Last initial candidate for a planar real-paper cue: indicate the centre hinge before lifting. Once paper lifts or layers leave the common plane, stop the planar overlay and use the 3D underside-fold demonstration. |
| **7 — Close the body** | Body folded on the centre crease; narrow body held with nose layers outside. | **8 — Fold the first wing:** highlighted outer flap down; long sloping edge to body's bottom edge. | **Manual / 3D initially.** The geometry includes an upright presentation rotation here. An overhead rectangle or old planar fit cannot identify the outer flap, underside path or hidden layer order. | Show front/side 3D views and the moving-layer highlight. Ask the learner to compare the centre/body edge and nose-layer placement. A dedicated fixed-side photograph may be researched later, but is not an enabled camera check. |
| **8 — Fold the first wing** | First wing crease made; a narrow body remains beneath the wing. | **9 — Fold the other wing:** repeat on opposite side, matching the first wing. | **Manual / 3D initially.** A side view may expose one crease/edge, but can hide the other wing, body thickness and selected layer. A correct-looking silhouette is insufficient. | Replay the wing fold with the highlighted outer layer. Invite an explicit manual comparison of the edge/crease, then show the opposite-side action. No automatic completion from animation playback. |
| **9 — Fold the other wing** | Both wing folds made; wing outlines and crease positions should match. | **10 — Open your finished wings:** lift both level, narrow body below. | **Manual / 3D initially.** Paired visible outlines may support a future constrained comparison, but a single view can conceal the opposite crease or a wrongly folded body. | Offer the 3D wing-opening movement and learner-controlled rotation. Ask for a manual comparison before opening; do not project a single homography across the separated wing/body planes. |
| **10 — Open your finished wings** | Wings opened level, narrow body below; completed dart. | **Completion / optional repeat**, not action 11. The source suggests looking from the front to compare wings. | **Manual completion initially.** A future front-view checkpoint could inspect visible wing balance and body-below relation. That would not prove hidden fold order, flight performance or completion of every earlier action. | Show the finished 3D reference and front-view prompt. Save learner-confirmed completion separately from visual-check evidence. Provide “review a step” and “start again”; do not label the real result camera-verified. |

## Candidate checks and error wording

These error classes are a labeling and content-authoring proposal. They must be
reviewed using actual paper before thresholds or correction text are approved.

| Candidate | Potentially visible error evidence | Must remain unjudgeable when… | Proposed teaching response |
| --- | --- | --- | --- |
| C00 / C02 | Sheet cropped; expected top direction unconfirmed; sheet visibly lifted or curled. | Material/size is unknown; direction is symmetric; hands conceal needed points; the crease is invisible. | Ask for the whole sheet flat and a deliberate TOP check. For C02 ask the person to compare the centre crease and replay action 1 if needed. |
| C01 | Exposed corners/edges visibly offset in the specified resting view. | The lower layer or matched edges are hidden; only a generic rectangle is visible. | “Compare the exposed corners before pressing.” Do not infer a missing layer or badly pressed crease from its absence in the image. |
| C03 | Visible moved edge stops short of or crosses a visible centre reference; wrong side is clearly identified. | Centre reference, flap identity or direction is ambiguous. | Point to the particular visible edge/endpoint; repeat the left-corner motion. Do not say “wrong layer” without visible evidence. |
| C04 | Exposed left/right fold edges show a clear gap, overlap or unequal visible placement. | Symmetric outline masks hidden layering; perspective/occlusion prevents a fair comparison. | Compare the two edges against the reviewed target; replay the relevant side. |
| C05 / C06 | Identifiable exposed long edge visibly misses the centre target; one side is at the wrong supported stage. | Layers conceal the relevant edge; the nose is crushed/lifted; current state cannot be distinguished reliably. | Highlight only the supported edge/target relationship. Offer a retake or manual 3D comparison; do not prescribe an unseen corrective fold. |

State 0 and state 2 deserve a dedicated negative-control test. The source
geometry returns both to the same sheet outline. A blank rectangle placed at the
same pose is not evidence of action 1 having occurred. A valid C02 result may
mean **“paper positioned for the next instruction”** while crease correctness
remains **unknown / learner-confirmed**. These are different outputs.

All checkpoints need three result classes: `visible_match`, `visible_error`,
`unjudgeable`. “Visible match” means only that the declared observable criteria
match. It must never be presented as an unrestricted “your fold is correct.”
No result should advance the lesson automatically in this first implementation.

## Proposed dataset manifest and label schema

Store one JSON object per selected image/frame in a versioned JSONL manifest.
Keep original capture sequences and a separate split manifest so neighboring
frames, derivatives and mistakes corrected during the same attempt can be
tracked together. This is a proposed schema, not a collected dataset:

```json
{
  "schema_version": 1,
  "sample_id": "<unique sample ID>",
  "tutorial_id": "classic_dart",
  "content_revision": "<reviewed text/geometry/checkpoint revision>",
  "source_step_index": 3,
  "expected_checkpoint_id": "C03",
  "capture": {
    "media_path": "<local relative path>",
    "media_sha256": "<hash>",
    "parent_sequence_id": "<original video or burst>",
    "frame_timestamp_ms": 0,
    "attempt_id": "<whole-course attempt>",
    "operator_id": "<pseudonymous ID>",
    "physical_sheet_id": "<sheet ID>",
    "capture_session_id": "<session ID>",
    "device_family": "<device/camera>",
    "image_size_px": [0, 0],
    "pixel_orientation_applied": "<recorded orientation>",
    "view": "overhead",
    "visible_side": "<reviewed side label or unknown>",
    "material_setup": "<known A4 / unknown material>",
    "marker_variant": "none",
    "lighting_condition": "<capture label>",
    "background_condition": "<capture label>"
  },
  "annotation": {
    "result": "unjudgeable",
    "visible_criteria": ["<criterion ID and observed fact>"],
    "error_codes": [],
    "unjudgeable_reasons": ["<reason code>"],
    "landmarks": [],
    "visible_edges": [],
    "visible_outline": [],
    "registration_supported": false,
    "direction_identity": "unknown",
    "review_status": "pending",
    "annotator_id": "<pseudonymous reviewer>",
    "second_review_status": "pending"
  }
}
```

Use oriented-image pixel coordinates: origin top-left, x right, y down. Every
landmark/edge carries an identity, coordinates and visibility (`visible`,
`occluded`, `outside_image`, `ambiguous`). Unknown points have no invented
coordinates. If evaluating viewport overlays, separately store the image-to-
viewport crop/rotation transform; do not mix normalized viewport points with
original image pixels.

Suggested reason codes include `cropped`, `occluded`, `motion_blur`,
`low_contrast`, `direction_ambiguous`, `state_ambiguous`, `reference_invisible`,
`nonplanar`, `unsupported_material` and `unsupported_view`. Maintain registration
quality separately from the semantic label: a strong rectangle detection is not
a “correct fold” label. Model outputs must not become the reference annotation.

The capture checklist should cover each enabled checkpoint's correct examples,
reviewed typical errors, look-alike states, wrong direction/side, hand and object
occlusion, cropped paper, varied distances, oblique views, light/background
changes, and entering/leaving the support conditions. Include state-0/state-2
look-alikes and examples outside the enabled stage, not just clean positives.
Collect real sequences of lifting, removal, rotation and return for recovery
evaluation. Synthetic shapes can test mathematics and plumbing but cannot
replace this real-paper evidence.

### Splits and independent evaluation

- Reserve development, validation and untouched test groups before selecting
  frames; a provisional **60/20/20 allocation of independent groups**, not
  frames, is a starting plan. Report actual group and sample counts and reduce
  claims if the available independent groups are too few.
- A physical sheet, operator, course attempt and capture session must not cross
  the primary split. Group shared identities together; all frames, edited crops,
  augmentations and corrected-error sequences inherit their original group.
- Tune thresholds on development/validation only. Freeze checkpoint criteria,
  code/model and feedback revision before evaluating the untouched test set.
- Keep an additional device/background/lighting challenge set when sufficient
  data exist; report those conditions separately rather than hiding them in an
  aggregate score. Pilot learners must not simply repeat memorized test images.
- Review label disagreements before release; preserve `unjudgeable` rather than
  forcing a guess about a hidden crease or layer. Record reviewer uncertainty
  and final resolution in the manifest.

For registration, use independently annotated interior points or cue lines that
were not the four fitting corners. Report error normalized by a declared paper
width/visible reference, stability, valid-overlay coverage, false cue display
during loss, and reacquisition after features become visible. The proposal's 3%
error / 1-second recovery numbers remain **unvalidated targets**. For checking,
report per-checkpoint counts and the three-class confusion matrix, emphasizing
visible errors incorrectly approved and incorrect corrective suggestions.

## Gates before calling this a complete-course MVP

1. A reviewer follows all ten authored actions with real A4 paper and records
   where instructions, 3D layer selection and the actual result disagree. Each
   row receives a dated review entry; this draft is not that entry.
2. The team selects and documents enabled alignment/checking states, view
   requirements, marker/direction conventions, visible criteria, rejection rules
   and reviewed correction wording. Rectangular and polygonal states require
   separate support decisions.
3. On-device camera testing verifies the first-flat-sheet milestone and every
   newly enabled state on the supported orientations/devices. Synthetic tests,
   simulator fixtures and a successful build do not satisfy this gate.
4. Independent captures validate the supported checks and their uncertainty
   behavior. No checkpoint is enabled solely because its synthetic outline can
   be recognized. Semantically ambiguous states retain manual confirmation.
5. An entire attempt from state 0 through state 10 works with replay, help,
   recovery, interruption/resume and manual 3D fallback. The source's later
   three-dimensional actions remain clearly labeled manual unless separately
   validated; the course must still be completable without a misleading overlay.
6. The beginner pilot records completion, errors, help, time and failure points,
   with the software build, device conditions and enabled checkpoint coverage.
   Its results inform the next revision; no learning-effect percentage is assumed.

## Code pointers for the subsequent implementation

- [LessonContent.swift](../ios/PaperSteps/LessonContent.swift): `LessonStep` and
  `PaperLesson.steps`, the authoritative action text and order (states 0–10).
- [PaperGeometry.swift](../ios/PaperSteps/PaperGeometry.swift): material source
  coordinates, `PaperFrame.crease`/`actionPaths`, reversal in steps 1/2, cumulative
  corner folds 3–6, upright body presentation at 7, wing movement at 8–10.
- [PaperModel.swift](../ios/PaperSteps/PaperModel.swift): existing dashed crease
  and moving-layer/action-arrow rendering; explanatory arrows include rendering
  offsets and are not measurements of the user's paper.
- [PaperRegistration.swift](../ios/PaperSteps/PaperRegistration.swift),
  [PaperGuideSession.swift](../ios/PaperSteps/PaperGuideSession.swift),
  [PaperVisionTracker.swift](../ios/PaperSteps/PaperVisionTracker.swift): current
  first-sheet mapping, observation lifetime/identity rules and rectangular
  candidate detection. These do not implement the candidate course checks above.
- [LessonController.swift](../ios/PaperSteps/LessonController.swift): first-guide
  support gate, camera/lesson lifecycle, explicit learner confirmation and 3D
  fallback. Animation `progress` is separate from physical completion evidence.
- [FoldHelp.swift](../ios/PaperSteps/FoldHelp.swift): authored comparison/help;
  Dart currently uses generic step-help fallback. The candidate feedback above
  needs its own reviewed, step-specific authoring before integration.
- [LearningProgressStore.swift](../ios/PaperSteps/LearningProgressStore.swift):
  versioned teaching progress; do not persist reusable camera coordinates or
  mistake learner confirmation for a camera result.
- [PaperGeometryTests.swift](../ios/PaperStepsTests/PaperGeometryTests.swift):
  geometry conservation, continuity and corner-to-centre checks. These test the
  virtual model, not real folds or a visual evaluator.
- [BUILD_PLAN_2026-10-25.md](BUILD_PLAN_2026-10-25.md) and
  [PROGRESS.md](PROGRESS.md): overall MVP definition and current evidence gates.
