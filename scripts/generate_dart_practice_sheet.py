#!/usr/bin/env python3
"""Generate a true A4 practice sheet from the same layout bundled in the app.

Requires reportlab. Print at Actual size / 100%, with no fit-to-page or headers.
The PDF contains only four black QR matrices; its quiet zones stay white.
"""
from argparse import ArgumentParser
from pathlib import Path
import json

from reportlab.graphics.barcode import qrencoder
from reportlab.pdfgen import canvas
from reportlab.lib.units import mm

ROOT = Path(__file__).resolve().parents[1]


def generate(layout_path: Path, output_path: Path) -> None:
    layout = json.loads(layout_path.read_text())
    assert layout["schemaVersion"] == 1
    assert layout["layoutID"] == "protacta-dart-a4-ptc2"
    assert layout["layoutRevision"] == 2
    width = layout["sheetSizeMM"]["width"]
    height = layout["sheetSizeMM"]["height"]
    side = layout["codeSideMM"]
    quiet = layout["quietZoneMM"]
    assert (width, height, side, quiet) == (210, 297, 14, 3)
    assert [m["payload"] for m in layout["markers"]] == ["PTC2A", "PTC2B", "PTC2C", "PTC2D"]
    assert [(m["center"]["x"],m["center"]["y"]) for m in layout["markers"]] == [(.30,.72),(.70,.72),(.70,.94),(.30,.94)]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(output_path), pagesize=(width * mm, height * mm), pageCompression=1)
    pdf.setTitle("Protacta Dart practice sheet - PTC2 revision 2 - A4 at 100 percent")
    pdf.setAuthor("Protacta development")
    pdf.setSubject("PTC2 revision 2. Print Actual size / 100%. Four PTC2 codes. 14 mm matrix, 3 mm quiet zone. Obsolete PTC1 sheets are not supported.")
    pdf.setFillColorRGB(1, 1, 1)
    pdf.rect(0, 0, width * mm, height * mm, fill=1, stroke=0)
    for marker in layout["markers"]:
        cx = marker["center"]["x"] * width
        cy = marker["center"]["y"] * height
        assert cx - side / 2 - quiet > 0 and cx + side / 2 + quiet < width
        assert cy - side / 2 - quiet > 0 and cy + side / 2 + quiet < height
        qr = qrencoder.QRCode(version=1, errorCorrectLevel=qrencoder.QRErrorCorrectLevel.M)
        qr.addData(marker["payload"])
        qr.make()
        matrix = qr.modules
        assert len(matrix) == 21 and all(len(row) == 21 for row in matrix)
        module = side / len(matrix)
        left = cx - side / 2
        top = cy - side / 2
        pdf.setFillColorRGB(0, 0, 0)
        for row, modules in enumerate(matrix):
            for column, dark in enumerate(modules):
                if dark:
                    pdf.rect((left + column * module) * mm,
                             (height - top - (row + 1) * module) * mm,
                             module * mm, module * mm, fill=1, stroke=0)
    pdf.showPage()
    pdf.save()
    print(output_path)


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--layout", type=Path, default=ROOT / "ios/PaperSteps/Resources/DartPracticePaper.json")
    parser.add_argument("--output", type=Path, default=ROOT / "output/pdf/Protacta_Dart_Practice_A4.pdf")
    args = parser.parse_args()
    generate(args.layout, args.output)
