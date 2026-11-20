# Everyday course Simulator walkthrough

Requested by the user on 16 November 2026. Candidate: Protacta 1.0 (32),
`org.realitycore.protacta.prototype`, iPhone 17 Pro Max / iOS 26.5 Simulator.
This records local use; it does not replace camera or physical-object testing.

## Observed manual use

The app was opened from its normal SpringBoard icon, without camera fixtures or
UI-testing launch arguments. The three-page introduction completed and the
home page loaded. Opening Towel displayed the actual animated 3D model.

- Automatic playback advanced the first fold and stopped at 100%.
- Tapping Play then Pause held the model at 23%; a later observation retained
  that pose. Play resumed and progressed to the finished first fold.
- Tapping **I've done it · Next** changed the counter to **ACTION 2 OF 3** and
  animated the second fold.
- Returning to the home page and opening Towel again restored action 2.
- Tapping **AR** displayed the supported-device message and retained the
  usable 3D model, current action, playback and confirmation controls.

The native macOS accessibility value setter moved the slider thumb without
updating the model's progress. That operation is not counted as a drag test.
Actual touch-slider behavior is checked by the XCTest Simulator UI flows below.

## Automated touch-flow verification

Status: **Passed — 4 tests, 0 failures, 0 skipped.** Receipt:
`output/simulator-walkthrough-20261116/EverydayUserFlow.xcresult`.

Selected cases cover all five courses' playback/pause/scrubbing and explicit
next action; every one of the 25 actions through completion and reopen; Help
replay and independent saved progress after app relaunch; and genuine Simulator
AR unavailability without a synthetic camera fixture.

The complete-course flow moves the timeline through the intermediate and final
poses before confirming each action; it does not establish that all 25 actions
were naturally played to the end. Separate playback/pause checks and the manual
Towel walkthrough verify timed animation. No crashes or blocked lesson flows
were observed in these checks. No application code was changed for this run.

- Machine-readable result: `output/simulator-walkthrough-20261116/summary.json`.
- Test log: `output/simulator-walkthrough-20261116/tests.log`.
- 76 named screenshots: `output/simulator-walkthrough-20261116/screenshots/`.
- Towel midpoint: `Everyday_towel_3D_mid_move.png` in that screenshot folder.

## How to use

1. Choose **Everyday** on the home page, then **Towel**, **T-shirt**, **Bedsheet**,
   **Square knot** or **Four-in-hand**.
2. Watch the movement. Use **▶︎ / Pause** or drag the timeline to inspect it.
3. After trying the action, choose **I've done it · Next**. Before animation
   finishes, that same button continues the current movement instead.
4. Use **←** to review the preceding action, or **Help** for the current one.
5. Return home and reopen the lesson to resume the saved confirmed action.
   Reopening does not promise to retain an intermediate animation percentage.

The Simulator supports 3D interaction. Actual camera placement, three-point
cloth fit, hand occlusion and live speech recognition remain iPhone checks.
