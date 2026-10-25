#!/usr/bin/env python3
"""Offline evidence reporting; never a camera validator or an MVP acceptance gate."""

from __future__ import annotations

import argparse
import binascii
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import struct
import sys
import uuid
import zlib
from typing import Any


OUTCOMES = ("visibleMatch", "needsAdjustment", "cannotJudge")
SOURCES = ("physical_camera", "synthetic_fixture")
SPLITS = ("development", "evaluation")
QUAD_KEYS = ("topLeft", "topRight", "bottomRight", "bottomLeft")
GROUP_KEYS = ("sessionID", "operatorID", "sheetID", "attemptID", "originID")
LAYOUT_PATH = Path(__file__).resolve().parents[1] / "ios/PaperSteps/Resources/DartPracticePaper.json"


class ValidationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def number(value: Any, name: str, minimum: float | None = None) -> float:
    require(type(value) in (int, float) and math.isfinite(value), f"{name}: finite number required")
    require(minimum is None or value >= minimum, f"{name}: below minimum")
    return float(value)


def text(obj: dict, key: str) -> str:
    value = obj.get(key)
    require(isinstance(value, str) and bool(value.strip()) and len(value) <= 512, f"{key}: nonempty string required")
    return value


def enum_value(obj: dict, key: str, choices: tuple[str, ...]) -> str:
    value = text(obj, key)
    require(value in choices, f"{key}: unknown value {value!r}")
    return value


def point(value: Any, name: str, width: float = 1, height: float = 1) -> tuple[float, float]:
    require(isinstance(value, dict), f"{name}: point object required")
    x, y = number(value.get("x"), name + ".x"), number(value.get("y"), name + ".y")
    require(0 <= x <= width and 0 <= y <= height, f"{name}: point outside coordinate extent")
    return x, y


def _constant(value: str) -> None:
    raise ValidationError(f"nonfinite JSON number: {value}")


def parse_json(content: str, name: str) -> dict:
    try:
        value = json.loads(content, parse_constant=_constant)
    except (json.JSONDecodeError, UnicodeError) as error:
        raise ValidationError(f"{name}: invalid JSON: {error}") from error
    require(isinstance(value, dict), f"{name}: JSON object required")

    def finite_tree(item: Any) -> None:
        if isinstance(item, float):
            require(math.isfinite(item), f"{name}: nonfinite value")
        elif isinstance(item, dict):
            for child in item.values():
                finite_tree(child)
        elif isinstance(item, list):
            for child in item:
                finite_tree(child)
    finite_tree(value)
    return value


def read_jsonl(path: Path) -> list[dict]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise ValidationError(f"{path}: {error}") from error
    return [parse_json(line, f"{path}:{index}") for index, line in enumerate(lines, 1) if line.strip()]


def derived_stem(basename: str) -> str:
    """A second guard in addition to explicit origin/session/attempt grouping."""
    require(Path(basename).name == basename and basename not in (".", ".."), "sourceBasename must be a basename")
    stem = Path(basename).stem.casefold()
    # Do not strip UUID numeric components. Only explicit derivative suffixes.
    pattern = r"(?:[._-](?:frame|crop|aug|resize|copy|rot|flip)[._-]?\d*)$"
    previous = None
    while stem != previous:
        previous = stem
        stem = re.sub(pattern, "", stem)
    if not re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", stem):
        stem = re.sub(r"[_-]\d{3,}$", "", stem)
    require(bool(stem), "empty original basename")
    return stem


def stats(values: list[float]) -> dict:
    ordered = sorted(values)

    def percentile(p: float) -> float | None:
        if not ordered:
            return None
        position = (len(ordered) - 1) * p
        low, high = math.floor(position), math.ceil(position)
        return ordered[low] + (ordered[high] - ordered[low]) * (position - low)
    return {"n": len(ordered), "median": percentile(0.5), "p95": percentile(0.95), "max": max(ordered) if ordered else None}


