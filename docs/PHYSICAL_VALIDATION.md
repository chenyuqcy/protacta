# Real-paper acceptance protocol

Status: not executed. Build 5 installation/launch was verified, but the user
deferred physical testing while local checks continue. Build 6 and later require the new
PTC2 revision-2 sheet; update the app and paper together. Synthetic images and
simulator screens do not establish a result in this protocol. The executable
review forms and pilot script are in [physical-review/README.md](physical-review/README.md).

## Prepare a reproducible session

- Record device, OS, app commit, orientation and practice-sheet revision.
- Print the bundled PDF on white A4 at Actual Size / 100%. Measure the 14 mm
  code matrix and an A4 edge; note printer scaling and camera lens choice.
- Use a plain dark mat, even lighting and a phone stand. Photograph the setup
  separately only when deliberately collecting evaluation data; the app does
  not retain camera frames during normal practice.
- Give each full-course attempt and physical sheet distinct IDs. Keep one
  attempt's neighboring frames and corrected variants in the same dataset split.

## Registration and lifecycle

| Case | Required observable behavior | Record |
| --- | --- | --- |
| Flat natural sheet | Direction confirmation, crease drawn at the intended location | Independent crease endpoints and viewport size |
| Printed sheet translated/rotated | Coded TOP remains attached to the same physical end, including 180-degree rotation | Independent points along the top, center and bottom; do not use the four fitted centers as accuracy evidence |
| Distance and oblique views | Align only while the whole support region remains usable | Point/line error and rejected views |
| Hand/code occlusion, removal, duplicate sheet | Cues disappear on uncertainty, resume only after valid current evidence | Last valid timestamp, cue-hide time, recovery time, false alignment count |
| Fold, lift or curl the sheet | No flat-plane cues trusted across nonplanar deformation | Which unsupported shapes were rejected or falsely admitted |
| Background, camera denial and interruption | No stale cue/check survives; an explicit recovery path remains | Visible state before/after and crash/black-feed occurrence |
| iPad portrait/landscape and resizing | One rotation/crop transform, semantic code identity preserved | Independent display points in each orientation |

The 350 ms observation lifetime, 4 Hz admission limit and marker residual
thresholds are software settings awaiting measured end-to-end latency. If most
valid results expire, measure the processing path before changing the lifetime.
Do not hide lag by counting expired observations as valid alignment.

## Visible-outline checks

Physically review all ten actions first. Confirm that the 20 mm code-plus-quiet
zone boxes stay visible and coplanar in candidate states 0 and 2-6. Disable a
candidate if this does not hold. Actions 1 and 7-10 remain manual/3D checks.

For each supported checkpoint, collect independent examples in these groups:

- Correct visible boundary in varied supported poses and lighting.
- Incorrect visible boundary, including previous-step paper, the opposite-side
  fold, a small edge displacement and a large mismatch.
- Cannot judge: shadow, clipped sheet, hand, low contrast, missing/duplicate code,
  lifted layers, unfamiliar paper and unrelated white objects near the sheet.
- Negative controls: a newly printed flat sheet and the reopened state 2 have
  the same boundary. Neither may be described as proof of a center crease.

Label visible criteria separately from whether the whole fold is correct.
Report the three-way confusion matrix, false visible-match count on incorrect
and unclear examples, cannot-judge frequency and counts per checkpoint. Keep
development sessions separate from the final evaluation sessions. A matching
silhouette cannot validate hidden layers, fold order or pressure.

## Course and beginner pilot

Have a reviewer follow the entire physical sequence using the authored text,
3D actions and practice paper. Amend draft help based on observed ambiguity;
record the reviewed content revision before collecting learner outcomes.

Then run the exploratory beginner comparison proposed in the build plan. Use
the same task and stopping rule for the 3D/text reference condition and guided
practice condition; record completion time, required interventions, where each
person gets stuck and a separately judged visible final result. Counterbalance
order or use separate beginners so prior folding experience does not masquerade
as an app improvement. Report individual observations and sample counts; do not
invent a percentage improvement from a demonstration.

## Exit evidence

Save device/install receipts, independent registration errors, check results and
reviewed tutorial revisions in a dated local validation folder. The full MVP is
accepted only after these physical and learner gates, not by compilation alone.
