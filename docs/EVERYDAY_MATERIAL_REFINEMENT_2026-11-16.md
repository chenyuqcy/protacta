# Everyday model and catalog refinement

## Scope

Next local candidate: **1.0 (34)**, `org.realitycore.protacta.prototype`.
Retain the Build 33 interface, Origami-first order, explicit action confirmations,
draggable timeline, saved progress, and current AR placement/alignment controls.
This round covers Towel, T-shirt, Bed sheet, Square knot, and Necktie.

## Design

Use portraits of the actual authored 3D models for the five catalog cards.
The material colors and matte finish are shared with the live renderer. Render
transparent PNGs offline, so opening the home screen does not create five live
3D renderers. Cloth portraits show a recognizable partly folded state.

Give open cloth surfaces thin, closed edges. Stable undeformed coordinates
identify shared vertices, so a folded layer touching another layer does not
change topology. Thickness scales with the dimensions used by manual cloth
alignment; the existing rope and tie volumes retain their original thickness.
These are teaching models, not physical cloth simulation or object tracking.

## Verification gates

- Validate finite meshes, indices, boundary treatment, closed-volume normals,
  calibrated dimensions, and continuity between actions.
- Run the five-course Simulator playback and labeled AR-layout checks.
- Scrub each cloth action forward and back near its closed endpoint; inspect
  flat, mid-fold, and closed-layer screenshots.
- Inspect all five bundled catalog images and their appearance on the home page.

Live camera occlusion, physical-object registration and semi-transparent AR
layer sorting require a physical device. Simulator fixtures do not certify them.

## Results

**Build 34 compiled and passed 33 tests on the iPhone 17 Pro Max Simulator,
iOS 26.5: 29 geometry tests and 4 UI cases, zero failures or skipped tests.**

The UI cases cover all five courses' playback and labeled AR-layout transitions,
all 13 cloth actions including reverse scrubbing at 97–100%, and home resume with
instruction disclosure. The separate pure-Swift probe passed 1,785 surface
samples and all adjacent-action boundaries. Closed rope/tie surfaces retain
outward winding; calibrated cloth thickness is explicitly tested.

Receipts under `output/material-refinement-20261116/`:

- `Phone.xcresult`, `phone-summary.json`, `phone-test.log`
- `surface-check/README.md`, `surface-check/result.txt`, `surface-check/volumes.txt`
- `build.json`, `assets-check.txt`: all five bundled PNGs decode to the same
  pixels as their source portraits (Xcode optimizes the PNG files on copy).
- `named-screens/`: 52 captured checkpoints, including the catalog, flat cloth,
  mid-fold poses, closed layers, paused progress and labeled AR layout.

The five 800-pixel transparent catalog portraits total **223,972 bytes**.
Regenerate with `scripts/render_everyday_catalog_thumbnails.sh`; its pose and
mesh receipt is `output/catalog-previews/everyday-preview-manifest.json`.

Visual inspection of the catalog and selected flat/mid/closed cloth captures
found no missing panels or new dark tessellation grid on the flat bedsheet.
The folded edges remain schematic, not photorealistic fabric. Fixed whole-course
framing keeps scale stable but makes the final small bedsheet packet occupy too
little of the viewport. A later user-controlled focus option could enlarge the
current movement without moving the camera unexpectedly while scrubbing.

This pass is local only: no physical iPhone installation, TestFlight upload or
App Store change. Build 32 remains the last verified physical-device candidate.

## Next acceptance step

Use a real towel on the iPhone: align the flat reference, inspect a half-fold
from an oblique angle with the see-through guide, then move a hand across the
edge. This checks physical alignment and transparency/occlusion behavior that
the Simulator cannot establish. Observe whether a first-time learner discovers
the instruction disclosure and understands the explicit completion button.
