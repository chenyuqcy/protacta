# Current-step framing — Build 35

## Interaction

Everyday courses now frame the full movement of the current action instead of
the full course. The camera frame is cached for that action and physical scale;
seeking or playing within an action does not continuously chase the model.

The new viewfinder button beside More pauses playback and fits the current fold.
Tap it again to show the full movement. Playing, replaying or dragging exits this
detail view once, restoring the fixed action frame so a larger unfolding motion
is not cropped. Focus resets manual zoom/orbit but does not change the action,
animation progress or learner confirmations. After explicit Finish, the final
packet is framed closely; reopening a completed course uses the same framing.

The focus control is available only in the studio. It changes the observation
camera, never the model's dimensions or its AR placement. The existing tabletop
controller still owns world placement and manual cloth alignment.

## Implementation

- `EverydayStepFraming`: fixed movement bounds, explicit pose bounds and completed
  bounds, with conservative padding around the render surface. The small-packet
  radius floor is 2.5 cm instead of the old 15 cm.
- `EverydaySceneController`: cache per-action frames, invalidate on calibrated
  scale changes, and keep `action`, `detail`, `complete` modes separate.
- `Tutorial3DRenderer`: change studio framing without replacing the ARView or
  content entity. Gesture callbacks update diagnostics only after real gestures,
  avoiding a view-update/camera-update publication loop.
- `EverydayTutorialPlayer`: one compact focus control; existing timeline,
  confirmation and AR navigation retain their meanings.

## Validation

Artifacts: `output/step-focus-20261117/`.

- Pure Swift probes: 1,525 densely sampled movement poses and 338 calibrated
  cloth poses fit inside their action frame, including rendered shell thickness.
- iPhone 17 Pro Max Simulator, iOS 26.5: **8 passed, 0 failed, 0 skipped**
  (`Phone.xcresult`, `phone-summary.json`). Five geometry tests plus three UI
  cases cover late-step framing, explicit focus, manual zoom reset, stable
  scrubbing, completion framing, AR-layout return and saved progress.
- iPad Pro 13 Simulator: **1 passed, 0 failed, 0 skipped**. Focused framing and
  paused pose persist through landscape and portrait, and controls stay reachable
  (`Tablet.xcresult`, `tablet-summary.json`). Total: **9 tests passed**.
- Captured before/after towel focus and the late bedsheet were visually checked:
  the model is larger and centered, with complete silhouettes and reachable
  controls. Images are in `named-screens/`.
- Signed Release build verified with `codesign --verify --deep --strict`.
- Installed on the paired iPhone 17 Pro Max. Independent app inventory confirms
  `org.realitycore.protacta.prototype`, version **1.0 (35)** in
  `installed-app.json`; installation receipt is `install.json`.

The initial physical launch was rejected by iOS because the phone was locked
(`launch.json` / `launch.log`). Installation is verified; physical interaction
acceptance is still pending. No TestFlight or App Store upload is included.

## Physical check

1. Open Everyday → Towel and reach action 3. Drag to the folded end.
2. Tap the viewfinder beside More. The folded towel should grow and center;
   action 3 and the same percentage must remain selected.
3. Drag backward. The view should return to the complete movement once, then
   remain stable through further dragging. Play/replay should show the full fold.
4. Repeat on Bedsheet's final action. Enter and leave AR; the physical model's
   scale/placement should not change because of studio focusing.

Any subsequent physical launch feedback is recorded below when available.

The phone was subsequently unlocked and the same Build 35 launched successfully
(`launch-unlocked.json`, PID 24698). The user reported that the towel and shirt
still look like rigid paper rather than realistic fabric; this is the next
visual work item. Focus interaction acceptance has not yet been reported.
