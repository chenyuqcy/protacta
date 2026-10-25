"""Synthetic fixtures only; these tests do not measure a device or real paper."""

import hashlib
import importlib.util
import json
import math
from pathlib import Path
import struct
import tempfile
import unittest
import uuid
import zlib


SCRIPT = Path(__file__).resolve().parents[1] / "evaluate_practice_validation.py"
SPEC = importlib.util.spec_from_file_location("practice_validation", SCRIPT)
validation = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validation)


def png(width, height, seed, color=0):
    def chunk(name, data):
        return struct.pack(">I", len(data)) + name + data + struct.pack(">I", zlib.crc32(name + data) & 0xffffffff)
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    rows = b"".join(b"\0" + bytes([(seed + row) % 256]) * width * channels for row in range(height))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


class ValidationHarnessTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.samples = self.root / "samples"
        self.samples.mkdir()
        self.labels = self.root / "labels.jsonl"
        self.labels.write_text("")
        self.counter = 0

    def tearDown(self):
        self.temp.cleanup()

    def sample(self, name="one", *, split="evaluation", source="synthetic_fixture", width=200, height=100):
        self.counter += 1
        folder = self.samples / name
        folder.mkdir()
        image = png(width, height, self.counter)
        (folder / "image.png").write_bytes(image)
        identifier = str(uuid.uuid5(uuid.NAMESPACE_DNS, name))
        sample = {
            "schemaVersion": 1, "id": identifier, "source": source, "split": split,
            "tutorialID": "classic-dart", "courseRevision": "SYNTHETIC-COURSE-REVISION",
            "appVersion": "0.1.0", "appBuild": "SYNTHETIC-TEST",
            "sessionID": "session-" + name, "operatorID": "operator-" + name,
            "sheetID": "sheet-" + name, "attemptID": "attempt-" + name,
            "originID": "origin-" + name, "sourceBasename": identifier + ".png",
            "checkpointID": "dart-visible-outline-3-v1", "referenceState": 3,
            "capturedUptime": 100, "processedUptime": 100.02,
            "image": {"width": width, "height": height, "orientation": "raw_top_left",
                      "path": "image.png", "sha256": hashlib.sha256(image).hexdigest()},
            "rawSheetQuadrilateral": {"topLeft": {"x": .1, "y": .1}, "topRight": {"x": .8, "y": .1},
                                      "bottomRight": {"x": .8, "y": .9}, "bottomLeft": {"x": .1, "y": .9}},
            "registrationPoints": [{"id": key, "sheet": {"x": xy[0], "y": xy[1]}}
                                   for key, xy in validation.known_registration_points().items()],
            "result": {"outcome": "visibleMatch", "message": "SYNTHETIC FIXTURE", "support": "visible_outline_only", "timestamp": 100},
            "frameDisposition": "fresh"
        }
        self.write_sample(name, sample)
        return sample

    def write_sample(self, name, sample):
        (self.samples / name / "sample.json").write_text(json.dumps(sample))

    def label(self, sample, *, dx=0, expected="visibleMatch", landmarks=True):
        w, h = sample["image"]["width"], sample["image"]["height"]
        return {"sampleID": sample["id"], "annotationSource": "human" if sample["source"] == "physical_camera" else "synthetic_fixture",
                "annotatorID": "synthetic-test-generator", "checkpointID": sample["checkpointID"],
                "referenceState": sample["referenceState"], "expectedOutcome": expected,
                "landmarks": [{"id": "independent-center", "sheet": {"x": .5, "y": .5},
                               "rawPixel": {"x": .45 * w + dx, "y": .5 * h}}] if landmarks else [],
                "paperWidthReference": {"sheetY": .97, "leftRawPixel": {"x": .1 * w, "y": .876 * h},
                                        "rightRawPixel": {"x": .8 * w, "y": .876 * h}} if landmarks else None}

    def write_labels(self, *labels):
        self.labels.write_text("\n".join(json.dumps(label) for label in labels) + ("\n" if labels else ""))

    def report(self, events=None):
        return validation.evaluate(self.samples, self.labels, events)

    def test_independent_projection_and_error_use_paper_width_not_image_diagonal(self):
        sample = self.sample(width=1000, height=100)
        # The sheet spans 200 px, although the image diagonal exceeds 1000 px.
        sample["rawSheetQuadrilateral"]["topLeft"]["x"] = .2
        sample["rawSheetQuadrilateral"]["bottomLeft"]["x"] = .2
        sample["rawSheetQuadrilateral"]["topRight"]["x"] = .4
        sample["rawSheetQuadrilateral"]["bottomRight"]["x"] = .4
        self.write_sample("one", sample)
        label = self.label(sample)
        label["landmarks"][0]["rawPixel"]["x"] = 310  # predicted center is x=300
        label["paperWidthReference"]["leftRawPixel"]["x"] = 200
        label["paperWidthReference"]["rightRawPixel"]["x"] = 400
        self.write_labels(label)
        report = self.report()
        measurement = report["measurements"][0]
        self.assertAlmostEqual(measurement["points"][0]["errorPx"], 10)
        self.assertAlmostEqual(measurement["geometry"]["median"], .05)
        self.assertNotAlmostEqual(measurement["geometry"]["median"], 10 / math.hypot(1000, 100))
        self.assertFalse(report["physicalAcceptanceEstablished"])

    def test_perspective_map_uses_edge_coordinates_and_independent_interior_points(self):
        sample = self.sample()
        # Independently specified analytic projectivity, not the harness solver.
        def known(u, v):
            divisor = 1 + .2 * u + .1 * v
            return {"x": (.6 * u + .05 * v + .15) / divisor,
                    "y": (.1 * u + .6 * v + .1) / divisor}
        q = [known(0, 0), known(1, 0), known(1, 1), known(0, 1)]
        sample["rawSheetQuadrilateral"] = dict(zip(validation.QUAD_KEYS, q))
        self.write_sample("one", sample)
        label = self.label(sample)
        center, left, right = known(.5, .5), known(0, .97), known(1, .97)
        label["landmarks"][0]["rawPixel"] = {"x": center["x"] * 200, "y": center["y"] * 100}
        label["paperWidthReference"]["leftRawPixel"] = {"x": left["x"] * 200, "y": left["y"] * 100}
        label["paperWidthReference"]["rightRawPixel"] = {"x": right["x"] * 200, "y": right["y"] * 100}
        self.write_labels(label)
        self.assertAlmostEqual(self.report()["measurements"][0]["geometry"]["max"], 0, places=10)

    def test_per_point_and_per_sample_distribution_are_both_reported(self):
        sample = self.sample()
        label = self.label(sample, dx=14)
        label["landmarks"] += [{"id": "another-interior", "sheet": {"x": .25, "y": .5},
                                 "rawPixel": {"x": 55, "y": 50}}]  # predicted x=55: zero error
        self.write_labels(label)
        measurement = self.report()["measurements"][0]
        self.assertEqual(measurement["geometry"]["n"], 2)
        self.assertAlmostEqual(measurement["geometry"]["median"], .05)
        self.assertAlmostEqual(measurement["geometry"]["p95"], .095)
        self.assertAlmostEqual(measurement["geometry"]["max"], .1)

    def test_biased_lower_marker_fit_is_exposed_by_an_independent_upper_point(self):
        sample = self.sample(width=1000, height=1000)
        # SYNTHETIC arithmetic fixture: true image pose x=.2+.6u,y=.15+.7v.
        # Opposite .004 image-y biases at v=.72/.94 fit those marker rows while
        # extrapolating a >3%-paper-width error at the top of the real sheet.
        top_row = .15 + .7 * .72 - .004
        bottom_row = .15 + .7 * .94 + .004
        slope = (bottom_row - top_row) / (.94 - .72)
        intercept = top_row - slope * .72
        sample["rawSheetQuadrilateral"] = {
            "topLeft": {"x": .2, "y": intercept}, "topRight": {"x": .8, "y": intercept},
            "bottomRight": {"x": .8, "y": intercept + slope}, "bottomLeft": {"x": .2, "y": intercept + slope}}
        self.write_sample("one", sample)
        label = self.label(sample)
        label["landmarks"] = [{"id": "independent-upper-midpoint", "sheet": {"x": .5, "y": 0},
                                "rawPixel": {"x": 500, "y": 150}}]
        label["paperWidthReference"] = {"sheetY": .97, "leftRawPixel": {"x": 200, "y": 829},
                                        "rightRawPixel": {"x": 800, "y": 829}}
        self.write_labels(label)
        measurement = self.report()["measurements"][0]
        self.assertGreater(measurement["geometry"]["median"], .03)
        self.assertAlmostEqual(measurement["geometry"]["median"], .050303030303, places=8)

    def test_no_data_and_unlabeled_data_have_null_statistics(self):
        report = self.report()
        self.assertEqual(report["sampleCount"], 0)
        self.assertIsNone(report["source"])
        self.assertIsNone(report["candidate"])
        stats = report["splits"]["evaluation"]["totals"]["pointErrorPaperWidths"]
        self.assertEqual(stats, {"n": 0, "median": None, "p95": None, "max": None})
        self.assertIn("NO DATA", validation.markdown(report))
        self.sample()
        report = self.report()
        self.assertEqual(report["labeledCount"], 0)
        self.assertEqual(len(report["unlabeledSampleIDs"]), 1)

    def test_confusion_distinguishes_false_match_on_error_from_unclear(self):
        labels = []
        for index, expected in enumerate(("needsAdjustment", "cannotJudge", "visibleMatch")):
            sample = self.sample("sample" + str(index))
            labels.append(self.label(sample, expected=expected, landmarks=False))
        self.write_labels(*labels)
        checkpoint = self.report()["splits"]["evaluation"]["checkpoints"]["dart-visible-outline-3-v1"]
        self.assertEqual(checkpoint["falseVisibleMatchOnError"], {"count": 1, "labeledErrorCount": 1})
        self.assertEqual(checkpoint["falseVisibleMatchOnUnclear"], {"count": 1, "labeledUnclearCount": 1})
        self.assertEqual(checkpoint["confusionMatrix"]["visibleMatch"]["visibleMatch"], 1)

    def test_missing_pose_is_counted_in_classification_without_geometry(self):
        sample = self.sample()
        sample["rawSheetQuadrilateral"] = None
        sample["result"]["outcome"] = "cannotJudge"
        self.write_sample("one", sample)
        self.write_labels(self.label(sample, expected="cannotJudge"))
        report = self.report()
        self.assertEqual(report["measurements"][0]["skipReason"], "missing_pose")
        self.assertEqual(report["splits"]["evaluation"]["totals"]["labeledCount"], 1)

    def test_expired_frame_geometry_never_becomes_live_acceptance(self):
        sample = self.sample()
        sample["frameDisposition"] = "expired"
        sample["result"]["outcome"] = "cannotJudge"
        sample["processingMs"] = 15
        sample["frameAgeMs"] = 900
        self.write_sample("one", sample)
        self.write_labels(self.label(sample, expected="cannotJudge"))
        report = self.report()
        self.assertEqual(report["measurements"][0]["geometry"]["n"], 1)
        totals = report["splits"]["evaluation"]["totals"]
        self.assertEqual(totals["frameDispositionCounts"], {"expired": 1})
        self.assertEqual(totals["processingMs"]["median"], 15)
        self.assertEqual(totals["frameAgeMs"]["median"], 900)
        self.assertFalse(report["physicalAcceptanceEstablished"])

    def test_uptime_difference_is_frame_age_not_algorithm_processing(self):
        self.sample()
        totals = self.report()["splits"]["evaluation"]["totals"]
        self.assertEqual(totals["processingMs"]["n"], 0)
        self.assertAlmostEqual(totals["frameAgeMs"]["median"], 20)

    def test_fitting_landmark_id_or_coordinate_cannot_be_used_as_holdout(self):
        sample = self.sample()
        for collide_by_id in (True, False):
            label = self.label(sample)
            if collide_by_id:
                label["landmarks"][0]["id"] = sample["registrationPoints"][0]["id"]
            else:
                label["landmarks"][0]["sheet"] = sample["registrationPoints"][0]["sheet"]
            self.write_labels(label)
            with self.assertRaisesRegex(validation.ValidationError, "used for registration"):
                self.report()

    def test_every_group_identity_and_derived_basename_is_split_disjoint(self):
        first = self.sample("first", split="development")
        second = self.sample("second")
        for key in validation.GROUP_KEYS:
            old = second[key]
            second[key] = first[key]
            self.write_sample("second", second)
            with self.assertRaisesRegex(validation.ValidationError, "split leakage"):
                self.report()
            second[key] = old
        first["sourceBasename"] = "same_original_frame0001.png"
        second["sourceBasename"] = "same_original_frame0002_crop01.png"
        self.write_sample("first", first)
        self.write_sample("second", second)
        with self.assertRaisesRegex(validation.ValidationError, "split leakage"):
            self.report()

    def test_exact_image_copy_cannot_cross_splits_under_new_names(self):
        first = self.sample("first", split="development")
        second = self.sample("second")
        (self.samples / "second" / "image.png").write_bytes((self.samples / "first" / "image.png").read_bytes())
        second["image"]["sha256"] = first["image"]["sha256"]
        self.write_sample("second", second)
        with self.assertRaisesRegex(validation.ValidationError, "_imageSHA"):
            self.report()

    def test_mixed_provenance_duplicate_ids_and_unknown_labels_fail_closed(self):
        first = self.sample("first")
        second = self.sample("second", source="physical_camera")
        with self.assertRaisesRegex(validation.ValidationError, "evaluated separately"):
            self.report()
        second["source"] = "synthetic_fixture"
        second["id"] = first["id"]
        self.write_sample("second", second)
        with self.assertRaisesRegex(validation.ValidationError, "duplicate sample"):
            self.report()
        second["id"] = str(uuid.uuid4())
        self.write_sample("second", second)
        label = self.label(first)
        label["expectedOutcome"] = "correct_fold"
        self.write_labels(label)
        with self.assertRaisesRegex(validation.ValidationError, "unknown value"):
            self.report()

    def test_candidate_versions_are_required_isolated_and_reported(self):
        first = self.sample("first")
        second = self.sample("second")
        report = self.report()
        self.assertEqual(report["candidate"], {key: first[key] for key in ("tutorialID", "courseRevision", "appVersion", "appBuild")})
        self.assertIn("SYNTHETIC-COURSE-REVISION", validation.markdown(report))
        self.assertIn("SYNTHETIC-TEST", validation.markdown(report))
        for key in ("courseRevision", "appVersion", "appBuild"):
            changed = json.loads(json.dumps(second))
            changed[key] = "different-candidate"
            self.write_sample("second", changed)
            with self.assertRaisesRegex(validation.ValidationError, "mixed app/course"):
                self.report()
            changed[key] = ""
            self.write_sample("second", changed)
            with self.assertRaises(validation.ValidationError):
                self.report()
        changed = json.loads(json.dumps(second))
        changed["tutorialID"] = "different-course"
        self.write_sample("second", changed)
        with self.assertRaisesRegex(validation.ValidationError, "tutorialID"):
            self.report()

    def test_staging_metadata_is_rejected_without_requiring_uuid_folder_names(self):
        self.sample("reviewed-session/descriptive-folder".replace("/", "-"))
        self.assertEqual(self.report()["sampleCount"], 1)
        self.sample(".capture-interrupted")
        with self.assertRaisesRegex(validation.ValidationError, "staging metadata"):
            self.report()
        with self.assertRaisesRegex(validation.ValidationError, "staging root"):
            validation.evaluate(self.samples / ".capture-interrupted", self.labels)

    def test_bad_dimensions_nonfinite_and_invalid_quads_are_rejected(self):
        sample = self.sample()
        original = json.loads(json.dumps(sample))
        for key, value in (("width", 0), ("width", 201), ("height", float("nan"))):
            changed = json.loads(json.dumps(original))
            changed["image"][key] = value
            self.write_sample("one", changed)
            with self.assertRaises(validation.ValidationError):
                self.report()
        changed = json.loads(json.dumps(original))
        changed["rawSheetQuadrilateral"]["bottomRight"] = changed["rawSheetQuadrilateral"]["topLeft"]
        self.write_sample("one", changed)
        with self.assertRaisesRegex(validation.ValidationError, "convex"):
            self.report()

    def test_hash_path_future_time_and_expired_success_are_rejected(self):
        original = self.sample()
        changes = (("image", "sha256", "0" * 64), ("image", "path", "../image.png"),
                   ("result", "timestamp", 99), (None, "processingFailure", "fixture failure"),
                   (None, "processedUptime", 99), (None, "frameDisposition", "expired"))
        for container, key, value in changes:
            sample = json.loads(json.dumps(original))
            (sample[container] if container else sample)[key] = value
            self.write_sample("one", sample)
            with self.assertRaises(validation.ValidationError):
                self.report()

    def test_full_png_rejects_truncation_crc_corruption_and_invalid_compressed_data(self):
        sample = self.sample()
        original = (self.samples / "one/image.png").read_bytes()
        crc_corrupt = bytearray(original)
        crc_corrupt[45] ^= 1

        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)

        bad_stream = original[:33] + chunk(b"IDAT", b"not-zlib") + chunk(b"IEND", b"")
        short_scanlines = original[:33] + chunk(b"IDAT", zlib.compress(b"\0\xff")) + chunk(b"IEND", b"")
        for raw in (original[:24], bytes(crc_corrupt), bad_stream, short_scanlines, original + b"trailing"):
            (self.samples / "one/image.png").write_bytes(raw)
            sample["image"]["sha256"] = hashlib.sha256(raw).hexdigest()
            self.write_sample("one", sample)
            with self.assertRaises(validation.ValidationError):
                self.report()

    def test_valid_rgb_and_rgba_pngs_and_root_style_frame_name_are_supported(self):
        sample = self.sample()
        sample["sourceBasename"] = "550e8400-e29b-41d4-a716-446655440000_frame_12345.123456789.png"
        for color in (2, 6):
            raw = png(200, 100, color, color=color)
            (self.samples / "one/image.png").write_bytes(raw)
            sample["image"]["sha256"] = hashlib.sha256(raw).hexdigest()
            self.write_sample("one", sample)
            self.assertEqual(self.report()["sampleCount"], 1)

    def test_timing_contradictions_cannot_hide_slow_or_stale_processing(self):
        original = self.sample()
        for changes in ({"processingMs": 30}, {"frameAgeMs": 10}, {"frameAgeMs": 900},
                        {"processedUptime": 100.4}, {"frameDisposition": "unreported", "frameAgeMs": 900}):
            sample = json.loads(json.dumps(original))
            sample.update(changes)
            self.write_sample("one", sample)
            with self.assertRaises(validation.ValidationError):
                self.report()

    def test_omitting_or_moving_known_fitting_features_cannot_manufacture_holdouts(self):
        original = self.sample()
        for shortened in (True, False):
            sample = json.loads(json.dumps(original))
            if shortened:
                sample["registrationPoints"].pop()
            else:
                sample["registrationPoints"][0]["sheet"]["x"] += .01
            self.write_sample("one", sample)
            with self.assertRaises(validation.ValidationError):
                self.report()

    def test_label_checkpoint_provenance_width_and_duplicate_annotations_are_rejected(self):
        sample = self.sample()
        for field, value in (("referenceState", 4), ("annotationSource", "human"), ("checkpointID", "other")):
            label = self.label(sample)
            label[field] = value
            self.write_labels(label)
            with self.assertRaises(validation.ValidationError):
                self.report()
        label = self.label(sample)
        label["paperWidthReference"]["sheetY"] = .5
        self.write_labels(label)
        with self.assertRaisesRegex(validation.ValidationError, "full|width"):
            self.report()
        label = self.label(sample)
        self.write_labels(label, label)
        with self.assertRaisesRegex(validation.ValidationError, "duplicate human"):
            self.report()

    def test_optional_lifecycle_pairs_are_counted_and_bad_sequences_rejected(self):
        sample = self.sample()
        events_path = self.root / "events.jsonl"
        events = [{"schemaVersion": 1, "id": str(index), "source": sample["source"], "split": sample["split"],
                   "sessionID": sample["sessionID"], "attemptID": sample["attemptID"], "event": event, "timestamp": timestamp}
                  for index, (event, timestamp) in enumerate((("loss_onset", 10), ("cue_hidden", 10.04),
                                                            ("features_visible", 11), ("cue_shown", 11.7)))]
        events_path.write_text("\n".join(json.dumps(event) for event in events))
        lifecycle = self.report(events_path)["lifecycle"]
        self.assertAlmostEqual(lifecycle["lossToHiddenMs"]["median"], 40)
        self.assertAlmostEqual(lifecycle["featuresVisibleToCueShownMs"]["median"], 700)
        events.reverse()
        events_path.write_text("\n".join(json.dumps(event) for event in events))
        with self.assertRaisesRegex(validation.ValidationError, "chronological"):
            self.report(events_path)

    def test_cli_writes_json_and_markdown_without_a_pass_verdict(self):
        output = self.root / "reports"
        self.assertEqual(validation.main(["--samples", str(self.samples), "--labels", str(self.labels), "--output-dir", str(output)]), 0)
        report = json.loads((output / "validation_report.json").read_text())
        self.assertEqual(report["sampleCount"], 0)
        self.assertFalse(report["physicalAcceptanceEstablished"])
        self.assertIn("never declares the MVP passed", (output / "validation_report.md").read_text())


if __name__ == "__main__":
    unittest.main()
