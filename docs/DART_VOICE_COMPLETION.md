# Dart completion voice boundary — Build 7

The Build 6 source audit found that completing Dart practice removes its voice
controls but does not stop VoiceGuide. Its action stays at 10; if action 10 has
already been viewed in 3D, the old animation step also stays at 10. Neither
index observer necessarily runs. When one does run, `contextDidChange()` can
rearm enabled listening. A queued Back or Restart can then reopen the completed
practice, and a queued reading command can narrate after completion.

This defect was identified from source/control-flow evidence, not from a real
microphone recording. The earlier Build 6 completion repair applied to everyday
courses; the Dart player has its own callback and needed its own boundary.

## Resulting behavior

- The final confirmation invokes `VoiceGuide.stop()` synchronously before
  mutating the completed session and removing its microphone controls. This
  cancels recognition, narration, pending permission and scheduled rearming.
- A completion observer closes voice tools for completion through another
  state path. The live callback also rejects every queued voice command while
  Dart practice is complete, before navigation or narration is dispatched.
- The controller refuses new microphone startup and direct practice navigation
  or narration commands on a completed practice. Stop remains harmless.
- Visible **Start again** and **Previous action** explicitly reopen practice.
  Voice is available again but never starts automatically. Ordinary 3D lesson
  voice Restart remains available and does not change separate practice records.

The change uses PTC2 revision 2 from Build 6 without changing the print layout,
Dart teaching content, content fingerprint or CV thresholds. Build 6 artifacts
remain in their original output folders; Build 7 device builds use a separate
`output/DartVoiceCompletionDeviceDerivedData/` folder.

## Regression scope

Five added native cases cover ordinary versus final confirmation, stop-before-
mutation order both with/without final-action 3D replay, all queued/direct voice
commands, explicit reopening, ordinary 3D compatibility and restored completed
progress. They inject stop/dispatch callbacks and use real controller/session
logic without asking for microphone permission.

A new Simulator UI case follows action 10 into 3D, returns, confirms completion,
checks that voice controls disappear, then explicitly restarts and checks that
the controls return. It checks UI/state availability; it does not prove that a
physical microphone, permission prompt or audio interruption behaves correctly.

## Local checks

- **241 native tests passed, zero failed/skipped**, on iPhone 16 Pro Simulator
  iOS 18.3.1. This includes the eight-case command-boundary suite and existing
  geometry, CV, progress, lifecycle and integration regressions. Result:
  `output/validation/20261025T183117Z-dart-logic/Practice.xcresult`.
- **Four phone UI cases passed, zero failed/skipped**, on iPhone 17 Simulator
  iOS 26.5: the new final-action replay/completion/restart path, complete ten-action
  course, Setup/Help dismissal, and background/explicit camera recovery. Result:
  `output/dart-voice-completion/Phone-UI.xcresult`.
- All 85 original Foliafold files and six AERIS source files match their pinned
  hashes. Both Build 6 device executables and the PTC2 PDF also retain their
  recorded hashes. Evidence: `output/dart-voice-completion/preflight.json`.
- Generic iOS **signed Debug** and **unsigned Release** builds passed. Both
  bundles identify version 0.1.0/build 7; Debug's strict signature verification
  passed. The PTC2 PDF and teaching fingerprint are unchanged from Build 6.
  Logs: `output/dart-voice-completion/device-debug-build.log`,
  `device-release-build.log` and `debug-signature-verification.log`.
- Build 6's separate Python evaluator and browser-tool results remain preserved;
  those unchanged tools were not rerun for this native-only repair.

The exact candidate identity and build receipts are recorded in
`output/dart-voice-completion/validation-receipt.json` and
`output/dart-voice-completion/candidate.json`.

## Acceptance still outstanding

No phone was queried or installed during this iteration because the user
deferred device testing. Build 5 remains the last confirmed phone installation.
Physical testing must use the matching current app and PTC2 sheet, review all ten
real actions, exercise real speech/camera interruption, collect independent
correct/wrong/unclear samples and review correction wording before the beginner
pilot. This local voice repair does not complete any of those gates.
