# Offline practice-validation data, schema 1

This is an offline reporting format, not physical acceptance evidence. There is
no real-paper dataset bundled with the harness. Its unit tests generate clearly
labeled **synthetic fixtures** in temporary folders. Synthetic projection,
confusion and timing values cannot establish camera accuracy, hardware latency,
fold correctness, learner benefit or completion of the startup MVP.

Run the standard-library Python tool after collecting and independently labeling
actual captures:

```sh
python3 scripts/evaluate_practice_validation.py \
  --samples /path/to/exported-sample-folders \
  --labels /path/to/independent-annotations.jsonl \
  --output-dir /path/to/offline-report
```

It writes `validation_report.json` and `validation_report.md` on successful input
validation. Exit status 2 rejects invalid input and does not refresh reports.
Do not interpret a pre-existing report as the result of a failed run. Keep the
output directory outside the captures directory: every `*.json` under `--samples`
is treated as a sample manifest. Empty capture/label inputs produce counts of
zero and null statistics, never a pass. Unlabeled samples are listed explicitly;
they can contribute timing but never an inferred human label or geometric score.
Manifests anywhere inside `.capture-*` staging paths are rejected, including
passing a staging folder directly as `--samples`. Interrupted atomic exports
cannot be counted. Other descriptive names for completed folders are allowed;
the harness does not require folders themselves to be UUIDs.

## App-exported sample metadata

Each capture folder contains `sample.json` and the referenced PNG, usually
`image.png`. Schema keys are camelCase, matching the native exporter.

| Field | Required value / meaning |
| --- | --- |
| `schemaVersion` | Integer `1`. |
| `id` | Canonical UUID string; unique across the entire run. |
| `tutorialID` | Exactly `classic-dart`. |
| `courseRevision`, `appVersion`, `appBuild` | Nonempty single-line strings, at most 160 UTF-8 bytes each; exact candidate identity. |
| `paperLayoutID`, `paperLayoutRevision` | Current exports require `protacta-dart-a4-ptc2`, integer `2`. Historical PTC1 records use `protacta-dart-a4-ptc1`, integer `1`; only exact legacy fitting points may infer this pair when both fields are absent. |
| `source` | Exactly `physical_camera` or `synthetic_fixture`. Never mix these in one report. |
| `split` | Exactly `development` or `evaluation`. These are preassigned evidence groups, not random frame splits. |
| `sessionID`, `operatorID`, `sheetID`, `attemptID` | Nonempty pseudonymous capture-session, operator, physical-sheet and whole-course-attempt IDs. Reuse the same ID when the same entity reappears. |
| `originID` | Canonical original-frame/burst/video identity. Derivatives retain their source identity. |
| `sourceBasename` | Canonical source basename such as the original frame UUID plus `.png`; **not** the repeated export filename `image.png`. Copies/frames/crops must preserve source lineage. |
| `checkpointID`, `referenceState` | Requested checkpoint and source state; integer state `0...10`, including preparation `0`. They must match the independent annotation. |
| `capturedUptime`, `processedUptime` | Finite nonnegative timestamps on one monotonic clock; processed must not precede captured. |
| `image` | Object with positive integer `width`, `height` (maximum 16384 each), `orientation: "raw_top_left"`, relative `path`, and actual PNG `sha256`. The file must stay inside the sample folder. |
| `rawSheetQuadrilateral` | Object with `topLeft`, `topRight`, `bottomRight`, `bottomLeft`, each `{x,y}` in normalized **raw-image** coordinates, or explicit `null` when registration is unavailable. Names preserve semantic paper-corner identities, not a fresh image-space sort. |
| `registrationPoints` | List of `{id, sheet:{x,y}}` for all 20 known fitting QR centres/corners, even when no pose is available. IDs/positions must match the pinned layout named by the metadata. |
| `result` | Object with `outcome`, nonempty `message`, `timestamp` exactly equal to `capturedUptime`, and `support: "visible_outline_only"`. Outcome is exactly `visibleMatch`, `needsAdjustment` or `cannotJudge`. No pose requires `cannotJudge`. |
| `frameDisposition` | Optional `fresh` or `expired`. Expired requires `cannotJudge`. Missing disposition is reported as `unreported`, never assumed fresh. |
| `processingMs` | Optional finite nonnegative algorithm-processing duration, no greater than capture-to-processing elapsed time (0.001 ms rounding allowance). Omit it when not measured. |
| `frameAgeMs` | Optional finite nonnegative delivery/frame age, no smaller than capture-to-processing elapsed time. If omitted, the report derives `(processedUptime - capturedUptime) * 1000`. This is **not** algorithm processing time. |
| `processingFailure` | Optional nonempty explanation; if present the outcome must be `cannotJudge`. |

