# Explicit local camera-validation capture

This is developer test tooling for the physical acceptance gate. It is not a
record of device installation, collected real data or successful folding. Normal
practice does not record camera photos. The entry is hidden in Release builds.

## Record on a real device

1. Connect and unlock an iPhone/iPad. Open `ios/Protacta.xcodeproj`, select the
   Debug `Protacta` scheme and a real device. Configure its development signing
   as needed; an unsigned generic build is not an installed app.
2. Add the launch argument `--practice-validation`. Remove `--ui-testing` and
   `--paper-guide-fixture`; those arguments prohibit physical-source recording.
3. From the normal hub choose **Paper & craft** → **Classic Dart** →
   **Practice the complete Dart**. Use the matching PTC2 revision-2 sheet for
   Build 6 and later; Build 5/PTC1 is a different candidate. In the printer/setup panel
   choose **Configure local validation samples**. Enter anonymous operator,
   physical-sheet and whole-attempt IDs and choose development or evaluation.
   Do not use a person's name, phone identifier or email.
4. Return to the camera and frame the current action. Press **Save local test
   sample** only when you want a full camera image stored locally. The next
   admitted frame is tied to its own analysis, step, timestamp and viewport;
   capture never advances the course or invents a human label.
5. A save creates `Documents/ProtactaValidation/<sample UUID>/image.png` and
   `sample.json`. The record includes the exact PNG hash, raw image dimensions,
   semantic paper quad, declared fitting points, current comparison and measured
   processing/frame age. A slow result may be saved for diagnosis, but is marked
   expired and cannot have a visible-match approval.

Only one export can run at once. Changing action, resizing/rotating the camera,
backgrounding or losing tracking cancels an outstanding capture. Images are not
uploaded or shared automatically. Simulator fixtures are refused as physical
camera evidence; synthetic unit exports retain a distinct source declaration.

Capture correct, visibly wrong and unclear examples, not only successful
alignments. A missing pose can still contribute an explicit cannot-judge example.
Keep entity IDs consistent: reusing a paper, operator, attempt, session or source
frame in both splits is detected as leakage, even under a new sample UUID.

## Copy the records to the Mac

The following uses the locally verified `devicectl device copy from` interface.
The transfer itself remains unverified until a real device is connected. Use a
fresh destination and replace `YOUR_CONNECTED_DEVICE_ID` with the paired ID:

```sh
mkdir -p output/physical-validation/session-001
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device copy from \
  --device YOUR_CONNECTED_DEVICE_ID \
  --domain-type appDataContainer \
  --domain-identifier org.realitycore.protacta.prototype \
  --source Documents/ProtactaValidation \
  --destination output/physical-validation/session-001/captures
```

## Annotate independently, then report

Use [VALIDATION_DATA_FORMAT.md](VALIDATION_DATA_FORMAT.md) for a separate human
JSONL annotation file and the evaluator command. Raw PNG coordinates have their
origin at the top-left of the sensor image. A displayed portrait camera crop is
not the raw image; its transform is stored separately in the metadata.

Include clearly identifiable upper-sheet/nose landmarks as well as other
independent points. Four codes near the lower end can fit locally while their
homography extrapolates poorly at the top. Code centers/corners used by the
fitter or its consistency check are excluded from held-out accuracy evidence.
Normalize errors by an independently annotated full paper-width segment on the
same lower reference plane, not by the camera image diagonal.

The offline tool verifies record/PNG integrity, split separation, three-way
comparison results, independent point error and timing. It does not certify that
source declarations or annotations are truthful, turn synthetic data into real
evidence, or issue an MVP-pass decision. Physical tutorial review and beginner
trials in PHYSICAL_VALIDATION.md remain separate gates.
