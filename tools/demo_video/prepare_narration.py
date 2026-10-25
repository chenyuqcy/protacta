#!/usr/bin/env python3
"""Assemble timed narration without changing the speed of generated utterances.

The source voice manifest owns every absolute start time. This tool resamples
each source to 48 kHz stereo PCM, inserts silence, and normalizes the assembled
track in two passes. It never normalizes individual clips or truncates speech.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import subprocess
import wave

RATE = 48000
CHANNELS = 2
WIDTH = 2
TARGET = {"I": -16, "TP": -1.5, "LRA": 7}


def number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be a finite number")
    result = float(value)
    if not math.isfinite(result):
        raise ValueError(f"{label} must be finite")
    return result


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def resolve(path: str, base: Path) -> Path:
    result = Path(path).expanduser()
    return (base / result).resolve() if not result.is_absolute() else result.resolve()


def safe_id(value: object, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise ValueError(f"{label} must contain only letters, numbers, underscores or hyphens")
    return value


def command(args: list[str], log: Path) -> str:
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, check=False)
    log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); inspect {log}")
    return result.stdout


def loudness_json(output: str) -> dict:
    # loudnorm emits a JSON object after the ordinary ffmpeg progress log.
    matches = list(re.finditer(r'\{\s*"input_i"\s*:', output))
    if not matches:
        raise RuntimeError("ffmpeg did not return loudnorm measurements")
    value, _ = json.JSONDecoder().raw_decode(output[matches[-1].start():])
    for key in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset"):
        if key not in value or not math.isfinite(float(value[key])):
            raise ValueError(f"Invalid loudness measurement: {key}")
    return value


def read_pcm(path: Path) -> tuple[bytes, int]:
    with wave.open(str(path), "rb") as stream:
        if (stream.getnchannels(), stream.getsampwidth(), stream.getframerate()) != (CHANNELS, WIDTH, RATE):
            raise ValueError(f"Expected stereo 48 kHz 16-bit PCM: {path}")
        if stream.getcomptype() != "NONE":
            raise ValueError(f"Compressed WAV is not supported: {path}")
        frames = stream.getnframes()
        data = stream.readframes(frames)
    if len(data) != frames * CHANNELS * WIDTH:
        raise ValueError(f"Truncated PCM source: {path}")
    return data, frames


def write_pcm(path: Path, data: bytes) -> None:
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(CHANNELS)
        stream.setsampwidth(WIDTH)
        stream.setframerate(RATE)
        stream.writeframes(data)


def validated_plan(manifest: dict, base: Path) -> list[dict]:
    videos = manifest.get("videos")
    clips = manifest.get("clips")
    if not isinstance(videos, list) or not videos or not isinstance(clips, list) or not clips:
        raise ValueError("Manifest requires nonempty videos and clips lists")
    plans: dict[str, dict] = {}
    for video in videos:
        vid = safe_id(video.get("id"), "video.id")
        duration = number(video.get("duration"), f"{vid}.duration")
        source = resolve(video["source"], base)
        if vid in plans or duration <= 0 or not source.is_file():
            raise ValueError(f"Duplicate video, invalid duration or missing source: {vid}")
        plans[vid] = dict(video, id=vid, source=str(source), duration=duration,
                          frames=round(duration * RATE), clips=[])
    seen: set[str] = set()
    for clip in clips:
        cid = safe_id(clip.get("id"), "clip.id")
        vid = clip.get("videoID")
        if cid in seen or vid not in plans:
            raise ValueError(f"Duplicate clip or unknown video: {cid}")
        seen.add(cid)
        values = {key: number(clip.get(key), f"{cid}.{key}") for key in
                  ("slotStart", "slotEnd", "audioStart", "audioEnd", "duration", "sampleRate", "speed")}
        a, b = values["audioStart"], values["audioEnd"]
        slot_a, slot_b = values["slotStart"], values["slotEnd"]
        tolerance = max(2 / RATE, 2 / values["sampleRate"]) if values["sampleRate"] > 0 else 0
        if values["sampleRate"] <= 0 or values["speed"] <= 0 or values["duration"] <= 0:
            raise ValueError(f"Invalid sample rate, generation speed or clip duration: {cid}")
        if not (0 <= slot_a < slot_b <= plans[vid]["duration"] + 1 / RATE):
            raise ValueError(f"Clip slot is outside video duration: {cid}")
        if a < slot_a or b > slot_b + tolerance or b <= a:
            raise ValueError(f"Narration does not fit its picture window: {cid}")
        if abs(b - a - values["duration"]) > tolerance:
            raise ValueError(f"audioEnd disagrees with unmodified utterance duration: {cid}")
        source = resolve(clip["file"], base)
        if not source.is_file():
            raise ValueError(f"Missing utterance: {source}")
        plans[vid]["clips"].append(dict(clip, **values, id=cid, source=str(source),
                                          startFrame=round(a * RATE)))
    for plan in plans.values():
        if not plan["clips"]:
            raise ValueError(f"No narration for video {plan['id']}")
        plan["clips"].sort(key=lambda clip: clip["audioStart"])
        previous_end = 0.0
        for clip in plan["clips"]:
            if clip["audioStart"] < previous_end - 1 / RATE:
                raise ValueError(f"Narration overlaps a previous utterance: {clip['id']}")
            previous_end = clip["audioEnd"]
    return list(plans.values())


def assemble(plan: dict, folder: Path, ffmpeg: str) -> dict:
    folder.mkdir()
    intermediate = folder / "resampled_utterances"
    intermediate.mkdir()
    timeline = bytearray(plan["frames"] * CHANNELS * WIDTH)
    intervals = []
    previous_end = 0
    for clip in plan["clips"]:
        converted = intermediate / f"{clip['id']}.wav"
        command([ffmpeg, "-hide_banner", "-nostdin", "-v", "warning", "-i", clip["source"],
                 "-map", "0:a:0", "-vn", "-ar", str(RATE), "-ac", str(CHANNELS),
                 "-c:a", "pcm_s16le", str(converted)], intermediate / f"{clip['id']}.log")
        data, frames = read_pcm(converted)
        tolerance = max(2 / RATE, 2 / clip["sampleRate"])
        if abs(frames / RATE - clip["duration"]) > tolerance:
            raise ValueError(f"Actual source duration disagrees with manifest: {clip['id']}")
        start = clip["startFrame"]
        end = start + frames
        if start < previous_end or end > plan["frames"] or end / RATE > clip["slotEnd"] + tolerance:
            raise ValueError(f"Actual PCM would overlap or truncate speech: {clip['id']}")
        timeline[start * CHANNELS * WIDTH:end * CHANNELS * WIDTH] = data
        previous_end = end
        intervals.append({"id": clip["id"], "text": clip.get("text", ""),
                          "spoken": clip.get("spoken", clip.get("text", "")),
                          "source": clip["source"], "sourceSHA256": digest(Path(clip["source"])),
                          "generationSpeed": clip["speed"], "start": start / RATE,
                          "end": end / RATE, "startFrame": start, "endFrame": end,
                          "duration": frames / RATE, "slotStart": clip["slotStart"],
                          "slotEnd": clip["slotEnd"], "timeStretchApplied": False})
    raw = folder / "raw_timeline.wav"
    write_pcm(raw, timeline)
    normalization = "loudnorm=I=-16:TP=-1.5:LRA=7"
    measurement = loudness_json(command([ffmpeg, "-hide_banner", "-nostdin", "-i", str(raw),
                                        "-af", normalization + ":print_format=json",
                                        "-f", "null", "-"], folder / "loudnorm_pass1.log"))
    second_filter = (normalization + f":measured_I={measurement['input_i']}"
                     f":measured_TP={measurement['input_tp']}"
                     f":measured_LRA={measurement['input_lra']}"
                     f":measured_thresh={measurement['input_thresh']}"
                     f":offset={measurement['target_offset']}:linear=true:print_format=json")
    final = folder / "narration.wav"
    applied = loudness_json(command([ffmpeg, "-hide_banner", "-nostdin", "-i", str(raw),
                                    "-af", second_filter, "-ar", str(RATE), "-ac", str(CHANNELS),
                                    "-c:a", "pcm_s16le", str(final)], folder / "loudnorm_pass2.log"))
    final_data, final_frames = read_pcm(final)
    if final_frames != plan["frames"]:
        raise ValueError(f"Normalization changed the exact timeline length: {plan['id']}")
    # Keep an utterance-only diagnostic to inspect speech loudness without the
    # intentionally silent gaps. These intervals include TTS in-phrase pauses;
    # they are file spans, not VAD, word alignment or exact phoneme boundaries.
    speech_data = b"".join(final_data[item["startFrame"] * CHANNELS * WIDTH:
                                   item["endFrame"] * CHANNELS * WIDTH] for item in intervals)
    speech_only = folder / "speech_only.wav"
    write_pcm(speech_only, speech_data)
    verified = loudness_json(command([ffmpeg, "-hide_banner", "-nostdin", "-i", str(final),
                                     "-af", normalization + ":print_format=json",
                                     "-f", "null", "-"], folder / "loudnorm_verify.log"))
    speech_measurement = loudness_json(command([ffmpeg, "-hide_banner", "-nostdin", "-i", str(speech_only),
                                               "-af", normalization + ":print_format=json",
                                               "-f", "null", "-"], folder / "loudnorm_speech_only.log"))
    interval_receipt = {"videoID": plan["id"], "intervalKind": "generated utterance file spans, including in-phrase pauses; not word alignment or VAD",
                        "sampleRate": RATE, "intervals": intervals}
    (folder / "speech_only_intervals.json").write_text(json.dumps(interval_receipt, indent=2) + "\n")
    receipt = {"videoID": plan["id"], "videoSource": plan["source"],
               "duration": final_frames / RATE, "frames": final_frames,
               "sampleRate": RATE, "channels": CHANNELS, "sampleWidthBytes": WIDTH,
               "timeStretchApplied": False, "perClipNormalizationApplied": False,
               "target": TARGET, "pass1": measurement, "pass2": applied,
               "verifiedFullTimeline": verified, "verifiedUtteranceOnly": speech_measurement,
               "normalizationNote": "linear=true requested; ffmpeg may report dynamic fallback if linear gain cannot satisfy peak/range targets",
               "rawTimeline": str(raw), "narration": str(final),
               "rawSHA256": digest(raw), "narrationSHA256": digest(final),
               "intervals": str(folder / "speech_only_intervals.json")}
    (folder / "loudness_receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--ffmpeg", default=shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg")
    args = parser.parse_args()
    source = args.manifest.resolve()
    raw_manifest = source.read_bytes()
    manifest = json.loads(raw_manifest)
    plans = validated_plan(manifest, source.parent)
    output = args.output_dir.resolve()
    if output.exists():
        raise SystemExit("Use a new output directory; source and prior renders are preserved.")
    output.mkdir(parents=True)
    (output / "voice-manifest.snapshot.json").write_bytes(raw_manifest)
    receipts = []
    for plan in plans:
        print(f"Assembling {plan['id']}: {len(plan['clips'])} utterances, {plan['duration']:.3f}s", flush=True)
        receipts.append(assemble(plan, output / plan["id"], args.ffmpeg))
    (output / "narration_manifest.json").write_text(json.dumps({
        "sourceManifest": str(source), "sourceManifestSHA256": hashlib.sha256(raw_manifest).hexdigest(),
        "timeStretchApplied": False, "perClipNormalizationApplied": False,
        "videos": receipts}, indent=2) + "\n")
    print(f"Prepared {len(receipts)} exact-duration narration tracks: {output}", flush=True)


if __name__ == "__main__":
    main()