Every report contains exactly one `(tutorialID, courseRevision, appVersion,
appBuild)` tuple. Mixing builds or course revisions is rejected rather than
silently aggregating their results. JSON and Markdown report that identity;
empty reports expose a null/unavailable candidate rather than guessing a version.
Every report also contains one paper-layout ID/revision. PTC1 and PTC2 cannot be
pooled. The evaluator pins PTC2 in bundled `DartPracticePaper.json` and PTC1 in
`docs/reference/ptc1-layout-obsolete/`; it never reinterprets old coordinates as
the new layout. These declarations identify the intended candidate and do not
prove the photographed sheet is correct.

Optional contextual metadata may include `device`, `viewport`, marker
quadrilaterals and result mismatch points. These do
not override the raw-image coordinates or independent labels. The harness rejects
nonfinite JSON numbers anywhere, including optional metadata, and verifies the
PNG hash, dimensions, chunk lengths/types/CRCs, IEND and decoded IDAT scanline
size/filter values. Supported export PNGs are noninterlaced 8-bit grayscale,
RGB, gray-alpha or RGBA, with 64 MiB file/decoded-data limits. The tool does not
classify image contents or certify
that the exporter’s device/source declarations are truthful.

Collector IDs use only letters, digits, `_`, `.` and `-`: at most 80 characters
for session/operator/sheet/attempt/origin and 164 for a canonical
source PNG basename. Root-style `sessionUUID_frame_monotonicTimestamp.png`
names are supported. These source names are not required to be UUID-only;
the sample's `id` itself remains a UUID.

An expired frame may retain the raw-frame pose for measuring that same image.
Such a measurement says nothing about whether the pose would be safe to show
over a later live frame. Reports retain its expired disposition and explicitly
decline live-alignment acceptance. Fresh disposition is also not acceptance.
Fresh requires both capture-to-processing elapsed time and delivered frame age
to be at most 350 ms. Any stale/unknown-disposition frame beyond that limit must
have `cannotJudge`; it cannot report a live accepted comparison.

## Independent annotation JSONL

Use one JSON object per line, separately from app output. Required fields:

| Field | Meaning |
| --- | --- |
| `sampleID` | Exactly one exported UUID. Duplicate annotation IDs and unknown samples are rejected. |
| `annotationSource` | `human` for physical captures; `synthetic_fixture` for generated unit-test labels. Generated labels must not masquerade as human review. |
| `annotatorID` | Nonempty pseudonymous reviewer/fixture-generator identity. |
| `checkpointID`, `referenceState` | Must exactly equal the sample's checkpoint/state. |
| `expectedOutcome` | One of the same three outcomes, describing only the declared visible-outline criteria. |
| `landmarks` | List, possibly empty, of `{id, sheet:{x,y}, rawPixel:{x,y}}`. Each is an independently annotated known reference point, not a model output. |
| `paperWidthReference` | `null` without geometry, or `{sheetY, leftRawPixel:{x,y}, rightRawPixel:{x,y}}` as described below. Required when landmarks are supplied. |

The outcomes mean:

- `visibleMatch`: the declared visible criterion matches; hidden creases, layer
  order, fold strength and the rest of the course remain unassessed.
- `needsAdjustment`: a reviewed, visible outline mismatch is actually supported
  by this view. It is not a guess about a hidden fold.
- `cannotJudge`: insufficient or ambiguous evidence, wrong view, missing codes,
  occlusion, unsupported state/material or another declared limitation.

Do not label paper as correct because the app displayed a high-confidence pose.
A separate reviewer should resolve unclear labels; leave genuine uncertainty as
`cannotJudge`. In particular, states 0 and 2 can share the same rectangular
boundary without proving that a centre crease was made.

### Coordinates, width and holdouts

Raw pixel coordinates use **image edges**: x spans `0...width`, y spans
`0...height`, top-left origin, x right and y down. Pixel index `(i,j)` has centre
`(i+0.5,j+0.5)`. Normalized raw x/y multiply by **width/height**, not width-1,
height-1 or viewport dimensions. Display rotation/cropping is not used in these
offline raw-frame measurements.

`sheet` coordinates describe the known position in the stationary reference
paper plane. Use visible, nondeforming reference features whose plane positions
are independently known. An original material point that has moved during a
fold is not still at its old reference-plane coordinate. Expected outline
geometry is not automatically a ground-truth annotation of that moved point.

Every holdout must be separate from the fitting features by both ID and position.
The tool rejects an identical fitting ID or a sheet-coordinate distance within
1e-6 of any declared registration point. All fitting QR centres **and corners**
belong in the exclusion list. The known 20-point list is checked against this
sample's named pinned layout: preserve that source alongside the capture software,
rather than replacing it while evaluating older data. Its reprojection residuals cannot be reported as
independent accuracy.

