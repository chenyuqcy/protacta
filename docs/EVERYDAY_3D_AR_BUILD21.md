# Build 21 — continuous everyday movements and tabletop AR

Implemented 1 November 2026 for the user's request to give the everyday courses the connected movement and AR experience already available in origami.

| Course | Authored movements | New primary presentation |
| --- | ---: | --- |
| T-shirt | 6 | Hinged body panels, shaped neck and sleeves, successive packet folds |
| Rectangular towel | 3 | Two thirds followed by a half fold |
| Flat bedsheet | 4 | Four cumulative edge-matching folds |
| Square knot | 5 | Blue/orange volumetric cords with spatial crossings |
| Four-in-hand tie | 7 | Wide/narrow ribbons, neck loop, threading and rear keeper |

These are original, authored 3D teaching models. They are not a cloth/contact simulation or a reconstruction of the learner's actual fabric. The existing diagram references remain in Help.

## Playback and practice

- Opening an unfinished course starts the current movement. Explicitly confirming the finished action starts the next movement automatically.
- Adjacent actions share the same endpoint/start pose and mesh topology. The model and camera use a fixed full-course motion envelope rather than resetting or resizing each step.
- Playback uses measured elapsed time, a capped frame delta, four-second normal/eight-second slow movement, pause, seek and replay.
- Play/Pause has its own stable icon. It never turns into a physical-confirmation command while a person is tapping it. The confirmation button is disabled during playback.
- A paused unfinished move resumes before confirmation. Showing a target pose does not itself confirm the action. Completion remains the learner's declaration and persists independently per course.

## AR and voice

- Every course has an AR button and shares the existing tabletop controller: find a surface, Place here, move, resize and rotate the virtual reference.
- One renderer/ARView and the current pose survive studio/AR and fullscreen changes. Tracking loss, inactive state and Help pause motion; unsupported AR keeps the working studio.
- Fullscreen can retain touch controls or use the optional voice-only overlay, with microphone-failure recovery. In hands-free preview, Next step may show subsequent movements without changing the learner's saved confirmations. Return to my practice restores the declared action.
- Camera and supported speech recognition remain on device. The AR reference is placed beside the real object; it does not recognise or automatically align to clothing or knots. No general camera grading is added.
- All everyday courses now appear under the catalog's 3D & AR filter as well as Everyday.

## Validation and device delivery

Results, screenshots, build artifacts and installation receipts are retained under `output/everyday-ar-build21-2026-11-01/`. Latest results per distinct named case: 37 native geometry/playback/render/lifecycle tests and 11 Simulator UI cases passed. Early UI selector/timing failures were corrected; the zero-test tablet run is explicitly not validation. The actual tablet selector with `()` executed one case successfully. Tablet controls fit across rotation, but the studio-backed landscape AR fixture crops the shirt below the viewport; landscape model framing remains an open visual limitation.

Signed Release 0.1.0 (21) passed strict signature verification, installed on iPhone 17 Pro Max and independently queried as Build 21. Foreground launch succeeded. Physical AR appearance and learning acceptance are separate; no TestFlight upload was performed.

The labeled Simulator AR fixture has no live camera. Actual table placement, manipulation, hand-edge quality, on-device frame pacing and English recognition need a real-device check. Independent learner outcomes and knot/fabric instructional review remain open.

## First physical check

Open T-shirt, watch the first movement, pause and replay it, then confirm your own action. Check that the second movement starts automatically. Enter AR, scan a well-lit table, choose Place here and compare the reference beside your shirt. Pause halfway, return to 3D and verify the same pose. Repeat placement briefly for towel, sheet, knot and tie; record the build, course, action and symptom for any defect.
