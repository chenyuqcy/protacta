# Build 22 — AR boundary refinement

The user reports continuing jitter where the virtual object meets a real hand or object. This iteration changes silhouette ownership and calibrated history handling rather than simply increasing averaging.

## Research and inference

Apple's [Bringing People into AR](https://developer.apple.com/videos/play/wwdc2019/607/) explains native people matting, its refinement using the camera image, and support for a person's own hands and feet. [People occlusion documentation](https://developer.apple.com/documentation/arkit/occluding-virtual-content-with-people) shows how standard RealityKit rendering uses the person-with-depth semantic.

Apple's [scene-depth sample](https://developer.apple.com/documentation/arkit/displaying-a-point-cloud-using-scene-depth) enlarges low-resolution depth with a camera-guided filter. This supports the inference that a hard low-resolution triangle edge should not define the visible hand outline. Upsampling does not add newly measured geometry. This build uses RealityKit's native hand refinement; it does not claim to implement a new high-resolution general-object compositor.

Apple documents [smoothed depth](https://developer.apple.com/documentation/arkit/arframe/smoothedscenedepth) as multi-frame averaging. The source audit identified same-pixel history despite small camera movement, plus support-plane and confidence thresholds that can toggle complete triangles. More averaging alone would not solve those spatial ownership problems and could increase disappearance delay.

## Changes

- Automatic/refined mode keeps native hand matting enabled. Optional custom depth is limited to non-person objects. Runtime checks verify the entire requested semantic combination; unsupported combinations use native hands.
- A conservative person region and margin are removed before filtering, from warped history, and after filtering. Missing native coverage hides the optional custom surface rather than guessing a silhouette.
- Current camera geometry is used to check old and in-flight custom triangles against current person coverage. A mesh that could reclaim a hand pixel is hidden/rejected while native hand rendering continues.
- Previous depth points, confidence, hole holds and observation ages are reprojected using their own calibration/pose into the current exposure. Disoccluded points remain unknown; stale/backward history is rejected. Current coherent arrival/removal bypasses temporal blending.
- The depth health check uses fresh completed rendering/clear observations, not data receipt before asynchronous work succeeds. Empty results need sufficient fresh non-person coverage and demonstrated support-plane rejection without depth discontinuities, or a fully person-excluded region. High-confidence but wholly discontinuous depth cannot keep a failed object pipeline healthy.
- The existing no-grounding-shadow setting, no reconstructed scene-mesh occluder, current-pose freeze and 120ms stale-data limit remain.
- The everyday viewport now uses the existing explicit ARView layout container for rotation; this does not create another camera session.

## Evidence boundaries

The phone's copied `equipment-ar-diagnostic.json` was **Build 17**, timestamp 2026-10-31T22:17:44Z. Its 256×192 source and 33.6ms mesh age are historical evidence, not a fresh Build21/22 measurement. No current physical improvement percentage is available.

Local validation and the final signed artifact are retained in `output/ar-edge-research-2026-11-01/`. Results and deployment are recorded below. Simulator fixtures say NO LIVE CAMERA; their screenshots do not establish hand-edge quality.

## Local validation

- `FinalClearGateDepth.xcresult`: **87 native tests passed**, zero failures. Includes calibrated reprojection, thin person masks, mask removal, actual projected mesh triangles after camera/calibration changes, stale history, reliable clear observations, high-confidence discontinuous empty meshes, configuration and lifecycle checks.
- `FinalModeUI.xcresult`: one iPhone Simulator UI case passed for AR help and mode switching while preserving a paused fold. This ran before the final empty-depth-health predicate change; the final predicate and its integration were rebuilt and tested in the 87-case run above.
- `ModeAndEverydayUI.xcresult`: three earlier UI cases passed for mode selection, all five everyday AR entry/return flows and pause behavior. `EverydayTabletFrame.xcresult`: one iPad rotation/control case passed. These are navigation checks, not physical-camera tests.
- Visual inspection of the iPad landscape AR-layout fixture still shows the teaching model partly cropped, despite usable controls and explicit viewport resizing. This remains an open fixture/framing issue; it is not claimed fixed by the layout-container change.
- The final signed Release build passed, including strict signature verification. `build22-retained-receipt.json` identifies its retained app, executable SHA-256 and exact source hashes. Earlier Build 22 artifacts/receipts are preserved and superseded by this receipt.

## Device delivery

The final retained app was installed successfully on the paired iPhone 17 Pro Max. A separate app inventory query confirmed `org.realitycore.protacta.prototype`, version `0.1.0`, build `22`, and the same final installation container returned by installation. See `final-install.json` and `final-installed-apps.json`.

Both automatic foreground-launch attempts were rejected by iOS as locked (`final-launch.json`, `unlocked-launch.json`), including the attempt after the user reported unlocking. The user was asked to open the app directly and compare a stationary hand at the gearmotor edge in Refined edges mode. No result has yet been reported. Installation is confirmed; foreground launch and physical improvement are not inferred.

## Physical comparison

In the same course, placement, distance and light: hold a hand at the model edge for 5 seconds, rest it near the table, move it slowly across, then remove it completely. Check silhouette chatter, stepped holes and any lingering cutout separately. Also try a non-person object and a short phone movement. Compare Refined edges with Native hands without changing the model pose. Record build/course/mode and whether the symptom occurs at rest, during motion or after removal.
