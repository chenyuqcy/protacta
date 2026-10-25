"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { deflateSync } = require("node:zlib");
const core = require("../core.js");

function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) {
    value ^= byte;
    for (let bit = 0; bit < 8; bit += 1) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  }
  return (value ^ 0xffffffff) >>> 0;
}

function chunk(type, payload) {
  const body = Buffer.concat([Buffer.from(type), payload]);
  const length = Buffer.alloc(4), crc = Buffer.alloc(4);
  length.writeUInt32BE(payload.length);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

function png(width = 100, height = 80, extra = []) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8; // real, noninterlaced 8-bit grayscale PNG fixture
  const rows = Buffer.alloc((width + 1) * height, 128);
  for (let row = 0; row < height; row += 1) rows[row * (width + 1)] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header),
    ...extra, chunk("IDAT", deflateSync(rows)), chunk("IEND", Buffer.alloc(0))]);
}

// Neutral, numeric-only TIFF emitted by ImageIO for the native synthetic 4x2
// contract export: IFD0 orientation=1 + ExifIFDPointer, then two pixel dimensions.
const nativeUprightExif = () => Buffer.from("4d4d002a000000080002011200030000000100010000876900040000000100000026000000000002a00200040000000100000004a0030004000000010000000200000000", "hex");

function orientationExif(value = 1, little = false, type = 3, quantity = 1) {
  const bytes = Buffer.alloc(26);
  bytes.write(little ? "II" : "MM", 0);
  const short = (n, offset) => little ? bytes.writeUInt16LE(n, offset) : bytes.writeUInt16BE(n, offset);
  const long = (n, offset) => little ? bytes.writeUInt32LE(n, offset) : bytes.writeUInt32BE(n, offset);
  short(42, 2); long(8, 4); short(1, 8);
  short(0x0112, 10); short(type, 12); long(quantity, 14); short(value, 18);
  return bytes;
}

function withExif(payloads, width = 100, height = 80) {
  const f = fixture();
  f.bytes = png(width, height, payloads.map(payload => chunk("eXIf", payload)));
  f.metadata.image.width = width;
  f.metadata.image.height = height;
  f.metadata.image.sha256 = sha(f.bytes);
  return f;
}

function fixture({ source = "synthetic_fixture", state = 2 } = {}) {
  const bytes = png();
  const metadata = {
    schemaVersion: 1, id: "550e8400-e29b-41d4-a716-446655440000", source,
    tutorialID: "classic-dart", courseRevision: "SYNTHETIC-TEST-REVISION", appVersion: "0.1.0", appBuild: "TEST",
    checkpointID: "dart-visible-outline-" + state + "-v1", referenceState: state,
    image: { width: 100, height: 80, orientation: "raw_top_left", path: "image.png", sha256: sha(bytes) },
    result: { outcome: "visibleMatch", message: "DO NOT SHOW THIS PREDICTION", mismatchedPoints: [{ x: 0.2, y: 0.3 }] },
    rawSheetQuadrilateral: { topLeft: { x: 0.1, y: 0.1 } },
    markerQuadrilaterals: { secret: "DO NOT SHOW" }, registrationPoints: [{ id: "DO NOT SHOW" }]
  };
  return { bytes, metadata };
}

