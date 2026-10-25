# Build 4 wireless installation and user testing

25 October 2026. User-authorized installation on the paired iPhone 17 Pro Max,
iOS 26.6.1. Runtime source commit: `457319f1552acb751571ace0d88d2f6691168bc4`.

## Verified installation gates

- Signed Debug build succeeded in `output/DeviceInstallDerivedData` using the
  existing development team; strict signature verification passed. The embedded
  profile includes the phone and expires on 29 July 2027.
- An initial wireless tunnel interruption resolved after the user confirmed the
  phone was unlocked. Installation used the local-network developer connection.
- `devicectl` reported installation of `org.realitycore.protacta.prototype`.
  A separate installed-app query confirmed **Protacta 0.1.0 (4)**.
- Launch and explicit foreground activation succeeded without test/validation
  arguments. A subsequent process query confirmed PID 4486 still running.
- Normal launch does not enable synthetic frames, StoreKit simulation or the
  opt-in camera-photo validation exporter. Foliafold uses a separate bundle.

Receipts: `output/device-install/build4-20261025/`, including `signed-build.log`,
`signed-artifact.json`, `install.json`, `launch.json`, `foreground-launch.json`,
`installed-app.json`, `running-process.json` and `installation-receipt.json`.
Earlier unsigned validation artifacts were not overwritten. No camera image or
physical-fold result was collected by the installation commands.

## Test on the phone

1. Select **The Classic Dart**. Test 3D rotation, zoom, pause, slow playback,
   replay and returning to the current step. Accept camera access when needed.
2. With an ordinary flat white A4 sheet on a plain dark surface, open **Guide on
   my paper**. Confirm the highlighted TOP edge using **Direction looks right**;
   use **Turn guide** if needed. Slowly move/rotate the paper and change distance.
   Observe whether the center line and arrow stay on the paper. Cover/remove the
   sheet: uncertain cues should disappear, then reacquire/reconfirm when usable.
   This mode covers the flat-paper first fold, not every later folded shape.
3. For **Practice the complete Dart**, open the printer icon and print the
   bundled practice PDF on white A4 at 100% / Actual Size. Keep all four codes
   visible, code rows nearest the learner, and use a dark mat and even lighting.
   Test all ten learner-confirmed actions, Previous action, I'm stuck and Watch
   in 3D; returning from 3D should preserve the same practice action.
4. After actions 2-6, try **Check my step** with the paper flat and hands clear.
   Compare a correctly shaped state with an intentionally incomplete visible
   corner. Record match/adjustment/unknown results, especially an incorrect shape
   accepted as a match. Action 2 cannot verify the center crease; actions 1 and
   7-10 use manual/3D comparison. Checks must never advance the course themselves.
5. Open **See this comparison**: inspect the frozen image, reference and red
   comparison areas. **Replay this action** should open the same action in 3D.
   Returning to the camera or changing action should clear the old image.
6. Enable optional voice, test Next step / Previous step / Show me again /
   Slower, and retain button access. In practice, Next step does not confirm a
   physical fold. Background/lock and reopen the app: old overlays should clear,
   camera recovery should be explicit and lesson progress should remain usable.

For a problem, record the mode, action, expected behavior, observed behavior and
optionally a screenshot. These are proposed user checks; no pass is asserted.

## Non-origami scope

The installed catalog has 12 origami lessons. Classic Dart alone has the new
full-course practice, QR alignment and outline checks. Clothes, bedsheets,
towels, knots and ties remain later-course plans; gift wrapping and 3D paper arts
remain team decisions. No generic object-recognition course is installed.

The sibling `ar_product_manual_demo` project has an independent AERIS purifier
manual prototype with authored filter replacement, setup/cleaning and exploded
3D/tabletop AR. It is not integrated into Protacta. Its virtual product placement
does not establish automatic registration to a physical purifier.
