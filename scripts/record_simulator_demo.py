#!/usr/bin/env python3
"""Record real Simulator UI driven by DemoCaptureUITests, with explicit handshakes.

No phone access, synthetic camera promotion, UI replacement, or application edits.
XCTest writes readiness only after the native page exists. Recording starts
before the host acknowledges, and ends before the next app launch.
"""
from argparse import ArgumentParser
from datetime import datetime, timezone
from pathlib import Path
import json
import os
import signal
import subprocess
import time
import uuid
import hashlib

ROOT = Path(__file__).resolve().parents[1]
DEVELOPER = "/Applications/Xcode.app/Contents/Developer"
RUNNER_ID = "org.realitycore.protacta.prototype.ProtactaUITests.xctrunner"
CLIPS = ["01_origami", "02_everyday", "03_aeris", "04_synthetic_paper"]


def run(device: str, output: Path, clips: list[str]) -> None:
    output = output.resolve()
    if output.exists() and any(output.iterdir()):
        raise SystemExit("Use a fresh output directory; previous captures are preserved.")
    (output / "raw").mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, DEVELOPER_DIR=DEVELOPER)
    if not clips or len(set(clips)) != len(clips) or any(clip not in CLIPS for clip in clips):
        raise SystemExit("Choose a nonempty, unique subset of the four supported clips.")
    clips = [clip for clip in CLIPS if clip in clips]
    lookup = subprocess.run(["xcrun", "simctl", "get_app_container", device, RUNNER_ID, "data"],
                            env=env, capture_output=True, text=True, timeout=12)
    if lookup.returncode:
        raise SystemExit("The Simulator UI-test runner must already be installed. Build/run one focused UI test first.")
    container = Path(lookup.stdout.strip())
    request = container / "Documents/ProtactaDemoCapture/recording-request.json"
    request.parent.mkdir(parents=True, exist_ok=True)
    request_id = str(uuid.uuid4())
    request.write_text(json.dumps({"requestID": request_id, "createdAt": time.time(), "clips": clips}))
    start = time.time()
    command = ["xcrun", "xcodebuild", "-project", "ios/Protacta.xcodeproj",
               "-scheme", "Protacta-StoreKit", "-destination", f"platform=iOS Simulator,id={device}",
               "-derivedDataPath", "output/DerivedData", "-resultBundlePath", str(output / "Demo.xcresult"),
               "-parallel-testing-enabled", "NO", "-only-testing:ProtactaUITests/DemoCaptureUITests/testRecordDemoSequence", "test"]
    manifest = {"schemaVersion": 1, "startedAtUTC": datetime.now(timezone.utc).isoformat(),
                "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "device": device, "environment": "iOS Simulator; native prototype Build 7",
                "physicalAcceptance": False, "clips": [], "selectedClips": clips, "command": command,
                "workingTreeChanges": subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).splitlines()}
    for source in [ROOT / "ios/PaperStepsUITests/DemoCaptureUITests.swift", Path(__file__).resolve()]:
        snapshot = output / source.name
        snapshot.write_bytes(source.read_bytes())
        manifest.setdefault("captureSourceSnapshots", {})[str(snapshot)] = hashlib.sha256(snapshot.read_bytes()).hexdigest()
    test_log = (output / "test.log").open("w")
    test = subprocess.Popen(command, cwd=ROOT, env=env, stdout=test_log, stderr=subprocess.STDOUT, start_new_session=True)
    recorder = None
    recorder_log = None
    session_id = None
    index = 0
    last_container_lookup = 0.0
    deadline = start + 900
    heartbeat = start
    current = None
    try:
        while time.time() < deadline:
            now = time.time()
            if now - heartbeat >= 30:
                print(f"Capture progress: {index}/{len(clips)} complete; XCTest alive={test.poll() is None}", flush=True)
                heartbeat = now
            if container is None or (not (container / "Documents/ProtactaDemoCapture/latest.json").exists() and now - last_container_lookup > 2):
                last_container_lookup = now
                lookup = subprocess.run(["xcrun", "simctl", "get_app_container", device, RUNNER_ID, "data"],
                                        env=env, capture_output=True, text=True, timeout=12)
                if lookup.returncode == 0:
                    container = Path(lookup.stdout.strip())
            message = None
            if container:
                latest = container / "Documents/ProtactaDemoCapture/latest.json"
                try:
                    if latest.stat().st_mtime >= start - 1:
                        message = json.loads(latest.read_text())
                except (OSError, ValueError):
                    pass
            if message and index < len(clips) and message.get("clipID") == clips[index]:
                if session_id is None:
                    session_id = message["sessionID"]
                if message.get("sessionID") != session_id:
                    raise RuntimeError("Unexpected second XCTest capture session")
                session = Path(message["sessionDirectory"])
                if message["phase"] == "ready" and recorder is None:
                    clip_id = clips[index]
                    clip_path = output / "raw" / f"{clip_id}.mp4"
                    record_log = output / f"{clip_id}-record.log"
                    recorder_log = record_log.open("w")
                    recording_requested = time.time()
                    recorder = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(clip_path)],
                                                env=env, stdout=recorder_log, stderr=subprocess.STDOUT, start_new_session=True)
                    limit = time.time() + 20
                    while "Recording started" not in record_log.read_text():
                        if recorder.poll() is not None:
                            raise RuntimeError(f"Recording failed: {record_log.read_text()}")
                        if time.time() > limit:
                            raise RuntimeError("Simulator recorder did not acknowledge first frame")
                        time.sleep(0.1)
                    first_frame = time.time()
                    current = {"id": clip_id, "source": str(clip_path), "syntheticPaper": clip_id == "04_synthetic_paper",
                               "readyAt": message["timestamp"], "recordRequestedAt": recording_requested,
                               "firstFrameObservedAt": first_frame, "goAt": time.time(),
                               "scope": "synthetic paper fixture; not live camera" if clip_id == "04_synthetic_paper" else "native app in iOS Simulator"}
                    (session / f"{clip_id}.start").write_text("recording-first-frame-acknowledged\n")
                    print(f"Recording {clip_id}: first frame acknowledged; native actions released", flush=True)
                elif message["phase"] == "done" and recorder is not None:
                    recorder.send_signal(signal.SIGINT)
                    recorder.wait(timeout=25)
                    recorder_log.close()
                    recorder_log = None
                    current["doneAt"] = message["timestamp"]
                    current["recorderExitCode"] = recorder.returncode
                    recorder = None
                    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=width,height,codec_name", "-of", "json", current["source"]],
                                           check=True, capture_output=True, text=True)
                    current["probe"] = json.loads(probe.stdout)
                    current["events"] = json.loads((session / "events.json").read_text())
                    manifest["clips"].append(current)
                    (output / "capture-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
                    (session / f"{clips[index]}.continue").write_text("recording-finalized\n")
                    print(f"Saved {clips[index]}: {current['probe']['format']['duration']} seconds", flush=True)
                    current = None
                    index += 1
            if test.poll() is not None:
                if index != len(clips) or test.returncode:
                    raise RuntimeError(f"XCTest exited {test.returncode}; recorded {index}/{len(clips)} clips; inspect {output / 'test.log'}")
                manifest["testExitCode"] = test.returncode
                manifest["finishedAtUTC"] = datetime.now(timezone.utc).isoformat()
                (output / "capture-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
                print(f"All actual Simulator captures complete: {output}", flush=True)
                return
            time.sleep(0.1)
        raise RuntimeError("Capture run exceeded its 15-minute bound")
    finally:
        if recorder and recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
            try:
                recorder.wait(timeout=25)
            except subprocess.TimeoutExpired:
                recorder.terminate()
        if recorder_log:
            recorder_log.close()
        if test.poll() is None:
            os.killpg(test.pid, signal.SIGINT)
            try:
                test.wait(timeout=15)
            except subprocess.TimeoutExpired:
                os.killpg(test.pid, signal.SIGTERM)
        test_log.close()
        try:
            if json.loads(request.read_text()).get("requestID") == request_id:
                request.unlink()
        except (OSError, ValueError):
            pass


if __name__ == "__main__":
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--clips", nargs="+", choices=CLIPS, default=CLIPS)
    args = parser.parse_args()
    run(args.device, args.output_dir, args.clips)
