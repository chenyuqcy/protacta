# Build 6 local readiness — 25 October 2026

Protacta **0.1.0 (6)** is a local candidate. It has not been installed on the
phone; **Build 5 is the last confirmed phone installation**. The user selected
“稍后测试，先继续本地检查”. No real paper attempt, physical image label or beginner
result was collected in this iteration. The complete-course MVP remains open.

## Defects corrected

The PTC1 upper codes overlap the moved upper layers in correct authored Dart
states 5 and 6. A silhouette-only containment test missed the covering layer.
The replacement **PTC2 revision-2** sheet puts all four complete code/quiet-zone
footprints on stationary, top-visible material for supported states 0 and 2–6.
The new tests preserve the old failure and evaluate material mapping plus
higher-layer coverage. This establishes the authored geometric contract, not
real print readability, alignment accuracy or robust tracking during movement.

The new QR IDs reject obsolete sheets; the app's Setup identifies the required
revision. Old JSON/PDF bytes remain under `docs/reference/ptc1-layout-obsolete/`.
New captures include the layout ID/revision, and the evaluator refuses mixed
layouts. The changed marker baseline must be measured independently on real paper.
Update the installed app and practice sheet together before collecting evidence.

Everyday, origami and product-AR lessons now share foreground screen-awake leases.
Only the last participating window restores the actual previous idle-timer value;
overlapping scene closure or background/foreground cannot overwrite another hold.
Completion stops voice rather
than rearming a microphone whose controls disappeared. Queued commands cannot
reopen a completed session. Dart Setup/Help synchronously stop voice/narration,
block command routing and release the gate only when their sheet dismisses.

## Checks performed

| Check | Result and scope | Retained evidence |
| --- | --- | --- |
| Native focused logic | 236 passed, 0 failed/skipped; iPhone 16 Pro Simulator, iOS 18.3.1 | `output/validation/20261025T181003Z-dart-logic/Practice.xcresult`, `output/physical-readiness/logic-final-summary.json` |
| Phone UI | 3 passed, 0 failed/skipped; iPhone 17 Simulator, iOS 26.5 | `output/physical-readiness/Phone-UI-Final.xcresult`, `phone-ui-final.log` |
| Offline evaluator | 28 Python tests passed, including legacy/current layout rejection cases | `output/physical-readiness/python-layout-tests.log` |
| Independent annotator core | 17 Node tests passed, including raw-coordinate identity, explicit labels, provenance and bounded EXIF validation | `output/physical-readiness/annotation-core-tests.log` |
| Generic device Debug | Build 6 succeeded with development signing; `codesign --verify --deep --strict` passed | `output/physical-readiness/device-debug-signed-build.log` |
| Generic device Release | Build 6 succeeded without signing; no install claim | `output/physical-readiness/device-release-build.log` |
| Original project integrity | All 85 Foliafold baseline files and 6 AERIS source files match; migrated USDZ unchanged | `output/physical-readiness/artifact-integrity.json` |

The UI cases exercise the new paper-revision Setup/Help dismissal path, all ten
Dart actions with help/replay, and everyday help/replay plus independent progress
after relaunch. They do not test a microphone, sensor, physical screen lock or
real sheet. No new iPad acceptance was performed; the earlier Build 5 iPad raster
orientation limitation remains recorded in INTEGRATION_BUILD_5.md.

Both built app bundles identify version 0.1.0/build 6 and contain the exact new
PDF bytes. The signed Debug bundle is at
`output/PhysicalReadinessDeviceDerivedData/Build/Products/Debug-iphoneos/Protacta.app`.
The matching PDF SHA-256 is
`eb9f9135f7abe67d7dc448e97080440384aa72aeef9c0d0759f04ec6b518a012`.

macOS PDFKit rendered that exact bundled PDF at 1680×2376. Native Vision
revision 4 decoded precisely PTC2A/B/C/D; the page measures 210.000003×297.000013
mm, one page. A separate revision-1 attempt decoded zero and remains recorded.
The successful revision-4 result establishes artifact readability and dimensions,
not physical printing or iPhone detection. Script, raster and both attempts are
in `output/physical-readiness/pdf-native-decode/`.

The initial 233-case native run and three UI cases passed before the overlapping
idle-timer defect was identified. After the shared-coordinator repair, all 236
native cases and the same three UI cases passed again. Both attempts remain on
disk. Xcode emitted a post-run optional Simulator-diagnostics `simctl` lookup
warning; the test command exited successfully and the final result bundle reports
three passed, zero failed/skipped tests. No global Xcode selection was changed.

## Native export → independent label → offline report

The browser tool in `tools/validation_annotator/` verifies the exact selected
metadata/PNG pair, hides detector predictions and initially selects no label.
It uses no account, backend, upload or API. JSONL is written only on explicit
download. State-2 original-corner geometry is optional; other states remain
classification-only. Synthetic provenance cannot become human physical evidence.

A native Core Graphics **4×2 synthetic** export from the passing tests was copied
unchanged into `output/physical-readiness/native-contract/samples/sample-01/`.
The first browser import exposed an interoperability bug: native ImageIO writes
upright EXIF. The initial validator rejected all EXIF. It now accepts bounded,
well-formed TIFF with absent/1 orientation, rejects rotated/mirrored/malformed
metadata, and preserves the PNG and SHA. The native pair then imported correctly.

A Playwright browser smoke check explicitly selected `cannotJudge`, no geometry,
and pseudonym `synthetic-ui-smoke`, confirmed and downloaded one JSONL label.
The Python evaluator consumed that exact download and native pair successfully.
All artifacts still declare `synthetic_fixture`; the fixture app build is `test`,
not a physical Build 6 capture. This exercises file compatibility and bookkeeping;
neither the selected label nor its confusion count measures CV accuracy.

Browser screenshot: `output/playwright/annotation-synthetic-export.png`.
Round-trip report: `output/physical-readiness/native-contract/report/`.
The only browser console error was an absent favicon; there was no script error.
The temporary loopback static server served tool assets only and received no
capture upload.

## Shortest remaining acceptance gate

Use `docs/physical-review/README.md` and its blank CSVs. First install the matching
candidate, print the matching PTC2 A4 sheet, and physically follow all ten Dart
actions. Record ambiguities and actual observations before approving teaching
content. Then collect independent correct/wrong/unclear camera examples and
calibrate on development data, keeping evaluation attempts separate. Freeze a
reviewed candidate before the exploratory ten-beginner comparison. The packet
contains no fabricated reviewers, participants, outcomes, times or percentages.

The candidate identity and source hashes are in
`output/physical-readiness/candidate.json`; the local check receipt is
`output/physical-readiness/validation-receipt.json`. These identify preparation,
not successful physical acceptance.
