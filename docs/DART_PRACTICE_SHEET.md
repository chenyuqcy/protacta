# Dart practice sheet

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
| PTC1A | 0.16, 0.72 | 33.6, 213.84 |
| PTC1B | 0.84, 0.72 | 176.4, 213.84 |
| PTC1C | 0.84, 0.94 | 176.4, 279.18 |
| PTC1D | 0.16, 0.94 | 33.6, 279.18 |

All four matrices have the same orientation. The bundled
`Resources/DartPracticePaper.json` is the printing and interpretation contract.
Their quiet-zone boxes remain on stationary visible regions for Dart flat
states 0, 2, 3, 4, 5 and 6. State 1 and the later lifted body/wing states are not
eligible for the flat-outline check.

`DartOutlineChecker` compares only a visible silhouette. Use even lighting and
clear hands or other objects before checking. Its initial brightness, contrast
and mismatch thresholds are uncalibrated experimental parameters. It does not
validate a center crease, hidden layers, paper thickness or a correct finished
fold. A white obstruction may be indistinguishable from the paper. Real printed
paper, camera angles, lighting, marker decoding and false approvals still need
physical testing; synthetic tests cannot establish those results.
