# Independent raw-PNG annotation

Open `index.html` directly in a current desktop browser. It uses local scripts,
native file selection, Canvas and Web Crypto; no backend, library, account,
external service or AI is required. It does not open files until you select them.
Nothing is uploaded. The page keeps its preview in memory and downloads only the
JSONL you explicitly request; it uses no localStorage or other persistent store.
For browser automation that blocks file URLs, the same files may be served by a
temporary loopback static server. Only tool assets are requested; selected
capture files are read in page memory and are not posted to that server.

This tool makes the existing evaluator's label format usable. It does **not**
approve a course, confirm a fold, certify a source declaration or issue an MVP
acceptance result. Actual data and review are still required.

## Label a capture

1. Choose the exported `sample.json` and its matching original `image.png`.
   Dimensions and SHA-256 must agree. The tool checks PNG structure/CRCs; the
   browser must also decode the image successfully. Maximum preview is 16
   megapixels / 64 MiB. A bounded, well-formed PNG TIFF/EXIF block is accepted only
   when orientation is absent or exactly 1 (upright), including native ImageIO's
   Exif child IFD. Rotations, mirrors, duplicate/conflicting orientation metadata,
   cyclic/invalid IFD pointers and unsupported orientation fields are rejected.
   Nothing is stripped, rotated or re-encoded: SHA-256 still checks the exact
   original export bytes. Use the original export, not a portrait screenshot.
2. Enter an annotator pseudonym, not a name or email. Decide the visible-outline
   label yourself using the reviewed checkpoint criteria. No label is selected
   by default. Detector outcomes, quads, fitted points and mismatch hints are
   deliberately absent from the preview.
3. Geometry is optional and enabled **only for flat reopened state 2**. If all
   four ORIGINAL sheet corners are visible, enable it and click paper TL, TR,
   BR, BL in that order. Use the paper's marked TOP direction even when the raw
   image is sideways. These are not QR corners. Nothing snaps or generates a
   point for you. Undo and zoom are available.
4. If a corner is hidden, shifted by a fold or ambiguous, leave geometry off.
   Folded/other states export `landmarks: []` and `paperWidthReference: null`.
   A rectangular outline in state 2 does not prove that its centre crease exists.
5. Explicitly confirm your annotation and download one JSONL line. Changing the
   sample, label, reviewer ID or corner clicks clears the confirmation. A new
   sample also clears the old label and geometry.

The four corner clicks use known paper-plane positions `(0,0)`, `(1,0)`,
`(1,1)`, `(0,1)`. They are independent observed raw pixels, not detector points.
Paper BL and BR supply the full-width segment at `sheetY: 1`. The tool validates
click count, coordinate bounds and a non-crossed quad; it cannot prove that a
person actually selected paper rather than QR corners. That remains the
annotator's explicit responsibility. No hidden coordinate is imputed.

Raw coordinates are edge-based: x spans `0...width`, y `0...height`, top-left
origin. Pixel `(i,j)` has centre `(i+0.5,j+0.5)`. CSS zoom/scroll changes the
display only. No phone viewport transform or predicted homography is applied.

## Provenance and evaluator compatibility

Input `synthetic_fixture` always exports `annotationSource: synthetic_fixture`,
even when a human or UI automation clicks Export. There is no “make real” toggle.
Declared `physical_camera` input can export `annotationSource: human` only after
an explicit annotation/confirmation action. These tags are preserved declarations,
not cryptographic proof that an image came from a camera or received honest review.

Output contains exactly the fields consumed by `load_labels` in
`../../scripts/evaluate_practice_validation.py`: sampleID, annotationSource,
annotatorID, checkpointID, referenceState, expectedOutcome, landmarks and
paperWidthReference. There is no reviewed/approved/acceptance field. The existing
evaluator remains authoritative for candidate identity, paper-layout compatibility,
leakage, timing and dataset-wide integrity.

For several downloads, put the `annotation-*.jsonl` files in one folder and join
them, without duplicating sample IDs:

```sh
cat annotations/annotation-*.jsonl > annotations.jsonl
```

Then use that file with the existing evaluator command. Keep generated test
fixtures and real captures separate. This tool does not create capture data or
provide already-filled real annotations.

## Tests

From the repository root:

```sh
node --test tools/validation_annotator/tests/core.test.js
```

The tests use only Node built-ins and generated PNGs. They exercise integrity,
raw pixel conversion, optional corner geometry, mandatory explicit inputs,
source preservation and the exact export schema. Physical-source branches in
unit tests are synthetic code-path fixtures, not collected physical evidence.

The browser UI exposes `metadata-file`, `image-file`, `expected-outcome`,
`annotator-id`, `geometry-enabled`, `raw-image`, `confirm-annotation` and
`export-label` IDs for a local UI smoke test. The testable API lives in `core.js`:
`verifySample`, `imagePointFromClient`, `buildAnnotation` and `toJSONL`.
