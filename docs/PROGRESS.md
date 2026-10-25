# Protacta engineering progress

Goal: implement the complete-course startup MVP in BUILD_PLAN_2026-10-25.md.
Current work: Protacta 0.1.0 (7) has replaced Build 5 on the iPhone 17 Pro Max.
USB installation, an independent version query, activated launch and a later
process query succeeded. The user confirmed entry to complete Dart practice.
The full MVP
remains incomplete: real-paper review, device feature acceptance, independent
samples and beginner outcomes remain unproved.

## Build 7: USB phone update and basic course entry

- The user resumed engineering and requested installation. Wireless discovery
  remained unavailable after unlock; USB enumeration and a connected developer
  tunnel became available after the user connected the cable.
- The frozen signed Debug artifact from runtime commit `739f2c0` was installed
  without rebuilding. Separate before/after app queries verified 0.1.0 (5) → (7).
- The first launch was refused because the phone had locked. After the user
  unlocked again, normal foreground launch succeeded with no fixture or capture
  arguments; a later process query independently found PID 5989.
- User-reported on-device navigation passed: Paper & craft → Classic Dart →
  Practice the complete Dart. This does not establish physical folding or CV.
- The user has ordinary A4 paper and received the first-fold natural-guide
  follow/move/loss/recovery instructions. Its outcome is pending, not inferred.

See DEVICE_UPDATE_BUILD_7.md and `output/device-install/build7-20261025/`.

## Build 7: completed Dart practice stops voice

- Source/control-flow audit found that Dart's final confirmation can leave
  voice enabled while its controls disappear. Action 10 and the 3D step index
  may both remain unchanged, so index observers cannot provide the stop boundary.
- Stop synchronously before final confirmation, observe other completion paths,
  reject queued commands against live completion state, and refuse new startup
  or direct navigation/narration on a completed practice.
- Explicit Start again/Previous reopens practice without starting voice. Ordinary
  3D voice Restart keeps its existing behavior and independent progress.
- Five added native regression cases cover stop ordering, all queued/direct
  commands, restored completion, explicit reopening and ordinary 3D compatibility.
  A new UI case covers final-action 3D replay, completion and visible restart.
- 241 native tests and four focused phone Simulator UI cases passed with no
  failures/skips. Physical microphone/permission behavior remains untested.
- Generic signed Debug and unsigned Release Build 7 passed in a separate output
  folder. Debug's strict signature check passed; installation was not attempted
  at that local stage. The subsequent USB update is recorded above.
- The teaching content, PTC2 sheet and CV thresholds are unchanged. This is a
  local speech/state repair; no real microphone, paper or learner data was used.

See DART_VOICE_COMPLETION.md and `output/dart-voice-completion/` for validation.
Build 6 artifacts remain preserved separately.

## Build 6: paper visibility and physical-review readiness

- Found a real geometric defect in PTC1: upper QR codes sit beneath the narrowed
  top layers at correct reference states 5 and 6. PTC2 moves their full footprints
  into stationary, top-visible material. Tests evaluate actual layer coverage,
  not just containment inside the paper silhouette. Old sheets are rejected;
  the original PTC1 PDF/JSON remain pinned for historical data.
- Keep lesson screens awake through a shared coordinator across everyday,
  origami and product-AR windows. Restore the initial idle-timer setting only
  after the last active owner exits/backgrounds. Stop voice on completion and reject queued
  commands. Dart Setup/Help now block pending voice/narration until dismissal.
- Include exact paper-layout identity/revision in captures and reject mixed
  layouts in the offline evaluator. Historical PTC1 samples use their preserved
  fitting geometry; new PTC2 samples require explicit layout metadata.
- Added a local raw-PNG labeling tool that hides detector predictions, verifies
  image identity and exports only an explicit separate label. Native ImageIO
  upright EXIF is accepted without rewriting the PNG. Native-export → browser
  download → Python report round-trip passed using a synthetic 4×2 fixture;
  it is not a physical image label or measured camera result.
- 236 native logic/synthetic tests, 28 Python tests, 17 annotator-core tests and
  3 focused iPhone Simulator UI cases passed. Generic signed Debug and unsigned
  Release Build 6 passed. No Build 6 install or physical test was performed.
- Prepared ten-action physical-review and beginner-trial CSVs with all outcomes
  blank/not tested. The user again selected “稍后测试，先继续本地检查”.

See VALIDATION_PHYSICAL_READINESS.md and `output/physical-readiness/` for evidence.

## Build 5: everyday skills and integrated product manual

- User-approved expansion: T-shirt (6 actions), rectangular towel (3), flat
  bedsheet (4), square knot (5) and four-in-hand tie (7), with actual animated
  diagrams, exact Start/Target references, action help and independent progress.