def homography(quad: list[tuple[float, float]]) -> list[float]:
    cross = []
    for index in range(4):
        a, b, c = quad[index], quad[(index + 1) % 4], quad[(index + 2) % 4]
        cross.append((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]))
    require(all(v > 1e-10 for v in cross) or all(v < -1e-10 for v in cross), "predicted quad must be strictly convex")
    rows = []
    for (u, v), (x, y) in zip(((0, 0), (1, 0), (1, 1), (0, 1)), quad):
        rows += [[u, v, 1, 0, 0, 0, -x * u, -x * v, x],
                 [0, 0, 0, u, v, 1, -y * u, -y * v, y]]
    for column in range(8):
        pivot = max(range(column, 8), key=lambda row: abs(rows[row][column]))
        require(abs(rows[pivot][column]) > 1e-12, "singular predicted homography")
        rows[column], rows[pivot] = rows[pivot], rows[column]
        divisor = rows[column][column]
        rows[column] = [value / divisor for value in rows[column]]
        for row in range(8):
            if row != column:
                amount = rows[row][column]
                rows[row] = [a - amount * b for a, b in zip(rows[row], rows[column])]
    result = [rows[i][8] for i in range(8)] + [1.0]
    require(all(math.isfinite(v) for v in result), "nonfinite predicted homography")
    for u, v in ((0, 0), (1, 0), (1, 1), (0, 1)):
        require(result[6] * u + result[7] * v + 1 > 1e-10, "projective horizon intersects the sheet")
    return result


def verify_png(raw: bytes, width: int, height: int) -> None:
    """Validate exported noninterlaced 8-bit PNG structure and decoded scanlines."""
    require(raw[:8] == b"\x89PNG\r\n\x1a\n", "capture must be PNG")
    position, header, ended, seen_data, data_closed, seen_palette = 8, None, False, False, False, False
    compressed = []
    while position < len(raw):
        require(position + 12 <= len(raw), "truncated PNG chunk")
        size = struct.unpack(">I", raw[position:position + 4])[0]
        kind = raw[position + 4:position + 8]
        require(bool(re.fullmatch(rb"[A-Za-z]{4}", kind)) and not kind[2] & 32, "invalid PNG chunk type")
        end = position + 12 + size
        require(end <= len(raw), "truncated PNG payload")
        data = raw[position + 8:position + 8 + size]
        crc = struct.unpack(">I", raw[position + 8 + size:end])[0]
        require(binascii.crc32(kind + data) & 0xffffffff == crc, "PNG CRC mismatch")
        require(header is not None or kind == b"IHDR", "PNG must start with IHDR")
        if kind == b"IHDR":
            require(header is None and size == 13, "invalid or repeated PNG IHDR")
            header = struct.unpack(">IIBBBBB", data)
            w, h, depth, color, compression, filtering, interlace = header
            require((w, h) == (width, height), "PNG dimensions disagree with metadata")
            require(depth == 8 and color in (0, 2, 4, 6) and compression == 0 and filtering == 0 and interlace == 0,
                    "only noninterlaced 8-bit grayscale/RGB/gray-alpha/RGBA export PNGs are supported")
        elif kind == b"IDAT":
            require(not data_closed, "PNG IDAT chunks must be consecutive")
            seen_data = True
            compressed.append(data)
        elif kind == b"IEND":
            require(size == 0 and seen_data and end == len(raw), "invalid PNG IEND/trailing data")
            ended = True
            position = end
            break
        else:
            if seen_data:
                data_closed = True
            require(kind[0] & 32 or kind == b"PLTE", "unsupported critical PNG chunk")
            if kind == b"PLTE":
                require(not seen_palette and not seen_data and header[3] in (2, 6) and
                        0 < size <= 768 and size % 3 == 0, "invalid PNG palette")
                seen_palette = True
        position = end
    require(ended and header is not None and position == len(raw), "PNG lacks complete IEND")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[header[3]]
    row_size = width * channels + 1
    expected = row_size * height
    require(expected <= 64 * 1024 * 1024, "PNG decoded data exceeds 64 MiB limit")
    try:
        decoder = zlib.decompressobj()
        scanlines = decoder.decompress(b"".join(compressed), expected + 1)
    except zlib.error as error:
        raise ValidationError("corrupt PNG compressed stream") from error
    require(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail and len(scanlines) == expected,
            "PNG decompressed size/stream mismatch")
    require(all(scanlines[row * row_size] <= 4 for row in range(height)), "invalid PNG scanline filter")


