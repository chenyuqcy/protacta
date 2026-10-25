# Complete-course prototype validation

25 October 2026. Protacta 0.1.0 (2). Software prototype evidence; the active MVP
goal remains incomplete. Result counts are recorded below and in
output/full-course/validation-receipt.json.

## Validation boundaries

Logic checks cover ten-action content, explicit confirmation, revisions and
bounded persistence without live camera state. Capture tests cover stale,
pre-request, wrong-step and canceled results; limited tracking and background
cannot revive old cues. Authored 3D geometry and independent analytic silhouettes
are compared, including state 0/2 ambiguity. Native QR tests use both generated
images and the actual bundled PDF; geometry holds out code corners rather than
evaluating only the four fitted centers.

Simulator UI covers check/help, reference and return, all ten user confirmations,
completion/rewind, loss recovery and tablet landscape. The fixed sample drawing
is deliberately labeled NO LIVE CAMERA. A match in the UI fixture is not a
Vision accuracy result.

## Problems found and repaired

- Float transforms left a nearly collinear redundant hull vertex at states 5/6.
  Hull tolerance now scales by edge length; exact analytic-shape assertions stay.
- Limited tracking could previously let an in-flight result restore practice
  cues. It now invalidates requests/registration and gates callbacks until recovery.
- The actual-PDF test raster was reflected and offset by a Quartz transform.
  Correcting the transform preserved expected corners and physical assertions.
- Screenshot review found dark text on black confirmation buttons. Explicit
  white labels restore contrast; the simulator watermark stays in the viewport
  while the instructional card scrolls.
- A logic-test host failed before XCTest connected, inside RealityKit's Metal
  shader reflection. Debug unit-test hosting now opens an empty window instead
  of an unnecessary live renderer. UI tests still open the full application;
  the framework crash receipt is retained rather than counted as a test pass.

## Simulator barcode compatibility

The tested iOS 18.3.1 simulator's default barcode revision 4 initially could not
create an inference context. A supported CPU removed that error but returned no
codes. The same generated image and actual PDF produced no codes with revisions
3/4, while revision 1 on CPU decoded all four. Geometry gates remain unchanged.

Only Simulator selects revision 1 and a supported CPU. Physical iOS builds keep
the framework's default revision and automatic compute selection. The simulator
tests therefore do not validate the device algorithm, performance or detection
behavior. Failed hand processing still rejects the pose rather than substituting
an assumed hand-free view.

Compute selection follows the local SDK and Apple's
[VNRequest compute-device API](https://developer.apple.com/documentation/vision/vnrequest/setcomputedevice(_:for:)).

## Results and next gate

| Evidence | Result | Scope |
| --- | --- | --- |
| 20261025T100758Z-dart-logic/Practice.xcresult | 144 passed, 0 failed, 0 skipped | Logic, synthetic pixels and native simulator Vision checks |
| 20261025T100904Z-dart-phone/Practice.xcresult | 5 passed, 0 failed, 0 skipped | iPhone 16 Pro Simulator, iOS 18.3.1; both practice and first-fold UI |
| 20261025T101038Z-dart-tablet/Practice.xcresult | 7 passed, 0 failed, 0 skipped | iPad Pro 13-inch M5 Simulator, iOS 26.5; portrait and landscape UI |
| output/full-course/device-release-build.log | BUILD SUCCEEDED | Generic iOS Release build, code signing disabled; no installation |

The result bundles live under output/validation/. Different device runs repeat
some UI cases; counts are not claimed as distinct user trials. Release identity
is org.realitycore.protacta.prototype, version 0.1.0 build 2. The practice PDF and
layout are bundled; StoreKit fixtures and code signing are absent. All 85 files
in the original Foliafold baseline still match their recorded hashes.

Phone/tablet screenshots, actual-PDF raster checks and their export manifests
are in output/full-course/. Final preview images retain their explicit synthetic
watermarks. Earlier failed runs and the framework crash are retained as history,
not included in the passing counts. No physical-camera, fold-correctness or
beginner result is claimed. PHYSICAL_VALIDATION.md is the next device protocol.