- Migrated AERIS's native filter/setup/cleaning walkthroughs, interactive tab,
  exploded 3D, Quick Look and tabletop AR into the same app. Original projects
  and the copied model's bytes were verified; no separate-app link substitutes
  for integration.
- Added home/exit routing and renderer cleanup; opening one destination does not
  leave the previous camera renderer or display link running behind it.
- 220 native focused logic/synthetic tests passed. Complete skill flows,
  persistence/help, AERIS's release gate and existing Dart regressions passed
  phone Simulator checks. A near-endpoint slider assertion was repaired with
  explicit Start/Target comparison controls and a passing focused rerun.
- Signed Debug and unsigned Release Build 5 succeeded. Phone installation and
  launch succeeded, and a separate installed-app query confirmed Build 5. A
  subsequent live-process query timed out in the wireless tunnel; it is not
  recorded as a confirmed long-running process or device-feature acceptance.
- New everyday content remains an illustrated, manual-comparison prototype.
  Object-specific camera tracking/checking for these categories is not enabled.
  The user explicitly deferred cloud AI until after course integration.

Full evidence, retained failed attempts and iPad screenshot limits are recorded
in INTEGRATION_BUILD_5.md and `output/multi-course/validation-receipt.json`.

## Build 4: wireless device installation

- The user connected the phone on the same network and confirmed it was unlocked.
  After an initial tunnel interruption, a local-network developer tunnel opened.
- Built and verified a separate signed Debug artifact using the existing team;
  the provisioning profile includes the target phone. The earlier unsigned
  artifacts and local-validation receipt were preserved.
- Installed Protacta 0.1.0 (4), launched/activated it without synthetic or validation
  arguments, and independently queried the installed app and running process.
- Camera permissions, physical paper alignment, voice, complete folding and
  checkpoint accuracy still require the user's actual testing. Installation and
  process launch are not feature acceptance.

See DEVICE_INSTALL_2026-10-25.md and
`output/device-install/build4-20261025/` for the signed build and device receipts.

## Build 4: frozen visual comparison and action-specific replay

- Added **See this comparison** after an accepted check. The temporary grayscale
  image, paper pose, display transform and result belong to the same frame.
  Green marks the reference silhouette; soft red areas suggest where to compare.
  Sample points are not presented as counts of separate folding mistakes.
- Added the current action's draft manual comparison, common-mistake notes and
  same-action 3D replay. Action 2 explicitly cannot verify the center crease;
  no comparison or replay automatically confirms an action.
- Paused paper analysis while the frozen comparison is open. Returning to the
  camera clears it and restarts registration. New checks, action changes, rescan,
  tracking loss, camera failure, backgrounding and exit clear the transient image.
  Normal practice saves no photo; opt-in Debug validation capture stays separate.
- Replaced unconditional Simulator matches with generated before-action pixels
  processed by the real checker. Visible labels identify every sample as synthetic.
  This exercises adjustment and unknown outcomes without manufacturing accuracy.
- 195 native logic/synthetic tests and 24 Python evaluator tests passed. The
  new snapshot path includes pixel-format/range and geometric-direction checks.
- Five phone UI cases and one tablet landscape case passed. A final phone rerun
  passed two overlapping cases after visual polish, including an asymmetric
  action-4 image; these are software checks, not separate users or physical tests.
- Generic iOS Debug and Release Build 4 compiled without signing. Final phone
  and tablet captures were visually reviewed. No installation was performed.

Evidence: VALIDATION_VISUAL_FEEDBACK.md and
`output/visual-feedback/validation-receipt.json`.

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

Earlier device inventories reported no available iOS connection. Physical testing
was deferred during the local Build 4 iteration. A subsequent user request enabled
wireless installation and launch; camera measurements and real-fold acceptance
have not yet been recorded.

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

## Simulator presentation videos — 2026-10-26

- [x] Recorded actual Simulator UI and delivered a 90-second presentation video,
  four portrait clips, original recordings and speaker notes locally.
- [x] Verified all five delivery encodes; synthetic paper and virtual AERIS are
  explicitly labeled. See `DEMO_VIDEO_2026-10-26.md`.
- [ ] Physical A4 alignment, hiding and recovery remain a separate acceptance gate.

## Narrated presentation edition — 2026-10-26

- [x] Added natural-style English AI narration and synchronized burned subtitles
  to the master and all four portrait clips, preserving the silent set and SRTs.
- [x] Verified five complete audio/video decodes and sampled all 37 caption cues.
  See `DEMO_NARRATION_2026-10-26.md` for provenance, artifacts and validation scope.