function sha(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
async function verify(f) { return core.verifySample(JSON.stringify(f.metadata), f.bytes, async bytes => sha(bytes)); }
const corners = () => ({ topLeft: { x: 10, y: 5 }, topRight: { x: 90, y: 5 },
  bottomRight: { x: 90, y: 75 }, bottomLeft: { x: 10, y: 75 } });
async function annotation(options = {}) {
  const sample = await verify(fixture());
  return core.buildAnnotation({ sample, annotatorID: "reviewer-01", expectedOutcome: "cannotJudge", confirmed: true, ...options });
}

test("verifies exact dimensions/SHA and exposes no detector prediction or pose", async () => {
  const sample = await verify(fixture());
  assert.equal(sample.image.width, 100);
  assert.equal(sample.image.height, 80);
  assert.equal(sample.source, "synthetic_fixture");
  for (const key of ["result", "rawSheetQuadrilateral", "markerQuadrilaterals", "registrationPoints", "mismatchedPoints"]) {
    assert.equal(Object.hasOwn(sample, key), false);
  }
  assert.equal(JSON.stringify(sample).includes("DO NOT SHOW"), false);
  assert.throws(() => { sample.source = "physical_camera"; }, TypeError);
});

test("fails closed on mismatched dimensions or image digest", async () => {
  const dimensions = fixture();
  dimensions.metadata.image.width = 99;
  await assert.rejects(verify(dimensions), /dimensions do not match/);
  const digest = fixture();
  digest.metadata.image.sha256 = "0".repeat(64);
  await assert.rejects(verify(digest), /SHA-256 does not match/);
});

test("rejects truncated PNG, CRC corruption and malformed EXIF", async () => {
  const original = fixture();
  for (const bytes of [original.bytes.subarray(0, 24),
    Buffer.concat([original.bytes, Buffer.from("trailing")]),
    png(100, 80, [chunk("eXIf", Buffer.from("orientation"))])]) {
    const f = fixture();
    f.bytes = bytes;
    f.metadata.image.sha256 = sha(bytes);
    await assert.rejects(verify(f), /PNG|EXIF|orientation/);
  }
  const corrupt = fixture();
  corrupt.bytes[45] ^= 1;
  corrupt.metadata.image.sha256 = sha(corrupt.bytes);
  await assert.rejects(verify(corrupt), /CRC mismatch/);
});

test("accepts exact upright ImageIO EXIF with child IFD without changing PNG bytes or SHA", async () => {
  const f = withExif([nativeUprightExif()], 4, 2);
  const before = Buffer.from(f.bytes);
  const sample = await verify(f);
  assert.equal(sample.image.width, 4);
  assert.equal(sample.image.height, 2);
  assert.equal(sample.image.sha256, sha(before));
  assert.deepEqual(f.bytes, before);
  assert.equal(sample.source, "synthetic_fixture");
});

test("accepts little-endian upright TIFF and a well-formed IFD with no orientation", async () => {
  await verify(withExif([orientationExif(1, true)]));
  const absent = Buffer.from("4d4d002a00000008000000000000", "hex");
  await verify(withExif([absent]));
});

test("rejects every rotated/mirrored or unknown EXIF orientation and unsupported type/count", async () => {
  for (const value of [0, 2, 3, 4, 5, 6, 7, 8, 9]) {
    await assert.rejects(verify(withExif([orientationExif(value)])), /orientation/);
  }
  await assert.rejects(verify(withExif([orientationExif(1, false, 4)])), /orientation/);
  await assert.rejects(verify(withExif([orientationExif(1, false, 3, 2)])), /orientation/);
});

test("rejects duplicate EXIF chunks and duplicate/conflicting orientation across IFDs", async () => {
  await assert.rejects(verify(withExif([orientationExif(), orientationExif()])), /Duplicate/);
  for (const value of [1, 6]) {
    const first = orientationExif();
    first.writeUInt32BE(26, 22);
    const combined = Buffer.concat([first, orientationExif(value).subarray(8)]);
    await assert.rejects(verify(withExif([combined])), /Duplicate/);
  }
  const sameIFD = Buffer.alloc(38);
  orientationExif().copy(sameIFD, 0);
  sameIFD.writeUInt16BE(2, 8);
  orientationExif().subarray(10, 22).copy(sameIFD, 22);
  await assert.rejects(verify(withExif([sameIFD])), /Duplicate/);
});

test("rejects cyclic, overlapping and out-of-bounds EXIF pointer/data graphs", async () => {
  const invalid = [];
  const cycle = nativeUprightExif(); cycle.writeUInt32BE(8, 30); invalid.push(cycle);
  const outside = nativeUprightExif(); outside.writeUInt32BE(65534, 30); invalid.push(outside);
  const overlap = nativeUprightExif(); overlap.writeUInt32BE(10, 30); invalid.push(overlap);
  const longTable = nativeUprightExif(); longTable.writeUInt16BE(256, 38); invalid.push(longTable);
  const dataOutside = nativeUprightExif(); dataOutside.writeUInt16BE(5, 42); dataOutside.writeUInt32BE(65535, 48); invalid.push(dataOutside);
  const unsupported = nativeUprightExif(); unsupported.writeUInt16BE(43, 2); invalid.push(unsupported);
  for (const payload of invalid) await assert.rejects(verify(withExif([payload])), /EXIF/);
});

test("rejects unknown source, malformed IDs, wrong raw orientation and nonfinite metadata", async () => {
  for (const mutate of [m => { m.source = "assume_real"; }, m => { m.id = "not-a-UUID"; },
    m => { m.image.orientation = "portrait"; }, m => { m.image.width = 0; }, m => { m.referenceState = 12; }]) {
    const f = fixture(); mutate(f.metadata);
    await assert.rejects(verify(f));
  }
  const f = fixture();
  const text = JSON.stringify(f.metadata).replace('"referenceState":2', '"referenceState":1e400');
  await assert.rejects(core.verifySample(text, f.bytes), /nonfinite/);
});

test("client coordinates map to raw edge pixels independently of CSS scale and scrolling", () => {
  const rect = { left: -50, top: 100, width: 400, height: 300 };
  assert.deepEqual(core.imagePointFromClient(150, 250, rect, 1600, 1200), { x: 800, y: 600 });
  assert.deepEqual(core.imagePointFromClient(-50, 100, rect, 1600, 1200), { x: 0, y: 0 });
  assert.deepEqual(core.imagePointFromClient(350, 400, rect, 1600, 1200), { x: 1600, y: 1200 });
  assert.equal(core.imagePointFromClient(351, 400, rect, 1600, 1200), null);
  assert.equal(core.imagePointFromClient(0, 0, { ...rect, width: 0 }, 1600, 1200), null);
  // Pixel-center i=.0 has edge coordinate .5; never use width-1 scaling.
  assert.deepEqual(core.imagePointFromClient(0.5, 0.5, { left: 0, top: 0, width: 100, height: 80 }, 100, 80), { x: 0.5, y: 0.5 });
});

test("no annotation can be built without explicit label, pseudonym and confirmation", async () => {
  const sample = await verify(fixture());
  assert.throws(() => core.buildAnnotation({ sample, annotatorID: "reviewer-01", expectedOutcome: "visibleMatch" }), /Explicitly confirm/);
  assert.throws(() => core.buildAnnotation({ sample, annotatorID: "reviewer-01", expectedOutcome: "", confirmed: true }), /Choose a three-way label/);
  assert.throws(() => core.buildAnnotation({ sample, annotatorID: "name@example.com", expectedOutcome: "cannotJudge", confirmed: true }), /pseudonym/);
  assert.throws(() => core.buildAnnotation({ sample: { ...sample }, annotatorID: "reviewer-01", expectedOutcome: "cannotJudge", confirmed: true }), /Verify/);
});

test("classification-only records use exactly the evaluator schema, with no approval flag", async () => {
  const record = await annotation();
  assert.deepEqual(Object.keys(record).sort(), ["sampleID", "annotationSource", "annotatorID", "checkpointID", "referenceState", "expectedOutcome", "landmarks", "paperWidthReference"].sort());
  assert.deepEqual(record.landmarks, []);
  assert.equal(record.paperWidthReference, null);
  assert.equal(record.expectedOutcome, "cannotJudge");
  assert.equal(record.annotationSource, "synthetic_fixture");
  const line = core.toJSONL(record);
  assert.equal(line.endsWith("\n"), true);
  assert.deepEqual(JSON.parse(line), record);
  assert.throws(() => core.toJSONL({ ...record }), /explicitly built/);
});

test("synthetic provenance stays synthetic even with explicit human/automation action", async () => {
  for (const expectedOutcome of core.outcomes) {
    const sample = await verify(fixture());
    const record = core.buildAnnotation({ sample, annotatorID: "human-reviewer", expectedOutcome,
      confirmed: true, annotationSource: "human" });
    assert.equal(record.annotationSource, "synthetic_fixture");
  }
});

test("declared physical source exports human annotation only on an explicit action", async () => {
  // Negative/branch fixture only: no physical capture or human review is claimed.
  const sample = await verify(fixture({ source: "physical_camera" }));
  assert.throws(() => core.buildAnnotation({ sample, annotatorID: "reviewer-01", expectedOutcome: "cannotJudge" }), /Explicitly confirm/);
  const record = core.buildAnnotation({ sample, annotatorID: "reviewer-01", expectedOutcome: "cannotJudge", confirmed: true });
  assert.equal(record.annotationSource, "human");
});

test("four state2 paper clicks preserve semantic identities and give sheetY1 full width", async () => {
  const record = await annotation({ originalCorners: corners(), expectedOutcome: "visibleMatch" });
  assert.equal(record.landmarks.length, 4);
  assert.deepEqual(record.landmarks.map(p => p.sheet), [{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 1, y: 1 }, { x: 0, y: 1 }]);
  assert.deepEqual(record.paperWidthReference, { sheetY: 1, leftRawPixel: { x: 10, y: 75 }, rightRawPixel: { x: 90, y: 75 } });
  const rotated = { topLeft: { x: 90, y: 75 }, topRight: { x: 10, y: 75 },
    bottomRight: { x: 10, y: 5 }, bottomLeft: { x: 90, y: 5 } };
  const rotatedRecord = await annotation({ originalCorners: rotated });
  assert.deepEqual(rotatedRecord.landmarks[0].rawPixel, rotated.topLeft, "Never sort sensor-space corners");
});

test("folded/other states cannot acquire original-paper points", async () => {
  for (const state of [0, 1, 3, 4, 5, 6, 7, 10]) {
    const sample = await verify(fixture({ state }));
    assert.throws(() => core.buildAnnotation({ sample, annotatorID: "reviewer-01", expectedOutcome: "cannotJudge",
      originalCorners: corners(), confirmed: true }), /only for flat reopened state 2/);
    const record = core.buildAnnotation({ sample, annotatorID: "reviewer-01", expectedOutcome: "cannotJudge", confirmed: true });
    assert.deepEqual(record.landmarks, []);
    assert.equal(record.paperWidthReference, null);
  }
});

test("geometry needs four real clicks and rejects crossed, duplicate or outside points", async () => {
  const sample = await verify(fixture());
  const partial = corners(); delete partial.bottomLeft;
  const crossed = corners(); [crossed.topRight, crossed.bottomRight] = [crossed.bottomRight, crossed.topRight];
  const duplicate = corners(); duplicate.topLeft = duplicate.topRight;
  const outside = corners(); outside.topLeft = { x: -1, y: 5 };
  const nonfinite = corners(); nonfinite.topLeft = { x: NaN, y: 5 };
  for (const originalCorners of [partial, crossed, duplicate, outside, nonfinite]) {
    assert.throws(() => core.buildAnnotation({ sample, annotatorID: "reviewer-01", expectedOutcome: "cannotJudge", originalCorners, confirmed: true }));
  }
});
