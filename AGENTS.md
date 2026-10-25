# Protacta native app

- This is the isolated startup development project derived from Foliafold 1.0.1 Build 11. Keep `/Users/adrian/Desktop/QCRI/origami_ar_demo` unchanged.
- Use `ios/Protacta.xcodeproj` and the `Protacta` scheme after running `python3 scripts/generate_xcode_project.py`. Source folders retain the historical PaperSteps name. New Swift/resource files require regeneration.
- English UI and voice commands; iOS/iPadOS 17 minimum. Camera and speech stay on device.
- Keep studio, tabletop-model placement, and real-paper guidance as separate modes. World tracking does not establish paper registration. Animation progress does not certify a real fold.
- The first real-paper milestone supports a flat A4 sheet and the Classic Dart center crease. It does not grade folds or track arbitrary deformation. Hide uncertain/stale cues and require a usable view before resuming guidance.
- The complete Dart practice prototype uses a separate learner-confirmed ten-action session. Printed-paper Plan B uses four PTC2 revision-2 QR codes on the sheet itself, white paper on a dark mat, planar cues before actions 1 and 3-7, and experimental visible-outline checks after actions 2-6. Build 6 and later reject obsolete PTC1 codes; update app and printed sheet together. Preserve coded corner identity; never relabel it using screen sorting. Folded/lifted/hidden states use 3D/manual comparison. These checks remain uncalibrated until physical review and independent samples.
- Preserve a Git baseline and record code tests, simulator UI checks, and physical-device acceptance separately. Never label synthetic frames as real-device evidence.
- Bundle and purchase identifiers use the prototype namespace. This project is not an App Store release; retain original Foliafold receipts only as historical source evidence.
