# Build 5: one app for paper, everyday skills and product manuals

25 October 2026. The user requested integration of the other proposed directions
into Protacta, then explicitly chose to defer cloud AI until after course
integration. This is an expanded prototype, not a physically accepted MVP.

## Delivered modules

| Entry | Implemented teaching | Current physical/camera boundary |
| --- | --- | --- |
| Paper & craft | Existing origami library and complete Classic Dart practice | Existing restricted paper alignment and outline checks; physical accuracy still unaccepted |
| T-shirt | Six actions: body panel, sleeve, opposite panel/sleeve, two packet folds | Authored animated diagrams and manual result comparison |
| Rectangular towel | Three actions: left third, right third, half the strip | Authored animated diagrams and manual comparison |
| Flat bedsheet | Four successive edge-pair folds with named corners | Flat sheets only; no fitted-sheet or fabric-recognition claim |
| Square knot | Five actions showing named ends, two opposite half-knots and dressing | Loose practice only; authored over/under routes, not camera grading |
| Four-in-hand tie | Seven actions covering front/behind/front wraps, neck-loop ascent, front-band descent, dressing and keeper | Authored wide/narrow-end routes with wearer/viewer direction notes |
| AERIS One | Filter replacement (7 steps), setup (5) and cleaning (5); interactive release tab, exploded view, Quick Look and tabletop AR | Virtual original concept product; no physical-appliance recognition/alignment |

Everyday courses contain material/setup, instructions, manual checkpoints,
common mistakes and action-specific help. Playback supports pause, replay,
slower speed, a scrubber and exact Start/Target positions. Entering a new action
or replaying help returns to the instruction/diagram at the top of the page.
The first home thumbnails showed too much scope text; the final cards prioritize
the actual diagram and use the Illustrated guide label.

Only explicit learner confirmation advances everyday practice. Separate local
records survive relaunch, validate per-course content revisions, reject invalid
steps/confirmations and remain bounded to five courses/64 KiB. Earlier review
withdraws later declarations; it does not alter a physical object. Restoring a
completed course shows the final target. AERIS preserves session-local progress.

The existing on-device English VoiceGuide supplies optional narration and
commands. Next step does not confirm the person's physical action. Permission
prompts, backgrounding and exit cancel or suspend the appropriate work. No API
key was created, no generated chatbot was added and normal use needs no backend.

## Integration and lifecycle

Home creates only its selected destination. Leaving origami permanently invokes
shutdown, invalidating its display link and restoring the idle timer before a
different module can open. AERIS has its own studio ARView and shares that view
with its own tabletop controller; ownership checks prevent delayed dismantling
from clearing the restored studio. Camera-permission, load and animation tasks
are cancelled on background/final dismissal.

The source AERIS app and original Foliafold remain untouched. The 85 original
Foliafold hashes and six AERIS source/resource hashes were checked. The copied
AERIS asset remains byte-identical (3,653,362 bytes). Migration hashes are in
`ios/PaperSteps/ProductManual/MIGRATION_SOURCE.json`; local checks are in
`output/multi-course/source-integrity.json`.

## Validation evidence

- 220 focused native logic/synthetic tests passed in
  `output/validation/20261025T134333Z-dart-logic/Practice.xcresult`: prior 195
  plus 14 course/session/store, 4 fold projection and 7 AERIS integration cases.
  The latter loads the real USDZ and checks every authored target; it does not
  create physical-camera evidence.
- Initial phone sweep: 5 passed in `output/multi-course/Phone-UI.xcresult`,
  including all five complete everyday flows, persistence/help, AERIS routing/tab
  gate and two existing Dart regressions. Reviewed screenshots exposed retained
  scroll position and oversized home thumbnail captions, which were corrected.
- Intermediate phone pass: 2 passed in `Phone-Final.xcresult`, covering AERIS
  and the corrected tie front-band sequence. The original renderer showed that
  band before its action; the corrected route creates it during the movement.
- Refined phone sweep: 3 passed, 1 failed in `Phone-Refined.xcresult`. Complete
  courses, cross-relaunch progress and AERIS passed. The tie test's normalized
  slider gesture landed near the endpoint, so the exact TARGET POSITION assertion
  failed. Explicit Start/Target controls now provide deterministic comparisons;
  the failed run and attachments are retained.
- Final endpoint case: 1 passed in `Phone-Endpoints.xcresult`; actual Start/Target
  buttons select exact positions, with reviewed before/target/next-action images.
- Initial tablet interaction case passed in `Tablet-UI.xcresult`. A rerun with
  explicit landscape-window waits passed in `Tablet-Landscape-Verified.xcresult`.
  The raster remained portrait. An additional screenshot-aspect assertion in
  `Tablet-Window-Verified.xcresult` failed even though the app-frame landscape
  assertions passed. These results are retained rather than calling a portrait
  raster validated landscape rendering. Final control bounds and metadata are
  recorded separately; physical iPad visual acceptance remains open.
- A later tablet-control run stalled before XCTest started and was interrupted.
  Its partial `Tablet-Controls-Final.xcresult` and error log are retained. The
  simulator was rebooted for one fresh retry. The final test asserts reported
  landscape window/control bounds and records screenshot size/orientation as
  diagnostic metadata; it does not equate a portrait raster with landscape QA.
  The fresh retry passed (1 case) in `Tablet-Fresh-Retry.xcresult`; the earlier
  stalled invocation is not included in the successful case count.
- Generic iOS signed Debug and unsigned Release Build 5 both succeeded. Strict
  signature validation passed; the profile includes the phone. Earlier Build 4
  artifacts were preserved using `output/MultiCourseDeviceDerivedData`.
- Installation and activated launch succeeded on iPhone 17 Pro Max iOS 26.6.1.
  A separate app query confirmed version 0.1.0 (5). Launch used no synthetic,
  validation or StoreKit-test arguments. A later live-process query failed due
  to a wireless-tunnel timeout, so continued process liveness is not certified.
  See `install.json`, `launch.json`, `installed-app.json`, `running-process.json`
  and the combined `validation-receipt.json` under `output/multi-course`.

These phone runs use iPhone 17 Simulator iOS 26.5. The logic selection used
iPhone 16 Pro Simulator iOS 18.3.1. Some successful UI runs emitted an optional
post-run diagnostics warning that the default toolchain could not locate simctl;
test results and exported attachments are retained. Global toolchain settings
were not changed to suppress the warning.

## User testing and remaining work

On the new home screen, choose each everyday card, try its movement, compare with
real material, use help, confirm all actions, close and reopen. Check that another
course keeps its own position. Follow AERIS in studio first; test Explore parts,
task switching, the release-tab gate and returning from View in AR/Apple AR.
Confirm the actual phone's camera, gestures, voice and background recovery.

New teaching text, knot/tie diagrams and material handling still need physical
follow-through review. New categories do not yet have object-specific camera
registration or correctness models. The original Dart physical dataset,
independent accuracy/timing labels and beginner comparison remain outstanding.
No simulated course completion substitutes for those acceptance gates.
