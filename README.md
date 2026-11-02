# Protacta

An iPhone and iPad learning app that demonstrates practical tasks with animated
3D lessons, tabletop AR and hands-free English voice controls.

**Current prototype: 0.1.0 (24)** · iOS / iPadOS 17+ · SwiftUI, SceneKit,
RealityKit, ARKit, Vision, Speech and AVFoundation.

Build 24 is available to the existing external TestFlight group. See the
[release record](docs/TESTFLIGHT_BUILD_24.md) for the verified distribution state.

## Current experience

- **Origami first:** a leading home card, a 3D course library and a ten-action
  Classic Dart practice course with local progress, replay and step-specific help.
- **Tabletop AR:** manually place a virtual reference, then use Adjust / Done to
  move, resize, rotate and lock it. Retry scan preserves the current lesson step.
- **Hands-free practice:** on-device English narration and commands, compact AR
  controls and an optional voice-only fullscreen layout.
- **Everyday skills:** T-shirt, towel, flat bedsheet, square knot and four-in-hand
  tie courses, with animated movements and tabletop AR references.
- **3D equipment:** gearmotor and educational turbofan module animations with
  studio and tabletop AR views; an integrated AERIS concept-product manual.

The current origami AR default, **Hands first**, keeps recognised person pixels
in front of the virtual paper on supported devices. It favours hand visibility
over depth ordering; it does not simulate physical contact. Optional depth modes
remain available. See [origami hand contact](docs/ORIGAMI_CONTACT_BUILD23.md).

## Camera guidance scope

Tabletop AR is a manually placed virtual reference. Its world tracking does not
automatically align a model with a real sheet, garment or machine.

The separate experimental **Guide on my paper** mode supports a flat A4 sheet
and the Classic Dart centre crease. A separate printed **PTC2 revision-2** sheet
supports selected planar cues and outline comparisons during Dart practice.
Uncertain or stale observations hide the cues. These modes do not grade hidden
folds, track arbitrary paper deformation or automatically confirm completed work.
Learners explicitly confirm their own actions.

Camera analysis and available speech recognition run on device. Cloud AI chat
is deferred; the app does not require an API key. Physical paper registration,
hand-edge quality and independent learner outcomes still need real-device review.

## Open and build

Requirements: macOS, Xcode with an iOS 17+ SDK, and Python 3 for the project
generator. The bundled app assets do not require downloading authoring tools.

```sh
python3 scripts/generate_xcode_project.py
open ios/Protacta.xcodeproj
```

Select the **Protacta** scheme and an iPhone or iPad Simulator. For a command-line
Simulator build:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/Protacta.xcodeproj \
  -scheme Protacta \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath output/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

For installation on a physical device, select an authorised signing team in
Xcode and allow camera, microphone and speech permissions when requested.
Real AR, paper alignment and voice behaviour require a supported physical device.
Regenerate the project after adding Swift files or bundled resources.

## Verification

Build 24's focused validation passed **32 native tests and six Simulator UI
cases**. The signed archive, device installation and external TestFlight
availability were verified separately. Details are in
[Build 24](docs/ORIGAMI_FIRST_BUILD24.md) and the
[development record](docs/PROGRESS.md).

List available Simulators with `xcrun simctl list devices available`, then run:

```sh
scripts/test_first_fold.sh SIMULATOR_UDID
scripts/test_dart_practice.sh SIMULATOR_UDID logic
scripts/test_dart_practice.sh SIMULATOR_UDID phone
scripts/test_dart_practice.sh SIMULATOR_UDID hub
python3 -m unittest discover -s scripts/tests -p 'test_evaluate_practice_validation.py' -v
node --test tools/validation_annotator/tests/core.test.js
```

`Protacta-StoreKit` uses the local prototype purchase fixture. The ordinary
scheme does not. Debug Simulator camera fixtures are explicitly labelled as
synthetic; passing them does not establish real camera, speech or learning results.

## Repository layout

| Path | Contents |
| --- | --- |
| `ios/PaperSteps/` | App source and bundled assets; historical source-folder name |
| `ios/PaperStepsTests/` | Native logic, geometry, tracking and lifecycle tests |
| `ios/PaperStepsUITests/` | Simulator navigation and interaction checks |
| `ios/Protacta.xcodeproj/` | Generated Xcode project and shared schemes |
| `scripts/` | Project generation, validation and offline asset tools |
| `tools/` | Local annotation and demo-video tools |
| `docs/` | Plans, release notes, scope and validation records |

Build products, signing credentials, local environment files and device/test
receipts in `output/` are excluded from Git. Historical documents describe the
builds named in them; use the Build 24 notes for the current prototype.

## Provenance and assets

This isolated project was derived from Foliafold 1.0.1 Build 11. The original
checkout remains unchanged; [baseline hashes](docs/FOLIAFOLD_BASELINE.json) record
the source snapshot. Prototype bundle identifier:
`org.realitycore.protacta.prototype`.

Bundled third-party models retain their
[source and licence notices](ios/PaperSteps/Resources/ThirdPartyModelNotices.txt):
the Innerscene gearmotor is CC0 and the turbofan source is MIT. The engine is an
educational interpretation, not manufacturer CAD or an approved repair procedure.
Source and conversion records are in [model sources](docs/assets/model_sources.json).
