# Checker and local capture validation, build 3

25 October 2026. This is software evidence, not physical or beginner acceptance.

## Scope

The checker now considers ambiguous gray values in the expected exterior. A
gray corner can no longer disappear from both the missing/extra counts. An
exception is limited to a gray sample whose exact bilinear footprint consists
only of settled white and settled dark source pixels. Real gray source pixels
remain unknown. Independent straight/rotated/projective regressions preserve
`needsAdjustment` for clearly extra white paper. Sampling uses edge-normalized
image coordinates and actual pixel centers, with asymmetric gradient tests.

Printed analysis failures cannot return a pose even if corners exist. Frame
results carry measured processing start/end separately from capture time. A
requested local capture retains only its own admitted full-resolution buffer;
normal practice does not retain an extra image. Step, camera, registration,
viewport and time gates are checked before file export. Expired captures must
say cannotJudge; a later saved file cannot retroactively approve live guidance.

The local service validates image dimensions/timestamp, source, anonymous IDs,
PNG bytes, digest, atomic commit, busy limits, cancellation and no overwrite.
Physical recording requires a real device, Debug mode and the explicit launch
flag. UI fixture arguments and substituted CGImages cannot produce a physical
source record. Human labels and review conclusions are never generated.

## Recorded results

| Evidence | Result | Meaning |
| --- | --- | --- |
| output/validation/20261025T103840Z-dart-logic/Practice.xcresult | 168 passed, 0 failed/skipped | Logic, synthetic Vision, capture I/O and request boundaries |
| output/validation-capture-python-tests.log | 24 passed | Independent projections, normalization, confusion, PNG integrity, leakage, candidate isolation and staging rejection |
| output/validation-capture/synthetic-contract/report/ | One declared synthetic export parsed successfully | Native PNG/JSON to Python contract only; no physical data |
| output/validation-capture/Phone-UI.xcresult | 2 passed | Complete practice flow and refusal to record simulator evidence |
| output/validation-capture/Tablet-QA-UI.xcresult | 1 passed | Local settings and simulator-source refusal on iPad iOS 26.5 |
| output/validation/20261025T104054Z-dart-phone/Practice.xcresult | 5 passed, 1 framework launch crash | Full phone UI sweep; failed launch retained |
| output/validation-capture/Phone-Case-Retest.xcresult | 1 passed | Isolated rerun of the failed first-fold UI case |

The failure stack is in CoreRE's timebase update calling CoreMedia on the old
iOS 18.3.1 simulator, before the first test button appeared. The rerun is not a
claim that the underlying framework issue was fixed. The crash is retained as
`output/validation-capture/simulator-ui-framework-crash.ips`; physical stability
and older supported device/OS combinations still need actual-device checks.

Generic iOS Debug/Release compilation, bundle identity, source integrity and
device inventory are recorded in output/validation-capture/validation-receipt.json.
Unsigned compilation is not installation. The simulator barcode compatibility
boundary documented in VALIDATION_FULL_COURSE.md still applies.

## Remaining physical limitations

Four codes near the lower end can satisfy local residual checks while the fitted
plane extrapolates poorly at the upper tip. The evaluator includes an independent
upper-point synthetic counterexample (about 5.03% paper-width error) to show why
fit-point residuals cannot establish full-sheet accuracy. That number is not a
measured device error. Upper visible landmarks, actual correct/incorrect/unclear
frames, lighting and movement still need independent review on real paper.

No real camera dataset, reviewed full physical course or beginner outcome was
created during this software phase. GOAL_ACCEPTANCE_AUDIT.md lists the unfinished
requirements and the next gate.