def known_registration_points() -> dict[str, tuple[float, float]]:
    try:
        layout = parse_json(LAYOUT_PATH.read_text(encoding="utf-8"), str(LAYOUT_PATH))
        width, height = layout["sheetSizeMM"]["width"], layout["sheetSizeMM"]["height"]
        half_x, half_y = layout["codeSideMM"] / width / 2, layout["codeSideMM"] / height / 2
        result = {}
        for marker in layout["markers"]:
            x, y = marker["center"]["x"], marker["center"]["y"]
            result[marker["payload"] + ".center"] = (x, y)
            for suffix, dx, dy in (("topLeft", -half_x, -half_y), ("topRight", half_x, -half_y),
                                   ("bottomRight", half_x, half_y), ("bottomLeft", -half_x, half_y)):
                result[marker["payload"] + "." + suffix] = (x + dx, y + dy)
    except (OSError, KeyError, TypeError, ZeroDivisionError) as error:
        raise ValidationError(f"cannot load pinned printed registration layout: {error}") from error
    require(layout.get("schemaVersion") == 1 and len(result) == 20, "unsupported printed registration layout")
    return result


def project(matrix: list[float], xy: tuple[float, float]) -> tuple[float, float]:
    u, v = xy
    denominator = matrix[6] * u + matrix[7] * v + 1
    require(denominator > 1e-10, "invalid landmark projection")
    return ((matrix[0] * u + matrix[1] * v + matrix[2]) / denominator,
            (matrix[3] * u + matrix[4] * v + matrix[5]) / denominator)


