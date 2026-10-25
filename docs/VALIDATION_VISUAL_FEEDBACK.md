# Build 4: frozen visual feedback

25 October 2026. Protacta 0.1.0 (4), prototype bundle
`org.realitycore.protacta.prototype`. The user chose local development now and
physical testing later. This record covers local software behavior only.

## Implemented behavior

An accepted **Check my step** can expose **See this comparison**. A single bounded
grayscale image, semantic paper quad, AR display transform, viewport and result
are captured together. The reference silhouette and comparison areas use that
frozen transform; later camera movement cannot move annotations on the image.
The native normal path uses the checker's at-most-320-pixel luminance image and
retains no extra full-resolution camera buffer. It performs no photo file write.

The comparison shows a green expected outline and a single translucent red mask
over sample areas to inspect. It does not count individual mistakes, infer a
hidden layer, identify a causal fold or certify success. Draft action-specific
comparison/help and same-action 3D replay remain separate from the learner's
explicit confirmation. Action 2 retains the center-crease ambiguity notice.

Paper analysis stops while the comparison is visible. Dismissal clears the image
and restarts registration, rather than reusing an old pose. New checks, action
changes, rescan, major tracking loss, camera failure, backgrounding and leaving
practice clear the transient image. Background/exit dismissal cannot restart a
paused camera. Ordinary missing-pose observations can hide live cues without
mutating an already captured comparison. Debug validation capture remains an
explicit, separate storage path and is unavailable during comparison review.

The Debug Simulator fixture now renders before-action pixels through the actual
outline checker: state 2 demonstrates the crease ambiguity; actions 3-6 produce
visible differences; unavailable, stale or unsupported samples remain unknown.
It is compiled only for Debug Simulator and displays a persistent synthetic
source label. It supplies no physical-camera accuracy evidence.

## Recorded checks

| Check | Result | Evidence |
| --- | --- | --- |
| Native focused logic and synthetic Vision | 195 passed, zero failed/skipped, iPhone 16 Pro Simulator iOS 18.3.1 | `output/validation/20261025T130505Z-dart-logic/Practice.xcresult` |
| Python offline evaluator regression | 24 passed | `output/comparison-python-regression.log` |
| Phone comparison, same-action replay, background recovery and complete course | 5 passed, iPhone 17 Simulator iOS 26.5 | `output/visual-feedback/Phone-UI.xcresult` |
| Tablet comparison and return controls in landscape | 1 passed, iPad Pro 13-inch (M5) Simulator iOS 26.5 | `output/visual-feedback/Tablet-UI.xcresult` |
| Final phone visual polish, asymmetric action 4 and crease-unknown notice | 2 passed, overlapping phone cases rerun | `output/visual-feedback/Phone-Visual-Final.xcresult` |
| Generic physical-iOS Debug and Release compilation | Both succeeded, signing disabled; no installation | `output/visual-feedback/device-debug-build.log`, `device-release-build.log` |

The 195 native cases include 11 snapshot, 8 generated-comparison and 8 review
lifecycle cases added to the prior 168-case selection. New checks cover bounded
images, stale/invalid geometry, preserved semantic direction, display transforms,
same-request acceptance, resets, background and return. A synthetic bi-planar YUV
test exercises the native luminance extraction with full/video range values and
an asymmetric pattern before checking snapshot pixels. This checks data handling,
not real camera quality or ARKit calibration.

The five initial phone cases and tablet case passed before the final red-mask
cosmetic adjustment. The final two phone cases were rerun after it. These counts
must not be summed as distinct independent scenarios or beginner participants.
An early compile attempt rejected ambiguous `.infinity` constants in new test
code; explicit `CGFloat.infinity` corrected it before the recorded passing runs.

## Visual inspection

Reviewed phone and tablet captures for frozen-image/outline correspondence,
permanent synthetic labels, readable controls and scope notices. The asymmetric
action-4 screenshot verifies that the already folded left side stays on the
left, with the expected right-side difference highlighted; the bitmap is not
vertically flipped relative to the overlay. Final red areas avoid the earlier
clutter of overlapping rings and retain a readable green boundary.

- Final phone preview: `output/visual-feedback/preview-synthetic-comparison.png`.
- Final source attachment: `output/visual-feedback/phone-final-attachments/369774F8-B908-4DED-9D8A-18596BCABACB.png`.
- Tablet attachment: `output/visual-feedback/tablet-attachments/8F5BC72F-7EB1-446C-A2D0-82B9463EB03B.png` (before cosmetic mask polish).
- Machine summaries and source hashes: `output/visual-feedback/validation-receipt.json`.

## Remaining acceptance

No phone was installed or queried during this local continuation. Natural-paper
and QR registration, actual camera orientation/latency, folded-paper boundaries,
the complete physical tutorial, draft help review, independently labeled real
examples and beginner outcomes remain unverified. Generic compilation and these
synthetic examples do not complete the startup MVP. Physical testing is deferred
at the user's request, not replaced by a simulated pass.
