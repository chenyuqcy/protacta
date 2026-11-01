# Build 24 — origami first and team feedback

On 1 November 2026 the user asked for Origami to lead the app, an updated version and presentation changes based on the Capstone WhatsApp discussion. The latest observed requests were to replace the jet-engine image on slide 1 and refresh prototype imagery on slide 7. Earlier team feedback requested fewer entry controls and reported difficulty placing/resizing the tabletop reference. The group also agreed to describe real-time layout as a future enhancement. No WhatsApp message was sent during this work.

## Application changes

- Origami now occupies the leading visual entry. Other courses remain available below it and through the existing filters; the jet engine is a normal later tile. The large hero has a bounded interaction shape so its enlarged image cannot intercept taps on the category filter.
- The placed origami reference has a compact visible Adjust / Done control. Unlocking shows a short gesture hint; locking restores the stable reference. These controls remain outside the clean fullscreen and voice-only layouts.
- A stalled initial scan offers Retry scan, preserving the current course and partial fold. Scan/recovery text distinguishes first placement from recovering an existing anchor. The existing horizontal-plane raycast and paper geometry are unchanged.
- These controls improve discovery and recovery. They do not establish why a teammate's device took a long time to place a reference, prove a placement-time improvement, or turn tabletop placement into automatic paper registration. Build 23's foreground-hand default remains integrated; its physical contact comparison is still pending.

## Verification

Evidence is retained under `output/origami-first-build24-2026-11-01/`.

- `FinalNavigationAndAR.xcresult`: **32 native tests and six Simulator UI cases passed**, zero failures. The UI cases cover the first entry and filters, other model navigation, Adjust / Done and fullscreen separation, clean voice-only layout, complete ten-fold completion/restart, and phone setup/AR entry. No live camera or microphone result is inferred.
- The first home-filter check found a real oversized hero hit region: a category tap reopened Origami. The explicit interaction shape fixed it; the final check retains selected-filter, absent-tile and actual-navigation assertions.
- The final Release archive, App Store distribution export, and strict signatures passed. `build24-retained-receipt.json` pins the retained device app, executable hash and source inputs. `ipa-receipt.json` verifies build 24, distribution entitlements, no provisioned-device list and no local StoreKit fixture.
- Installation and a separate inventory query confirm version 0.1.0, build 24 on the paired iPhone 17 Pro Max, in the final returned installation container. Normal foreground launch succeeded (`launch.json`). This is installation/runtime evidence, not physical placement or hand-edge acceptance.
- `upload.log` records **Upload succeeded** and **Uploaded package is processing** at App Store Connect. External group assignment, beta review and tester availability have not been confirmed; the management webpage remained at a loading/authentication failure. The previous public invitation must not be presented as already distributing Build 24.

## Presentation

The current shared native deck is `Protacta_Prototype`, ID `1_VfDyupV6uBGLcgIEoMqSHT55T4xGR8tqFznkDIv8KQ`. It contains 17 slides. The original full JSON, PDF, rendered slides and edit plan are retained in `output/presentation-visual-update-build24-2026-11-01/`.

The authorised update uses nine new unedited Simulator screenshots of the origami home, actual lesson stages, phone setup, completion and labelled AR/voice-only layout fixtures. Real camera and outcome photos are removed from the presentation. A proposed camera-check mockup remains explicitly planned; team-reported qualitative observations remain separate from current development changes and pending retests. The broken appendix video was removed while retaining the working clickable-prototype link. The team testing-notes tab is now linked from Appendix C.

The native deck update completed at revision `5zzDP_PF-GazxQ` (modified 2026-11-01T17:48:10.725Z). Full readback, all 17 rendered pages and a zero-issue structural check passed; 186 non-target elements and slide ordering are unchanged. All six changed pages (1, 5, 7, 8, 14 and 16) were additionally reviewed by the parent agent. The exported editable `Protacta_Build24_NoPhotos.pptx` passed ZIP integrity and 17-slide XML checks. A checksum-verified copy is in `/Users/adrian/Downloads/Protacta_Build24_NoPhotos.pptx`. Receipts, source backups and final exports remain in the presentation output folder. No WhatsApp reply or coursework submission was made.
