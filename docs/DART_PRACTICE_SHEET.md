# Dart practice sheet

Current print contract: **PTC2 revision 2**, layout ID
`protacta-dart-a4-ptc2`. Print a new sheet for this version; PTC1 sheets cannot
establish camera alignment. The PDF metadata title identifies PTC2 revision 2.

Generate `output/pdf/Protacta_Dart_Practice_A4.pdf` with:

```sh
python3 scripts/generate_dart_practice_sheet.py
```

The generator requires ReportLab. Print the single page on white A4 paper at
**Actual size / 100%**. Disable fit-to-page, printer headers and footers. The page
is deliberately mostly blank: extra text or artwork would interfere with the
visible-outline experiment.

The checked PDF is bundled as `ios/PaperSteps/Resources/Protacta_Dart_Practice_A4.pdf`.
In complete Dart practice, open the printer button to share or print it. Keep
both code rows at the end closest to the learner; the other short edge is TOP.
All four IDs retain direction even when the phone or sheet rotates.

Place the sheet flat on a dark plain mat. The four codes identify positions on
the original sheet, allowing the guide to retain orientation after upper-corner
folds. The code matrix is 14 mm square, with a 3 mm white quiet zone on each side.
Code centers, measured from the top-left of an uncut 210 x 297 mm A4 sheet, are:

| Code | Normalized center | Center in mm |
| --- | --- | --- |
| PTC2A | 0.30, 0.72 | 63.0, 213.84 |
| PTC2B | 0.70, 0.72 | 147.0, 213.84 |
| PTC2C | 0.70, 0.94 | 147.0, 279.18 |
| PTC2D | 0.30, 0.94 | 63.0, 279.18 |

All four matrices have the same orientation. The bundled
`Resources/DartPracticePaper.json` is the printing and interpretation contract.
In the ideal authored geometry, their full matrix and quiet-zone boxes remain
stationary and top-layer visible at Dart flat states 0, 2, 3, 4, 5 and 6.
`DartPracticePaperVisibilityTests` maps each original material footprint into
the folded mesh, then checks its continuous polygon for overlap with higher
paper layers. Silhouette containment alone does not establish visibility.
State 1 and the later lifted body/wing states are not eligible for the
flat-outline check.

The old PTC1 first row lay underneath the correct narrowing flaps at states 5
and 6. Its unchanged PDF and JSON are retained under
`docs/reference/ptc1-layout-obsolete/` for historical validation records only.
PTC2 moves the columns inward, retaining the vertical row baseline. The changed
horizontal baseline still requires independent physical alignment measurement;
ideal-model visibility does not establish camera accuracy.

`DartOutlineChecker` compares only a visible silhouette. Use even lighting and
clear hands or other objects before checking. Its initial brightness, contrast
and mismatch thresholds are uncalibrated experimental parameters. It does not
validate a center crease, hidden layers, paper thickness or a correct finished
fold. A white obstruction may be indistinguishable from the paper. Real printed
paper, camera angles, lighting, marker decoding and false approvals still need
physical testing; synthetic tests cannot establish those results.