def load_sample(path: Path) -> dict:
    try:
        sample = parse_json(path.read_text(encoding="utf-8"), str(path))
    except (OSError, UnicodeError) as error:
        raise ValidationError(f"{path}: {error}") from error
    require(sample.get("schemaVersion") == 1 and type(sample.get("schemaVersion")) is int, "unsupported sample schemaVersion")
    for key in ("id", "checkpointID", *GROUP_KEYS, "sourceBasename"):
        text(sample, key)
    require(sample.get("tutorialID") == "classic-dart", "tutorialID must be classic-dart")
    for key in ("courseRevision", "appVersion", "appBuild"):
        value = text(sample, key)
        require(len(value.encode("utf-8")) <= 160 and "\n" not in value and "\r" not in value,
                f"{key}: bounded single-line candidate metadata required")
    for key in GROUP_KEYS:
        limit = 80
        require(len(sample[key]) <= limit and bool(re.fullmatch(r"[A-Za-z0-9_.-]+", sample[key])), f"{key}: safe pseudonymous ID required")
    require(len(sample["sourceBasename"]) <= 164 and
            bool(re.fullmatch(r"[A-Za-z0-9_.-]+\.png", sample["sourceBasename"])) and
            sample["sourceBasename"].casefold() != "image.png", "sourceBasename must be a canonical original PNG name, not image.png")
    try:
        canonical_id = str(uuid.UUID(sample["id"]))
    except ValueError as error:
        raise ValidationError("sample id must be a UUID") from error
    require(canonical_id == sample["id"].lower(), "sample id must use canonical UUID form")
    sample["_stem"] = derived_stem(sample["sourceBasename"])
    enum_value(sample, "source", SOURCES)
    enum_value(sample, "split", SPLITS)
    state = sample.get("referenceState")
    require(type(state) is int and 0 <= state <= 10, "referenceState must be an integer 0...10")
    captured = number(sample.get("capturedUptime"), "capturedUptime", 0)
    processed = number(sample.get("processedUptime"), "processedUptime", 0)
    require(processed >= captured, "processedUptime precedes capturedUptime")
    for key in ("processingMs", "frameAgeMs"):
        if key in sample and sample[key] is not None:
            number(sample[key], key, 0)
    sample["_frameAgeMs"] = sample.get("frameAgeMs")
    if sample["_frameAgeMs"] is None:
        sample["_frameAgeMs"] = (processed - captured) * 1000
    disposition = sample.get("frameDisposition", "unreported")
    require(disposition in ("fresh", "expired", "unreported"), "unknown frameDisposition")
    sample["_disposition"] = disposition
    elapsed_ms = (processed - captured) * 1000
    require(sample.get("processingMs") is None or sample["processingMs"] <= elapsed_ms + 0.001,
            "processingMs exceeds capture-to-processing elapsed time")
    require(sample["_frameAgeMs"] >= elapsed_ms - 0.001, "frameAgeMs is shorter than capture-to-processing elapsed time")
    require(disposition != "fresh" or max(elapsed_ms, sample["_frameAgeMs"]) <= 350 + 0.001,
            "fresh frame exceeds 350 ms observation lifetime")
    result = sample.get("result")
    require(isinstance(result, dict), "result object required")
    outcome = enum_value(result, "outcome", OUTCOMES)
    text(result, "message")
    require(number(result.get("timestamp"), "result.timestamp", 0) == captured, "result timestamp does not match captured frame")
    require(result.get("support") == "visible_outline_only", "result support must be visible_outline_only")
    require(disposition != "expired" or outcome == "cannotJudge", "expired frame must have cannotJudge outcome")
    require(max(elapsed_ms, sample["_frameAgeMs"]) <= 350 + 0.001 or outcome == "cannotJudge",
            "stale/unreported frame must have cannotJudge outcome")
    require(state in (0, 2, 3, 4, 5, 6) or outcome == "cannotJudge", "unsupported outline state must have cannotJudge outcome")
    if sample.get("processingFailure") is not None:
        text(sample, "processingFailure")
        require(outcome == "cannotJudge", "processing failure must have cannotJudge outcome")
    image = sample.get("image")
    require(isinstance(image, dict) and image.get("orientation") == "raw_top_left", "raw_top_left image required")
    width, height = image.get("width"), image.get("height")
    require(type(width) is int and type(height) is int and 1 <= width <= 16384 and 1 <= height <= 16384, "invalid image dimensions")
    relative = Path(text(image, "path"))
    require(not relative.is_absolute() and ".." not in relative.parts, "image path must stay inside sample folder")
    image_path = (path.parent / relative).resolve()
    require(image_path.is_relative_to(path.parent.resolve()), "image path escapes sample folder")
    digest = text(image, "sha256")
    require(bool(re.fullmatch(r"[0-9a-fA-F]{64}", digest)), "image sha256 must be 64 hex characters")
    try:
        require(image_path.stat().st_size <= 64 * 1024 * 1024, "PNG file exceeds 64 MiB limit")
        raw = image_path.read_bytes()
    except OSError as error:
        raise ValidationError(f"missing capture image: {error}") from error
    require(hashlib.sha256(raw).hexdigest() == digest.lower(), "capture image SHA-256 mismatch")
    sample["_imageSHA"] = digest.lower()
    verify_png(raw, width, height)
    require("rawSheetQuadrilateral" in sample, "rawSheetQuadrilateral is required (null when unavailable)")
    quad = sample["rawSheetQuadrilateral"]
    if quad is None:
        require(outcome == "cannotJudge", "missing pose must have cannotJudge outcome")
        sample["_matrix"] = None
    else:
        require(isinstance(quad, dict), "rawSheetQuadrilateral must be an object or null")
        sample["_matrix"] = homography([point(quad.get(key), "quad." + key) for key in QUAD_KEYS])
    features = sample.get("registrationPoints")
    require(isinstance(features, list), "registrationPoints list required")
    require(quad is None or len(features) >= 4, "pose needs declared fitting points")
    identifiers = set()
    for feature in features:
        require(isinstance(feature, dict), "invalid fitting point")
        identifier = text(feature, "id")
        require(identifier not in identifiers, "duplicate fitting point ID")
        identifiers.add(identifier)
        point(feature.get("sheet"), "registrationPoints.sheet")
    known_points = known_registration_points()
    require(identifiers == set(known_points), "all 20 known fitting QR centers/corners must be declared")
    require(all(math.dist(point(feature["sheet"], "fitting point"), known_points[feature["id"]]) <= 1e-9 for feature in features),
            "fitting points do not match the pinned printed layout")
    return sample


