# Everyday fabric realism — 17 November 2026

The user found the towel and T-shirt too similar to paper or rigid sheets.
This pass separates three causes: surface appearance, garment construction,
and the shape of a moving fold. A detailed normal map cannot change a silhouette.

## Implemented surface and construction changes

- Towel uses the scanned **Terry Cloth** material; T-shirt uses **Cotton Jersey**.
  Six packaged 1K maps total 6.55 MiB. See `FABRIC_MATERIAL_SOURCES.md` for
  first-party links, licenses, map conversion and checksums.
- Rest-space UVs use metres. Fabric does not slide over the object when a fold
  animates. Calibrating the physical size changes the number of pattern repeats,
  rather than making the fibres larger.
- RealityKit loads colour as colour, normal as normal data and roughness as
  scalar data. Repeat sampling, mipmaps and anisotropic filtering limit texture
  aliasing at oblique angles. Materials and GPU textures are reused between poses.
- Towel body starts at 2.6 mm thickness, with a 3.2 mm outer binding. T-shirt
  retains its 0.7 mm body, with 1 mm total thickness at its collar, cuffs and hem.
  These are visual-authoring choices, not measurements or simulated compression.
- Details follow actual garment boundaries and the same calibrated deformation
  as their underlying panel. Internal lesson fold divisions are not sewn edges.
- Existing progress dragging, saved learner confirmations, current-step focus,
  and table/physical-object alignment remain separate from material rendering.

## Shape work and honest limits

The first texture-only render was reviewed and still looked like rigid boards.
The live towel lesson now uses a continuous finite-radius surface. Its bend
widens while lifted and settles into a tighter layered fold. The final packet
uses a common bend axis across all layers to avoid pinching between them.
Rest UVs, topology and adjacent-action endpoints remain fixed. The unexpanded
finished centre-surface envelope is 206 × 462 × 24 mm for the default towel;
finite-radius bends intentionally extend beyond the former zero-radius footprint.

The independent strict probe passed 984 surfaces and 3,636,864 triangles across
four calibration scales, three actions and 41 progress values. It checked
nondegenerate triangles and UVs, exact action joins and no cloth below the table.
Mac Release CPU geometry plus shell generation measured 1.81 ms per sampled
frame; this excludes RealityKit uploads and is not a device frame-rate claim.

T-shirt and bedsheet teaching motions remain authored hinges. Truly soft sleeves,
gravity sag and contact wrinkles require another shape/animation pass. Do not
describe these lessons as a cloth physics simulation or automatic object tracking.

Recommended sequence after the material pass:

1. Inspect the new towel on a physical iPhone, especially its underside and the
   final fold of the stacked layers; confirm perceived softness and AR stability.
2. Extend a verified curved-fold approach to the shirt's sleeve and hem moves.
   Keep the fold itself legible; do not add random noise as a substitute for sag.
3. If authored curves cannot provide the desired result, prototype one offline
   cloth-baked action with constant topology, then validate deterministic iOS
   scrubbing and action boundaries before replacing a complete course.

## Verification

Evidence is kept in `output/fabric-realism-20261117/` and
`output/fabric-uv-20261117/`. Local rendering and simulator UI checks are not
physical iPhone AR visual acceptance. The final receipt records the exact build,
tests, installation and remaining visual limitations.
