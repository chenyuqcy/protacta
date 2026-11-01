# Build 23 — origami hand contact

The user prioritised origami and clarified the remaining symptom: the hand/virtual-paper intersection flickers when a hand enters or passes through the paper. This iteration is limited to the origami configuration, help and AR lifecycle. Equipment and everyday geometry/player behavior are unchanged.

## Evidence and approach

The captured phone file `output/origami-contact-build23-2026-11-01/build22-origami-before.json` is a fresh **Build 22 Classic Dart** AR diagnostic (2026-11-01T16:48:00Z, step 10). It shows Automatic mode, a placed paper, native-person exclusion and an active custom depth surface. It establishes the tested path, but does not measure visible flicker or prove its exact cause.

Apple documents that [`personSegmentation`](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/personsegmentation) makes recognised people occlude virtual content regardless of depth, and RealityKit ARView implements it automatically. Its [people-occlusion presentation](https://developer.apple.com/videos/play/wwdc2019/607/) covers native camera-guided matting and one's own hands/feet. The hypothesis is that removing the depth comparison at a hand/paper intersection will remove one source of front/back switching. Native silhouette noise remains a separate physical question.

## Changes

- Origami defaults to **Hands first** on devices supporting `.personSegmentation`. The exact frame-semantic request contains that mode only; custom object-depth and reconstructed mesh occluders are off. Native matting stays enabled and grounding shadows remain disabled.
- This deliberately keeps all recognised person pixels in front of the virtual paper, including hands actually behind it. It is a folding-guide visibility policy, not physical collision detection. Other real objects do not gain foreground occlusion in this mode. **Refined depth** and **Native depth** remain optional in AR help, using the existing persisted raw values.
- Independent mask capability checks and effective-mode normalisation avoid requesting unavailable features. Diagnostics distinguish requested person mask and depth semantics. Receiving an estimated-depth buffer is not used as a test of whether foreground-only mode is active.
- A paused fold now checks current camera freshness, normal tracking and its committed anchor on display ticks. Stale/missing tracking hides the virtual paper, stops playback and disables gestures without advancing or deleting the fold. Fresh normal frames carrying the same anchor restore it. Paper-registration and layout-fixture paths retain their own handling.
- Optional refined-depth mode now monitors completed/applied depth, with a two-second startup window and a 0.75-second loss window, then falls back to Hands first where supported. A mode change preserves the anchor, placement, step and partial fold and does not start a missing camera session.
- Source review found no blocking paper-geometry defect matching a hand-only symptom. Existing mesh construction, paper thickness, crease geometry and animation remain unchanged.

## Validation and delivery

- `OrigamiContactFinal.xcresult`: **71 native tests passed**, zero failures, covering exact configuration, health timing/controller transitions, partial folds, paper geometry/cache, learning progress, Dart practice, voice actions and paper-guide isolation. The initial run exposed an incorrect test assumption: `.personSegmentationWithDepth` includes the segmentation option bit. Exact semantic-set assertions replaced that assumption; application code did not change for that correction.
- The signed Release build and strict signature verification passed. `build23-retained-receipt.json` records the retained app, executable SHA-256 and source/project inputs.
- Installation succeeded on iPhone 17 Pro Max. An independent app query confirmed version 0.1.0, build 23 and installation container `BE2B4128-7B00-4F56-8612-F5AE134EE50D`. Remote foreground launch failed because the device disconnected immediately after connection. The user was asked to open it directly.
- `OrigamiModeAndFullscreenUI.xcresult`: **three iPhone Simulator UI cases passed**, zero failures, for AR help/mode selection, normal fullscreen/voice recovery and clean voice-only fullscreen, all preserving a partial fold. Simulator fixtures do not establish live-camera, speech or hand-edge quality.

## Physical acceptance

Use the same Classic Dart AR placement and light. In Hands first, slowly pass a hand through the virtual paper and hold at the intersection for five seconds; then move it completely away. Check stationary flicker, moving edge chatter and a lingering hole separately. Also switch to Refined depth and back while paused, confirming the same placement and fold, and return to 3D.

For independent runtime confirmation, retain a fresh `PaperStepsStatus.json` showing build 23, `occlusionMode: handsFirst`, mask requested, person-depth ordering not requested, and no custom depth triangles. Until the user reports a comparison, contact-edge improvement is pending.