def load_labels(path: Path, samples: dict[str, dict]) -> dict[str, dict]:
    labels = {}
    for label in read_jsonl(path):
        identifier = text(label, "sampleID")
        require(identifier not in labels, "duplicate human label sampleID")
        require(identifier in samples, f"label refers to unknown sample {identifier}")
        sample = samples[identifier]
        expected_source = "human" if sample["source"] == "physical_camera" else "synthetic_fixture"
        require(label.get("annotationSource") == expected_source, "annotationSource does not match sample provenance")
        text(label, "annotatorID")
        require(label.get("checkpointID") == sample["checkpointID"] and
                type(label.get("referenceState")) is int and label["referenceState"] == sample["referenceState"], "label checkpoint/referenceState mismatch")
        enum_value(label, "expectedOutcome", OUTCOMES)
        landmarks = label.get("landmarks")
        require(isinstance(landmarks, list), "landmarks list required")
        require("paperWidthReference" in label, "paperWidthReference required (null when unscored)")
        identifiers = set()
        fitting_ids = {item["id"] for item in sample["registrationPoints"]}
        fitting_xy = [point(item["sheet"], "fitting sheet") for item in sample["registrationPoints"]]
        seen_xy = set()
        for landmark in landmarks:
            require(isinstance(landmark, dict), "invalid landmark")
            name = text(landmark, "id")
            xy = point(landmark.get("sheet"), "landmark.sheet")
            require(name not in identifiers and xy not in seen_xy, "duplicate holdout landmark")
            require(name not in fitting_ids and all(math.dist(xy, fit) > 1e-6 for fit in fitting_xy), "holdout landmark was used for registration")
            point(landmark.get("rawPixel"), "landmark.rawPixel", sample["image"]["width"], sample["image"]["height"])
            identifiers.add(name)
            seen_xy.add(xy)
        reference = label.get("paperWidthReference")
        require(not landmarks or isinstance(reference, dict), "landmarks need an independent full-paper width reference")
        if reference is not None:
            require(isinstance(reference, dict), "invalid paperWidthReference")
            require(sample["referenceState"] in (0, 2, 3, 4, 5, 6), "full-width normalization only supports the declared planar Dart states")
            y = number(reference.get("sheetY"), "paperWidthReference.sheetY")
            require(0.95 <= y <= 1, "paper width must span original-sheet x=0...1 near the unchanged bottom edge, sheetY 0.95...1")
            left = point(reference.get("leftRawPixel"), "width.left", sample["image"]["width"], sample["image"]["height"])
            right = point(reference.get("rightRawPixel"), "width.right", sample["image"]["width"], sample["image"]["height"])
            require(math.dist(left, right) >= 1, "paper-width reference is degenerate")
        labels[identifier] = label
    return labels


def reject_leakage(samples: list[dict]) -> None:
    groups: dict[tuple[str, str], str] = {}
    for sample in samples:
        for key in (*GROUP_KEYS, "_stem", "_imageSHA"):
            group = (key, sample[key].casefold())
            require(group not in groups or groups[group] == sample["split"], f"split leakage through {key}={sample[key]!r}")
            groups[group] = sample["split"]


def geometry(sample: dict, label: dict) -> dict:
    matrix = sample["_matrix"]
    errors, points = [], []
    if matrix is not None and label["landmarks"]:
        reference = label["paperWidthReference"]
        width_px = math.dist(point(reference["leftRawPixel"], "width", sample["image"]["width"], sample["image"]["height"]),
                             point(reference["rightRawPixel"], "width", sample["image"]["width"], sample["image"]["height"]))
        for landmark in label["landmarks"]:
            normalized = project(matrix, point(landmark["sheet"], "landmark"))
            predicted = (normalized[0] * sample["image"]["width"], normalized[1] * sample["image"]["height"])
            observed = point(landmark["rawPixel"], "observed", sample["image"]["width"], sample["image"]["height"])
            pixel_error = math.dist(predicted, observed)
            relative_error = pixel_error / width_px
            errors.append(relative_error)
            points.append({"id": landmark["id"], "predictedRawPixel": list(predicted), "humanRawPixel": list(observed),
                           "errorPx": pixel_error, "paperWidthPx": width_px, "errorPaperWidths": relative_error})
    return {"sampleID": sample["id"], "checkpointID": sample["checkpointID"], "split": sample["split"],
            "frameDisposition": sample["_disposition"], "geometry": stats(errors), "points": points,
            "skipReason": "missing_pose" if matrix is None else ("no_holdout_landmarks" if not errors else None)}


def checkpoint_report(samples: list[dict], labels: dict, measurements: dict) -> dict:
    matrix = {actual: {predicted: 0 for predicted in OUTCOMES} for actual in OUTCOMES}
    errors, sample_medians = [], []
    labeled = 0
    for sample in samples:
        if sample["id"] not in labels:
            continue
        labeled += 1
        matrix[labels[sample["id"]]["expectedOutcome"]][sample["result"]["outcome"]] += 1
        measurement = measurements[sample["id"]]
        errors += [item["errorPaperWidths"] for item in measurement["points"]]
        if measurement["geometry"]["median"] is not None:
            sample_medians.append(measurement["geometry"]["median"])
    return {"sampleCount": len(samples), "labeledCount": labeled, "confusionMatrix": matrix,
            "falseVisibleMatchOnError": {"count": matrix["needsAdjustment"]["visibleMatch"], "labeledErrorCount": sum(matrix["needsAdjustment"].values())},
            "falseVisibleMatchOnUnclear": {"count": matrix["cannotJudge"]["visibleMatch"], "labeledUnclearCount": sum(matrix["cannotJudge"].values())},
            "pointErrorPaperWidths": stats(errors), "sampleMedianErrorPaperWidths": stats(sample_medians),
            "processingMs": stats([sample["processingMs"] for sample in samples if sample.get("processingMs") is not None]),
            "frameAgeMs": stats([sample["_frameAgeMs"] for sample in samples]),
            "frameDispositionCounts": dict(Counter(sample["_disposition"] for sample in samples))}


