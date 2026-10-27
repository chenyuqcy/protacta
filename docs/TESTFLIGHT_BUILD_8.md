# Protacta TestFlight — Build 8

Date: 27 October 2026 (Asia/Qatar).

App Store Connect app: **Protacta**, ID `6827601181`.
Bundle: `org.realitycore.protacta.prototype`; developer team: `67P96Z83PX`.
Version: `0.1.0 (8)`; iOS/iPadOS 17 or later.

Public invitation: **https://testflight.apple.com/join/wa2yVmvs**.

At the end of this run the build is **Waiting for Review**. The link is created
and enabled for up to 100 testers, but App Store Connect explicitly says testers
cannot join until the group has an approved build. Do not announce it as
installable yet. Automatic notification/release to this group is enabled after
approval; no external testers were added or emailed during this run.

The independent app record and explicit Bundle ID were created for this project.
Build 8 retains the prototype's current functionality; only its build number was
advanced from 7. The original Foliafold and AERIS projects were not edited.

## Build and upload evidence

Under ignored `output/testflight-2026-10-27/`:

- `archive.log`: Release archive succeeded with Xcode 26.6, generic iOS device.
- `archive-receipt.json`: correct identity/version, strict signature verification,
  bundled privacy manifest, and no local StoreKit test fixture.
- `export.log` and `export-after-login.log`: initial failures, `No Accounts` and
  no distribution provisioning profile. Browser login alone was insufficient.
- After the user completed Xcode sign-in, `export-signed.log` confirms successful
  App Store distribution export. `ipa-receipt.json` verifies Build 8, correct
  bundle/team, `get-task-allow=false`, `beta-reports-active=true`, no provisioned
  device list, no StoreKit fixture, and strict signature verification.
- `upload.log`: upload succeeded; Apple accepted the package for processing.
  Upload acceptance is separate from successful processing, beta approval and
  availability to a tester.

Exported IPA SHA-256:
`ce487ee1fba549a5112d19602e6cd4e58f83926ffc42361aa5417ea56c27f94c`.
Export options explicitly set `testFlightInternalTestingOnly=false` and preserve
the build number so the build can be considered for external beta testing.

## Beta scope and review information

No app login or purchase is needed for the startup hub, Classic Dart, Little Fox,
five everyday illustrated courses and the AERIS concept walkthrough. Camera and
microphone permissions are optional for 3D/illustrated tutorials. Normal camera
processing stays on device. On-device English speech commands are optional.

Paper guidance and visible-outline comparisons remain experimental. Use flat A4
for the first-fold guide and PTC2 revision-2 paper for supported complete-Dart
states. Everyday courses use authored diagrams and manual confirmation; AERIS is
a virtual concept product. Premium purchases and cloud AI are outside this beta.
There is a known unverified AERIS Explore parts interaction from Simulator capture;
guided release/cover/filter interactions worked. No new physical acceptance is
claimed by this upload.

Beta description and review notes describe these limits and navigation paths.
Review contact information was supplied for Apple's review workflow; private
phone/contact details are not retained in this repository document.

## Distribution gates

- [x] Archive and App Store distribution signing.
- [x] Upload accepted by App Store Connect.
- [x] Apple build processing verified; Build 8 became Ready to Submit.
- [x] Complete beta metadata saved and reloaded successfully.
- [x] Internal prerequisite group `Protacta Team` created with manual distribution.
- [x] External group `Protacta Public Beta` created and Build 8 submitted for review.
- [x] Public invitation link created; enabled with a 100-tester cap.
- [ ] External tester installation available after Apple approval.

External group ID: `e982f3b5-c389-427b-b75a-a47ace7da853`.
Build ID: `6eba4206-de23-4340-a5cf-7da1420bf0e0`.
The external group initially contained 0 testers and 1 build. Review status was
independently observed in the group's Builds tab; the public-link tab displayed
the explicit pending-approval warning. Evidence:
`output/testflight-2026-10-27/portal-proof/public-link.png` and `portal-record.json`.
The final Builds-tab screenshot, `portal-proof/build8-waiting-review.png`,
explicitly shows `0.1.0 (8)` as Waiting for Review. A separate public-browser
check showed that the invitation currently does not accept new testers;
`portal-proof/public-landing-pending.png` preserves that state. This is expected
pending approval, rather than an installation success.

No new legal agreement was presented or accepted in this release workflow.
This is a TestFlight beta submission, not an App Store production release.

Do not label the app ready for an external tester until the corresponding Apple
status and public invitation page have been checked.