Supply independent points across the region where a cue is intended, including
the **upper sheet** while it is flat. Good agreement near four lower printed
codes does not prove accurate extrapolation toward the top. The synthetic unit
test `test_biased_lower_marker_fit_is_exposed_by_an_independent_upper_point`
demonstrates that a small opposite bias in the lower code rows can produce over
3% paper-width upper-sheet error. This is an arithmetic warning, not a measured
device result or an assurance that a revised fitter solves it.

The normalization segment spans the **full original paper width**, x=0 to x=1,
at the same known row `sheetY`. For supported Dart states 0 and 2–6, choose the
unchanged bottom region, `0.95 <= sheetY <= 1` (for example the protocol row
0.97). Independently annotate its actual left/right endpoints in the image; the
pixel distance between these endpoints is the denominator. Do not use image
diagonal, bounding-box diagonal, half-width of folded paper, marker spacing or
the predicted mapping as a substitute. The tool rejects unsupported states,
invalid row/range, nonfinite/out-of-frame points and degenerate width segments.
It cannot prove that a person annotated the actual full-width endpoints: that
still needs reviewed capture instructions and human checking. If they cannot be
observed/measured independently, leave geometry unscored.

The optional browser tool in `tools/validation_annotator/` displays the exact raw
PNG while hiding detector predictions. It initially assigns no label and exports
only after an explicit choice and confirmation. It supports original-corner
geometry only for flat reopened state 2; other states remain classification-only.
Synthetic inputs always export `synthetic_fixture`, including automated browser
smoke checks. See its README for limits and the physical-review packet for the
unexecuted human protocol.

For each held-out landmark:

```text
errorPx = distance(predicted raw-image point, independently observed point)
errorPaperWidths = errorPx / independently annotated full paper width in pixels
```

The report includes every point and each sample's median, p95 and maximum. p95
uses linear interpolation between sorted samples, not a rounded rank. Aggregate
point statistics and the distribution of per-sample medians are separate so a
capture with many landmarks is not mistaken for many independent attempts.

## Split leakage and evidence scope

Never split neighboring frames or alternate crops at random. A session,
operator, physical sheet, attempt or origin cannot cross development/evaluation.
The tool rejects those shared IDs (case-insensitively), matching canonical source stems and identical
PNG hashes across splits. It also recognizes explicit frame/crop/augmentation/
resize/copy/rotation/flip suffixes and trailing three-or-more-digit frame indices
in non-UUID basenames. This name heuristic supplements honest origin IDs; it
cannot discover an undocumented, transformed duplicate with unrelated names.

Tune only on development data and freeze the code/checkpoint/feedback revision
before evaluating held-out data. Repeatedly tuning against the evaluation report
makes that group development data; preserve another untouched group. Use new
operators/sheets/sessions rather than inflating sample counts with adjacent
frames. Keep physical and synthetic reports separate, even with identical labels.

Reports show each split and checkpoint's full three-way confusion matrix. False
`visibleMatch` on a labeled error is counted separately from false `visibleMatch`
on an unclear view, with each denominator printed as a count. Missing poses still
contribute to classification when labeled; they contribute no geometric point
errors. No percentage is fabricated when the denominator is zero. Timing is
reported with counts and units, and synthetic timing is explicitly synthetic.

## Optional lifecycle annotation events

Add `--events /path/to/lifecycle.jsonl` only when actual onset/display events have
been measured or independently annotated. No such events are inferred from
sparse exported stills. Each line requires `schemaVersion:1`, unique `id`,
`source`, `split`, `sessionID`, `attemptID`, `event` and finite nonnegative
monotonic `timestamp`. Source/split/session/attempt must match the capture set.
Within each attempt the input must already be chronological.

Events are `loss_onset`, `cue_hidden`, `features_visible`, `cue_shown`. The report
pairs loss-to-hide and features-visible-to-show in milliseconds, counts shown-
while-annotated-lost events, and exposes unpaired onsets rather than inventing
latencies. It rejects unknown events, duplicate IDs, overlapping unpaired onsets,
source/session mismatches and reversed time. Unpaired events are incomplete
evidence. The format currently does not establish continuous stability, hand
occlusion success or a false-display duration from isolated event counts.

## Run the harness's synthetic tests

```sh
python3 -m unittest discover -s scripts/tests \
  -p test_evaluate_practice_validation.py -v
```

Tests cover independent affine/projective points, paper-width normalization,
upper-sheet extrapolation bias, split/duplicate leakage, invalid metadata, PNG
integrity declarations, holdout exclusion, unclear/error false matches, missing
pose, expired frames, timing meaning, empty data, lifecycle sequences and CLI
output. Passing these tests validates software bookkeeping, **not** a physical
course, CV accuracy or an MVP. Continue using the physical and beginner-review
gates in [CLASSIC_DART_COVERAGE.md](CLASSIC_DART_COVERAGE.md).