def lifecycle_report(path: Path | None, samples: dict[str, dict]) -> dict:
    delays, recoveries, ids, timelines = [], [], set(), defaultdict(list)
    if path is not None:
        known = {(s["sessionID"], s["attemptID"]): (s["source"], s["split"]) for s in samples.values()}
        for event in read_jsonl(path):
            require(type(event.get("schemaVersion")) is int and event["schemaVersion"] == 1, "unsupported event schema")
            identifier = text(event, "id")
            require(identifier not in ids, "duplicate lifecycle event ID")
            ids.add(identifier)
            key = (text(event, "sessionID"), text(event, "attemptID"))
            require(key in known and (event.get("source"), event.get("split")) == known[key], "event provenance/session mismatch")
            enum_value(event, "event", ("loss_onset", "cue_hidden", "features_visible", "cue_shown"))
            number(event.get("timestamp"), "event.timestamp", 0)
            require(not timelines[key] or event["timestamp"] >= timelines[key][-1]["timestamp"], "events must be chronological within each attempt")
            timelines[key].append(event)
    unpaired_loss, unpaired_recovery, shown_while_lost = 0, 0, 0
    for events in timelines.values():
        loss, visible, lost = None, None, False
        for event in events:
            name, timestamp = event["event"], event["timestamp"]
            if name == "loss_onset":
                require(loss is None, "overlapping unpaired loss events")
                loss, lost = timestamp, True
            elif name == "cue_hidden" and loss is not None:
                delays.append((timestamp - loss) * 1000)
                loss = None
            elif name == "features_visible":
                require(visible is None, "overlapping recovery events")
                visible, lost = timestamp, False
            elif name == "cue_shown":
                if lost:
                    shown_while_lost += 1
                if visible is not None:
                    recoveries.append((timestamp - visible) * 1000)
                    visible = None
        unpaired_loss += loss is not None
        unpaired_recovery += visible is not None
    return {"eventCount": len(ids), "lossToHiddenMs": stats(delays), "featuresVisibleToCueShownMs": stats(recoveries),
            "cueShownWhileAnnotatedLostCount": shown_while_lost,
            "unpairedLossCount": unpaired_loss, "unpairedRecoveryCount": unpaired_recovery}


def evaluate(samples_dir: Path, labels_path: Path, events_path: Path | None = None) -> dict:
    require(samples_dir.is_dir(), "--samples must be a directory of exported sample folders")
    require(not samples_dir.name.startswith(".capture-"), "unfinished .capture-* staging root is not evidence")
    sample_paths = sorted(samples_dir.rglob("*.json"))
    for path in sample_paths:
        require(not any(part.startswith(".capture-") for part in path.relative_to(samples_dir).parts),
                f"unfinished .capture-* staging metadata is not evidence: {path}")
    samples = [load_sample(path) for path in sample_paths]
    by_id = {}
    for sample in samples:
        require(sample["id"] not in by_id, "duplicate sample ID")
        by_id[sample["id"]] = sample
    sources = {sample["source"] for sample in samples}
    require(len(sources) <= 1, "physical and synthetic samples must be evaluated separately")
    candidate_keys = ("tutorialID", "courseRevision", "appVersion", "appBuild")
    candidates = {tuple(sample[key] for key in candidate_keys) for sample in samples}
    require(len(candidates) <= 1, "mixed app/course candidates must be evaluated separately")
    candidate = dict(zip(candidate_keys, next(iter(candidates)))) if candidates else None
    reject_leakage(samples)
    labels = load_labels(labels_path, by_id)
    measurements = {sample["id"]: geometry(sample, labels[sample["id"]]) for sample in samples if sample["id"] in labels}
    split_reports = {}
    for split in SPLITS:
        subset = [sample for sample in samples if sample["split"] == split]
        checkpoints = sorted({sample["checkpointID"] for sample in subset})
        split_reports[split] = {"sampleCount": len(subset),
                               "checkpoints": {checkpoint: checkpoint_report([sample for sample in subset if sample["checkpointID"] == checkpoint], labels, measurements) for checkpoint in checkpoints},
                               "totals": checkpoint_report(subset, labels, measurements)}
    return {"reportSchemaVersion": 1, "generatedAtUTC": datetime.now(timezone.utc).isoformat(),
            "source": next(iter(sources), None), "candidate": candidate,
            "sampleCount": len(samples), "labeledCount": len(labels),
            "unlabeledSampleIDs": sorted(set(by_id) - set(labels)), "splits": split_reports,
            "measurements": list(measurements.values()), "lifecycle": lifecycle_report(events_path, by_id),
            "physicalAcceptanceEstablished": False,
            "limitations": ["This offline report never declares the MVP passed.",
                            "Image-point error describes the captured raw frame, not live-cue stability or task correctness.",
                            "Expired frames are not accepted live alignment; fresh/unreported disposition is not acceptance either.",
                            "Synthetic fixtures cannot establish device latency, physical accuracy or learner performance.",
                            "Width reference and holdout landmarks are declared independent annotations; their physical accuracy still needs human review."]}


