"""Original equirectangular softbox lighting; uses only the Python standard library."""
import math
import struct
import zlib
from pathlib import Path

width, height = 1024, 512
scanlines = bytearray()
lights = [(.23, .32, .095, .15, (.92, .95, 1)),
          (.72, .34, .14, .10, (1, .91, .80)),
          (.49, .08, .34, .08, (.65, .73, .90))]
for y in range(height):
    scanlines.append(0)
    for x in range(width):
        u, v = x / width, y / height
        rgb = [.095, .105, .12]
        for cx, cy, sx, sy, color in lights:
            dx = min(abs(u - cx), 1 - abs(u - cx))
            weight = math.exp(-((dx / sx) ** 6 + ((v - cy) / sy) ** 6))
            for channel in range(3):
                rgb[channel] += weight * color[channel]
        floor = math.exp(-((v - .70) / .18) ** 2)
        for channel, value in enumerate((.08, .085, .09)):
            scanlines.append(round(min(1, max(0, rgb[channel] + floor * value)) ** (1 / 2.2) * 255))


def chunk(kind, data):
    return (struct.pack('>I', len(data)) + kind + data
            + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff))


png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(bytes(scanlines))) + chunk(b'IEND', b''))
destination = Path(__file__).resolve().parents[1] / 'ios/PaperSteps/Resources/studio-lighting.png'
destination.write_bytes(png)
print(destination)
