#!/usr/bin/env python3
"""Prepare small, traceable cloth textures from Poly Haven's CC0 scans.

Requires Pillow. Run with --download to fetch and verify the original 1K maps.
Without --download, the archived source files are used and verified offline.
No generated texture replaces the real scanned fiber pattern.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "output/fabric-realism-20261117/sources"
RESOURCES = ROOT / "ios/PaperSteps/Resources"
ASSETS = {
    "terry_cloth": "fabric-terry",
    "cotton_jersey": "fabric-jersey",
    "rough_linen": "fabric-linen",
}
MAPS = (("Diffuse", "png"), ("nor_gl", "png"), ("Rough", "png"))


def neutral_white_albedo(image):
    """Keep scanned reflectance detail while removing blue/beige dye colour.

    Work in linear light, not sRGB byte values. The material's colour is an
    art-directed white variant, not a claim that the source sample was white.
    """
    image = image.convert("RGB")
    decode = [value / 255 / 12.92 if value / 255 <= 0.04045
              else ((value / 255 + 0.055) / 1.055) ** 2.4 for value in range(256)]
    pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    luminances = [0.2126 * decode[r] + 0.7152 * decode[g] + 0.0722 * decode[b]
                  for r, g, b in pixels]
    mean_luminance = sum(luminances) / len(luminances)
    neutral = bytearray()
    for luminance in luminances:
        # Reduce dye/highlight contrast, retaining the measured local fibers.
        # Clamping is in physical linear reflectance, well below sensor white.
        reflectance = min(0.86, max(0.54, 0.72 * (luminance / mean_luminance) ** 0.35))
        encoded = 12.92 * reflectance if reflectance <= 0.0031308 else 1.055 * reflectance ** (1 / 2.4) - 0.055
        value = min(255, max(0, round(encoded * 255)))
        neutral.extend((value, value, value))
    return Image.frombytes("RGB", image.size, bytes(neutral))


def fetch(url, destination):
    subprocess.run(
        ["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2",
         url, "--output", str(destination)], check=True
    )


def digest(path, algorithm="sha256"):
    return hashlib.new(algorithm, path.read_bytes()).hexdigest()


def prepare(download=False):
    SOURCES.mkdir(parents=True, exist_ok=True)
    RESOURCES.mkdir(parents=True, exist_ok=True)
    output_manifest = []
    download_manifest = []
    for slug, prefix in ASSETS.items():
        for kind in ("info", "files"):
            path = SOURCES / f"{slug}-{kind}.json"
            if download:
                fetch(f"https://api.polyhaven.com/{kind}/{slug}", path)
            if not path.exists():
                raise FileNotFoundError(f"Missing {path}; rerun with --download")
        info = json.loads((SOURCES / f"{slug}-info.json").read_text())
        files = json.loads((SOURCES / f"{slug}-files.json").read_text())
        for map_name, extension in MAPS:
            metadata = files[map_name]["1k"][extension]
            source = SOURCES / metadata["url"].rsplit("/", 1)[-1]
            if download and not source.exists():
                fetch(metadata["url"], source)
            assert source.stat().st_size == metadata["size"], source
            assert digest(source, "md5") == metadata["md5"], source
            download_manifest.append({
                "file": source.name, "bytes": source.stat().st_size,
                "verified_md5": metadata["md5"], "url": metadata["url"]
            })
            image = Image.open(source)
            if map_name == "Diffuse":
                destination = RESOURCES / f"{prefix}-white-basecolor.jpg"
                neutral_white_albedo(image).save(destination, quality=94, subsampling=0, optimize=True)
                conversion = "Lossless source PNG -> linear luminance -> neutral white reflectance (0.72 * relative-luminance^0.35, bounded 0.54...0.86) -> sRGB JPEG q94"
            elif map_name == "nor_gl":
                # Pillow decodes the source RGB16 PNG to RGB8. No colour-space
                # conversion, sharpening, Y inversion, or image flip is applied.
                destination = RESOURCES / f"{prefix}-normal-gl.png"
                image.convert("RGB").save(destination, optimize=True)
                conversion = "RGB16 to RGB8 data; OpenGL +Y retained; no gamma transform"
            else:
                destination = RESOURCES / f"{prefix}-roughness.png"
                if image.mode in ("I;16", "I;16B", "I;16L", "I"):
                    # Direct convert('L') would clip a 16-bit map at 255.
                    image = image.convert("F").point(lambda value: value / 257).convert("L")
                else:
                    image = image.convert("L")
                image.save(destination, optimize=True)
                conversion = "16-bit scalar divided by 257 to L8; linear data, no gamma transform"
            prepared = Image.open(destination)
            output_manifest.append({
                "asset": slug, "file": destination.name,
                "bytes": destination.stat().st_size,
                "pixel_dimensions": list(prepared.size), "mode": prepared.mode,
                "physical_tile_m": [value / 1000 for value in info["dimensions"]],
                "source_url": metadata["url"],
                "source_md5": metadata["md5"],
                "sha256": digest(destination), "conversion": conversion,
                "license": "CC0-1.0", "license_url": "https://polyhaven.com/license"
            })
    (SOURCES / "download-manifest.json").write_text(json.dumps(download_manifest, indent=2) + "\n")
    manifest_path = SOURCES.parent / "prepared-texture-manifest.json"
    manifest_path.write_text(json.dumps(output_manifest, indent=2) + "\n")
    for item in output_manifest:
        print(f"{item['file']}: {item['bytes']:,} bytes, {item['pixel_dimensions']}")
    print(f"Total: {sum(item['bytes'] for item in output_manifest):,} bytes")
    print(manifest_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    prepare(parser.parse_args().download)
