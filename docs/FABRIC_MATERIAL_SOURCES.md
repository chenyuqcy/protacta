# Everyday fabric materials

Prepared 2026-11-17 for the native everyday lessons. These are scanned fabric
materials, not generated images or a carpet substituted for towel fabric.

## Source and license

All three materials are authored by **colormass (Photography)** and **Rico Cilliers
(Processing)** and distributed by Poly Haven:

| Lesson | Source | Physical tile width × height | Packaged pixel dimensions |
| --- | --- | --- | --- |
| Towel | [Terry Cloth](https://polyhaven.com/a/terry_cloth) | 0.367054 × 0.363200 m | 1024 × 1013 |
| T-shirt | [Cotton Jersey](https://polyhaven.com/a/cotton_jersey) | 0.263603 × 0.263800 m | 1024 × 1025 |
| Bedsheet | [Rough Linen](https://polyhaven.com/a/rough_linen) | 0.270708 × 0.271300 m | 1024 × 1026 |

The towel source has raised, looped fibers. The shirt source is a fine knit.
The bedsheet source is woven linen with crosshatch detail, not a knit reused
from the shirt. It is an authored white linen bedsheet material; it does not
claim to reproduce a particular physical sheet or cotton percale product.
All three contain actual scanned surface variation. The original samples are
blue and beige; the app uses neutral white derivatives requested by the user, not
the original dye colors. Their recorded dimensions come
from the first-party metadata endpoints below. Poly Haven's API schema defines
texture dimensions in **millimeters**, so the values are divided by 1000 for
the meter-based app geometry:

- https://api.polyhaven.com/info/terry_cloth
- https://api.polyhaven.com/info/cotton_jersey
- https://api.polyhaven.com/info/rough_linen
- https://api.polyhaven.com/api-docs/swagger.json

Assets are **CC0 1.0**. Poly Haven explicitly permits commercial use,
modification, and redistribution with a product. Attribution is not required,
but the app includes a credit record for traceability.

- [Poly Haven asset license](https://polyhaven.com/license)
- [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)

The downloaded original metadata, map URLs, and verified MD5 checksums are in
`output/fabric-realism-20261117/sources/`. Output SHA-256 checksums are in
`output/fabric-realism-20261117/prepared-texture-manifest.json`.

## Files bundled with the app

All nine files live in `ios/PaperSteps/Resources/`:

| File | Bytes | Usage |
| --- | ---: | --- |
| `fabric-terry-white-basecolor.jpg` | 430113 | Neutral white towel albedo derivative, sRGB |
| `fabric-terry-normal-gl.png` | 2125266 | OpenGL tangent-space normals, linear data |
| `fabric-terry-roughness.png` | 774533 | Scalar roughness, linear data |
| `fabric-jersey-white-basecolor.jpg` | 133206 | Neutral white cotton albedo derivative, sRGB |
| `fabric-jersey-normal-gl.png` | 1671998 | OpenGL tangent-space normals, linear data |
| `fabric-jersey-roughness.png` | 779337 | Scalar roughness, linear data |
| `fabric-linen-white-basecolor.jpg` | 267006 | Neutral white woven linen albedo derivative, sRGB |
| `fabric-linen-normal-gl.png` | 1940812 | OpenGL tangent-space normals, linear data |
| `fabric-linen-roughness.png` | 898817 | Scalar roughness, linear data |

Total active map files: **9,021,088 bytes (8.60 MiB)**. The additional linen
family is **3,106,635 bytes (2.96 MiB)**. This is disk size, not runtime
GPU residency. Source originals are archived outside the application bundle.
No displacement, metallic, or high-resolution source packs are bundled.

## Reproduction

Use a Python environment with Pillow, for example:

```sh
/Users/adrian/.codex/runtimes/blender-production-suite/.venv/bin/python scripts/prepare_fabric_materials.py
```

Pass `--download` to retrieve the original files again. The script verifies
the source download's byte count and MD5 against first-party metadata before
preparing any app texture.

- Base color: original lossless PNG decoded to RGB, transformed into a neutral
  white variant in linear light, then encoded as sRGB JPEG (quality 94,
  chroma subsampling disabled). This preserves the scanned spatial fiber
  variation. It does not add painted wrinkles or baked shadows.
- Normal: original OpenGL RGB16 PNG converted to RGB8, retaining the channel
  values and orientation. No green-channel inversion or gamma transform.
- Roughness: original 16-bit scalar converted by dividing by 257 into 8-bit
  grayscale. A direct `convert('L')` would incorrectly clip these source maps.
- No resizing, aspect correction, sharpening, or invented detail. Normal and
  roughness maps are unchanged by the neutral-white albedo conversion.

### White albedo transfer function

Each sRGB source channel `s` is decoded to linear light by the standard sRGB
transfer function: `s/12.92` for `s <= 0.04045`, otherwise
`((s + 0.055)/1.055)^2.4`. Source luminance is
`L = 0.2126 R + 0.7152 G + 0.0722 B` using those linear channels.

The derivative reflectance is
`W = clamp(0.72 * (L / mean(L))^0.35, 0.54, 0.86)`.
This is an authored neutral-white color variant, not a measurement of a new
white physical sample. The 0.72 target avoids pure white clipping; the exponent
reduces the strong dye contrast while retaining fine scanned reflectance detail.
`W` is encoded through the inverse sRGB transfer function and written equally
to R, G, and B. The app applies white tint, not a blue, beige, or gray tint.

## Integration requirements

1. Use the tile sizes above when constructing UVs from **unfolded/rest
   positions**. Recomputing UVs from posed world positions will make fibers
   slide over the fabric while it folds. Preserve map alignment across patches.
2. Use white base-color tint with the `*-white-basecolor.jpg` maps. Multiplying
   them by the previous teal/blue palette would reintroduce colored fabrics.
3. Load base color as color/sRGB; normal and roughness as normal/data. Set
   metallic to zero. Preserve the maps' roughness variation rather than using
   the previous uniform 0.94 value.
4. Use wrapping/repeat at the physical tile scale. Do not stretch a complete
   texture once over a 0.9 m towel; that would make the fiber pattern too large.
5. A normal map needs correct UV tangents and a smooth geometric normal field.
   If underside normals differ, preserve tangent handedness; do not globally
   invert the normal map to hide a UV or mesh-winding bug.

Apple's [Creating USD files for Apple devices](https://developer.apple.com/documentation/usd/creating-usd-files-for-apple-devices)
specifies **OpenGL normal maps for RealityKit**, with linear data for normals
and roughness, and sRGB for base color. Its
[WWDC24 asset optimization session](https://developer.apple.com/videos/play/wwdc2024/10186/)
also explains the normal-map convention. Therefore these `normal-gl` files
are not green-channel-flipped. The renderer still needs a visual check on the
actual generated mesh: an upside-down UV basis is a separate problem.

## What these maps do and do not solve

The maps add fabric color variation, small-scale surface lighting, and
roughness. They do not add a rounded fold silhouette, seams, fabric thickness,
gravity, sag, or contact deformation. Those require geometry and animation
changes. A towel should remain visibly thicker than the jersey, while the
shirt should show a finer knit at the same world scale. The bedsheet uses
the linen source's woven structure, not the shirt's knit. Keep physical fiber
size constant when zooming the camera. Avoid extreme normal strength, which
makes the surface look rocky and can shimmer when moving.

Prepared assets and successful checksum verification are not device visual
acceptance. Verify the new materials both in the studio renderer and in AR,
including folded edges, the underside, and camera motion at normal use distance.