def markdown(report: dict) -> str:
    def value(item: float | None) -> str:
        return "n/a" if item is None else f"{item:.6g}"
    candidate = report["candidate"]
    candidate_line = (f"Candidate: tutorial `{candidate['tutorialID']}`; course revision `{candidate['courseRevision']}`; "
                      f"app `{candidate['appVersion']}` build `{candidate['appBuild']}`.") if candidate else "Candidate: unavailable (no data)."
    lines = ["# Offline practice validation report", "", f"Source: **{report['source'] or 'NO DATA'}**", candidate_line,
             f"Samples: {report['sampleCount']}; labeled: {report['labeledCount']}; unlabeled: {len(report['unlabeledSampleIDs'])}.",
             "", "**Physical acceptance is not established. This report never declares the MVP passed.**", "",
             "Errors below are fractions of independently annotated full paper width in the raw image, not image diagonal.", "",
             "| Split / checkpoint | Labels | Holdout points | Median | p95 | Max | False match on error | False match on unclear |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for split, data in report["splits"].items():
        for checkpoint, item in {"ALL": data["totals"], **data["checkpoints"]}.items():
            error = item["pointErrorPaperWidths"]
            wrong, unclear = item["falseVisibleMatchOnError"], item["falseVisibleMatchOnUnclear"]
            lines.append(f"| {split} / {checkpoint} | {item['labeledCount']} | {error['n']} | {value(error['median'])} | {value(error['p95'])} | {value(error['max'])} | {wrong['count']} / {wrong['labeledErrorCount']} | {unclear['count']} / {unclear['labeledUnclearCount']} |")
    lines += ["", "No percentages are invented for empty denominators. JSON includes every point, per-sample median/p95/max, confusion matrices and timing counts.", "",
              "## Timing and frame disposition", "", "| Split | Processing n / median ms | Frame age n / median ms | Dispositions |", "| --- | --- | --- | --- |"]
    for split, data in report["splits"].items():
        item = data["totals"]
        lines.append(f"| {split} | {item['processingMs']['n']} / {value(item['processingMs']['median'])} | {item['frameAgeMs']['n']} / {value(item['frameAgeMs']['median'])} | {item['frameDispositionCounts']} |")
    lifecycle = report["lifecycle"]
    lines += ["", f"Lifecycle events: {lifecycle['eventCount']}; loss-to-hide pairs: {lifecycle['lossToHiddenMs']['n']}; recovery pairs: {lifecycle['featuresVisibleToCueShownMs']['n']}.",
              "", "## Limits", ""] + ["- " + limitation for limitation in report["limitations"]]
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=Path, required=True)
    parser.add_argument("--labels", type=Path, required=True)
    parser.add_argument("--events", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        report = evaluate(args.samples, args.labels, args.events)
    except (ValidationError, OSError) as error:
        print(f"Validation input rejected: {error}", file=sys.stderr)
        return 2
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "validation_report.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    (args.output_dir / "validation_report.md").write_text(markdown(report), encoding="utf-8")
    print(f"Wrote offline report for {report['sampleCount']} samples ({report['source'] or 'no data'}); no acceptance conclusion.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
