/* Local data-only helpers. No network, storage, inference or detector rendering. */
(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.ValidationAnnotatorCore = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const outcomes = Object.freeze(["visibleMatch", "needsAdjustment", "cannotJudge"]);
  const cornerNames = Object.freeze(["topLeft", "topRight", "bottomRight", "bottomLeft"]);
  const sourceCoordinates = Object.freeze([[0, 0], [1, 0], [1, 1], [0, 1]]);
  const verifiedSamples = new WeakSet();
  const builtAnnotations = new WeakSet();

  function requireValue(condition, message) {
    if (!condition) throw new Error(message);
  }

  function finite(value) {
    return typeof value === "number" && Number.isFinite(value);
  }

  function boundedText(value, name, limit) {
    requireValue(typeof value === "string" && value.trim().length > 0 &&
      value.length <= limit && !/[\r\n]/.test(value), name + " must be a nonempty single-line value.");
    return value;
  }

  function finiteTree(value) {
    if (typeof value === "number") requireValue(Number.isFinite(value), "Metadata contains a nonfinite number.");
    else if (Array.isArray(value)) value.forEach(finiteTree);
    else if (value && typeof value === "object") Object.values(value).forEach(finiteTree);
  }

  function crc32(bytes, start, end) {
    let crc = 0xffffffff;
    for (let index = start; index < end; index += 1) {
      crc ^= bytes[index];
      for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    return (crc ^ 0xffffffff) >>> 0;
  }

  function inspectExif(bytes) {
    // PNG eXIf contains a TIFF header directly, not a JPEG Exif wrapper. Native
    // ImageIO emits a small IFD0 plus an Exif child IFD even for an upright PNG.
    requireValue(bytes.length >= 14 && bytes.length <= 65536, "Unsupported EXIF size.");
    const little = bytes[0] === 0x49 && bytes[1] === 0x49;
    requireValue(little || (bytes[0] === 0x4d && bytes[1] === 0x4d), "Invalid EXIF TIFF byte order.");
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const uint16 = offset => view.getUint16(offset, little);
    const uint32 = offset => view.getUint32(offset, little);
    requireValue(uint16(2) === 42, "Unsupported EXIF TIFF format.");
    const sizes = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8, 4];
    const pending = [uint32(4)];
    const visited = new Set();
    const ranges = [];
    let entries = 0;
    let orientationSeen = false;
    while (pending.length) {
      const offset = pending.shift();
      requireValue(offset >= 8 && offset % 2 === 0 && offset + 2 <= bytes.length,
        "EXIF IFD offset is out of bounds.");
      requireValue(!visited.has(offset) && visited.size < 16, "Duplicate, cyclic or excessive EXIF IFDs.");
      visited.add(offset);
      const count = uint16(offset);
      const end = offset + 2 + count * 12 + 4;
      requireValue(count <= 256 && entries + count <= 512 && end <= bytes.length, "EXIF IFD table is out of bounds.");
      requireValue(ranges.every(range => end <= range[0] || offset >= range[1]), "Overlapping EXIF IFD tables.");
      ranges.push([offset, end]);
      entries += count;
      const tags = new Set();
      for (let index = 0; index < count; index += 1) {
        const entry = offset + 2 + index * 12;
        const tag = uint16(entry), type = uint16(entry + 2), quantity = uint32(entry + 4);
        requireValue(!tags.has(tag), "Duplicate EXIF tag.");
        tags.add(tag);
        requireValue(type > 0 && type < sizes.length && quantity > 0, "Unsupported EXIF field type or count.");
        const size = sizes[type] * quantity;
        requireValue(size <= bytes.length, "EXIF field length is out of bounds.");
        const data = size <= 4 ? entry + 8 : uint32(entry + 8);
        requireValue(data >= 8 && data + size <= bytes.length, "EXIF field data is out of bounds.");
        if (tag === 0x0112) {
          requireValue(!orientationSeen && type === 3 && quantity === 1,
            "Duplicate or unsupported EXIF orientation metadata.");
          orientationSeen = true;
          requireValue(uint16(data) === 1, "Rotated or mirrored EXIF orientation is not supported; use the exact upright raw export.");
        }
        const singleIFD = tag === 0x8769 || tag === 0x8825 || tag === 0xa005;
        const subIFDs = tag === 0x014a;
        if (singleIFD || subIFDs) {
          requireValue((type === 4 || (subIFDs && type === 13)) &&
            (singleIFD ? quantity === 1 : quantity <= 16), "Unsupported EXIF IFD pointer.");
          for (let item = 0; item < quantity; item += 1) pending.push(uint32(data + item * 4));
        } else {
          requireValue(type !== 13, "Unsupported EXIF IFD pointer tag.");
        }
      }
      const next = uint32(end - 4);
      if (next !== 0) pending.push(next);
    }
    return orientationSeen ? 1 : null;
  }

  function inspectPNG(bytes) {
    requireValue(bytes instanceof Uint8Array && bytes.length >= 33 && bytes.length <= 64 * 1024 * 1024,
      "Select a PNG file no larger than 64 MiB.");
    requireValue([137, 80, 78, 71, 13, 10, 26, 10].every((byte, index) => bytes[index] === byte),
      "The selected image is not a PNG.");
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let position = 8;
    let dimensions = null;
    let sawData = false;
    let dataClosed = false;
    let sawEnd = false;
    let sawExif = false;
    while (position < bytes.length) {
      requireValue(position + 12 <= bytes.length, "The PNG is truncated.");
      const length = view.getUint32(position);
      const end = position + length + 12;
      requireValue(end <= bytes.length, "The PNG has a truncated chunk.");
      const type = String.fromCharCode(...bytes.subarray(position + 4, position + 8));
      requireValue(/^[A-Za-z]{4}$/.test(type), "The PNG has an invalid chunk type.");
      requireValue(crc32(bytes, position + 4, position + 8 + length) === view.getUint32(position + 8 + length),
        "The PNG has a CRC mismatch.");
      requireValue(dimensions !== null || type === "IHDR", "The PNG must begin with IHDR.");
      if (type === "IHDR") {
        requireValue(dimensions === null && length === 13, "The PNG has an invalid IHDR.");
        const width = view.getUint32(position + 8);
        const height = view.getUint32(position + 12);
        requireValue(width > 0 && height > 0 && width <= 16384 && height <= 16384 && width * height <= 16777216,
          "PNG dimensions exceed this local annotator's safe preview size (16 megapixels).");
        requireValue(bytes[position + 16] === 8 && [0, 2, 4, 6].includes(bytes[position + 17]) &&
          bytes[position + 18] === 0 && bytes[position + 19] === 0 && bytes[position + 20] === 0,
          "Use a noninterlaced 8-bit grayscale or RGB/RGBA export PNG.");
        dimensions = { width, height };
      } else if (type === "IDAT") {
        requireValue(!dataClosed, "PNG IDAT chunks must be consecutive.");
        sawData = true;
      } else if (type === "IEND") {
        requireValue(length === 0 && sawData && end === bytes.length, "The PNG has an invalid IEND or trailing data.");
        sawEnd = true;
        position = end;
        break;
      } else {
        if (sawData) dataClosed = true;
        if (type === "eXIf") {
          requireValue(!sawExif, "Duplicate PNG EXIF orientation metadata.");
          sawExif = true;
          inspectExif(bytes.subarray(position + 8, position + 8 + length));
        }
        requireValue(type[0] === type[0].toLowerCase() || type === "PLTE", "Unsupported critical PNG chunk.");
      }
      position = end;
    }
    requireValue(sawEnd && dimensions !== null, "The PNG is incomplete.");
    return dimensions;
  }

  async function defaultDigest(bytes) {
    requireValue(typeof globalThis.crypto?.subtle?.digest === "function",
      "SHA-256 is unavailable. Open this local page in a browser with Web Crypto support.");
    const hash = await globalThis.crypto.subtle.digest("SHA-256", bytes);
    return Array.from(new Uint8Array(hash), value => value.toString(16).padStart(2, "0")).join("");
  }

  async function verifySample(metadataText, pngBytes, digestFunction = defaultDigest) {
    requireValue(typeof metadataText === "string" && metadataText.length <= 1024 * 1024,
      "Select a sample.json no larger than 1 MiB.");
    let metadata;
    try { metadata = JSON.parse(metadataText); }
    catch (_) { throw new Error("The metadata is not valid JSON."); }
    requireValue(metadata && typeof metadata === "object" && !Array.isArray(metadata), "Metadata must be an object.");
    finiteTree(metadata);
    requireValue(metadata.schemaVersion === 1 && metadata.tutorialID === "classic-dart", "Expected Classic Dart sample schema 1.");
    requireValue(typeof metadata.id === "string" && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(metadata.id),
      "The sample ID must be a UUID.");
    requireValue(["physical_camera", "synthetic_fixture"].includes(metadata.source), "Unknown sample source; no label can be exported.");
    requireValue(Number.isInteger(metadata.referenceState) && metadata.referenceState >= 0 && metadata.referenceState <= 10,
      "The reference state must be an integer from 0 to 10.");
    ["checkpointID", "courseRevision", "appVersion", "appBuild"].forEach(key => boundedText(metadata[key], key, 512));
    const image = metadata.image;
    requireValue(image && image.orientation === "raw_top_left" && image.path === "image.png",
      "Metadata must refer to image.png in raw_top_left orientation.");
    requireValue(Number.isInteger(image.width) && Number.isInteger(image.height), "Metadata image dimensions must be integers.");
    requireValue(typeof image.sha256 === "string" && /^[0-9a-f]{64}$/i.test(image.sha256), "Missing or invalid image SHA-256.");
    const dimensions = inspectPNG(pngBytes);
    requireValue(dimensions.width === image.width && dimensions.height === image.height,
      "PNG dimensions do not match sample.json. Select the matching original image.");
    const digest = await digestFunction(pngBytes);
    requireValue(typeof digest === "string" && digest.toLowerCase() === image.sha256.toLowerCase(),
      "PNG SHA-256 does not match sample.json. Select the matching original image.");
    // Only this allowlist reaches the UI. Detector output, pose, fit points and
    // mismatch hints are intentionally not returned or shown during annotation.
    const sample = Object.freeze({
      id: metadata.id, source: metadata.source, tutorialID: metadata.tutorialID,
      checkpointID: metadata.checkpointID, referenceState: metadata.referenceState,
      courseRevision: metadata.courseRevision, appVersion: metadata.appVersion, appBuild: metadata.appBuild,
      paperLayoutID: typeof metadata.paperLayoutID === "string" ? metadata.paperLayoutID : null,
      paperLayoutRevision: Number.isInteger(metadata.paperLayoutRevision) ? metadata.paperLayoutRevision : null,
      image: Object.freeze({ width: image.width, height: image.height, sha256: image.sha256.toLowerCase(), orientation: "raw_top_left" })
    });
    verifiedSamples.add(sample);
    return sample;
  }

  function imagePointFromClient(clientX, clientY, rect, imageWidth, imageHeight) {
    if (![clientX, clientY, rect?.left, rect?.top, rect?.width, rect?.height, imageWidth, imageHeight].every(finite) ||
      rect.width <= 0 || rect.height <= 0 || imageWidth <= 0 || imageHeight <= 0) return null;
    const x = (clientX - rect.left) / rect.width;
    const y = (clientY - rect.top) / rect.height;
    if (x < 0 || y < 0 || x > 1 || y > 1) return null;
    // Edge-based coordinates: center of pixel (i,j) is (i+.5,j+.5).
    return Object.freeze({ x: x * imageWidth, y: y * imageHeight });
  }

  function originalCornerPoints(corners, sample) {
    requireValue(sample.referenceState === 2, "Original-corner geometry is enabled only for flat reopened state 2.");
    requireValue(corners && typeof corners === "object" && !Array.isArray(corners) &&
      Object.keys(corners).length === 4 && cornerNames.every(name => Object.hasOwn(corners, name)),
      "Click all four ORIGINAL paper corners explicitly, or turn geometry off.");
    const points = cornerNames.map(name => {
      const p = corners[name];
      requireValue(p && finite(p.x) && finite(p.y) && p.x >= 0 && p.y >= 0 &&
        p.x <= sample.image.width && p.y <= sample.image.height, "A corner lies outside the raw image.");
      return Object.freeze({ x: p.x, y: p.y });
    });
    let sign = 0;
    for (let index = 0; index < 4; index += 1) {
      const a = points[index], b = points[(index + 1) % 4], c = points[(index + 2) % 4];
      requireValue(Math.hypot(b.x - a.x, b.y - a.y) >= 1, "Two paper corners are indistinguishable.");
      const cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      requireValue(Math.abs(cross) > 0.000001 && (index === 0 || cross * sign > 0),
        "Corner order is crossed or collapsed. Use paper TL, TR, BR, BL; do not sort image corners.");
      if (index === 0) sign = cross;
    }
    return points;
  }

  function buildAnnotation({ sample, annotatorID, expectedOutcome, originalCorners = null, confirmed = false }) {
    requireValue(verifiedSamples.has(sample), "Verify the local sample and image before annotating.");
    requireValue(confirmed === true, "Explicitly confirm your own annotation before exporting.");
    requireValue(typeof annotatorID === "string" && /^[A-Za-z0-9_.-]{1,80}$/.test(annotatorID) &&
      annotatorID !== "." && annotatorID !== "..", "Enter a short annotator pseudonym, not a name or email.");
    requireValue(outcomes.includes(expectedOutcome), "Choose a three-way label; no label is selected by default.");
    const points = originalCorners === null ? null : originalCornerPoints(originalCorners, sample);
    const landmarks = points ? points.map((p, index) => Object.freeze({
      id: "original-paper." + cornerNames[index],
      sheet: Object.freeze({ x: sourceCoordinates[index][0], y: sourceCoordinates[index][1] }), rawPixel: p
    })) : [];
    const annotation = Object.freeze({
      sampleID: sample.id,
      annotationSource: sample.source === "synthetic_fixture" ? "synthetic_fixture" : "human",
      annotatorID, checkpointID: sample.checkpointID, referenceState: sample.referenceState,
      expectedOutcome, landmarks: Object.freeze(landmarks),
      paperWidthReference: points ? Object.freeze({ sheetY: 1, leftRawPixel: points[3], rightRawPixel: points[2] }) : null
    });
    builtAnnotations.add(annotation);
    return annotation;
  }

  function toJSONL(annotation) {
    requireValue(builtAnnotations.has(annotation), "Export only an explicitly built annotation.");
    return JSON.stringify(annotation) + "\n";
  }

  return Object.freeze({ outcomes, cornerNames, inspectPNG, verifySample, imagePointFromClient, buildAnnotation, toJSONL });
});
