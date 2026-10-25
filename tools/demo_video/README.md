# Simulator demo capture and editing

These tools record the native app running in iOS Simulator, then add presentation
titles outside the recorded screen. They do not generate or repaint app pixels.

Run from the repository root. Requirements: Xcode at `/Applications/Xcode.app`, a
booted iPhone Simulator, `ffmpeg` and `ffprobe` in `/opt/homebrew/bin`, and Pillow.
The compositor defaults to the bundled Codex Python runtime; `--render-python`
can select another Python with Pillow. Typography uses macOS Arial fonts.

## Capture

Regenerate the project with `python3 scripts/generate_xcode_project.py` after
adding the UI test. The `ProtactaUITests` runner must already be installed on the
selected Simulator; running a focused ordinary UI test installs it. Find the
device identifier with `xcrun simctl list devices`.

```sh
python3 scripts/record_simulator_demo.py \
  --device SIMULATOR_UDID \
  --output-dir output/demo-video-new/capture-run01
```

Use a fresh output directory. Optional `--clips 03_aeris 04_synthetic_paper`
records only those clips. A fresh, single-use request in the test runner's
Documents directory enables the capture test. Ordinary test runs skip it without
waiting for a recording host. The host starts recording before acknowledging the
test's ready state, and finalizes each clip before allowing the next app launch.
Manifests retain timestamps, app events, source snapshots and test exit status.

The harness resets learning progress in the selected Simulator. Only the paper
clip enables `--paper-guide-fixture`. It does not use a physical phone.

## Edit

```sh
python3 tools/demo_video/build_edit_manifest.py \
  --capture-manifest output/demo-video-new/capture-run01/capture-manifest.json \
  --output output/demo-video-new/edit_manifest.json
python3 tools/demo_video/compose_demo.py output/demo-video-new/edit_manifest.json \
  --output output/demo-video-new/exports/Protacta_Prototype_Demo_90s.mp4 \
  --render-standalones
```

Repeat `--capture-manifest` to combine runs; a later completed clip supersedes the
same clip in an earlier run. The builder selects known event boundaries, checks
source durations and produces a 90-second / 2700-frame edit. Review the generated
manifest if the UI flow changes. The compositor outputs a 1920×1080 master and
1080×1920 standalone clips at 30 fps, H.264/yuv420p, without audio. Raw Simulator
footage may use variable frame timing; delivery files normalize it to 30 fps.

Keep the persistent Simulator label and synthetic-paper / virtual-product labels.
These videos demonstrate prototype interactions. They do not establish physical
camera alignment, fold accuracy, speech recognition or learning outcomes.

See [the dated capture receipt](../../docs/DEMO_VIDEO_2026-10-26.md) for the actual
delivered files, validation and limitations.

## Narrated edition

The local speech pipeline uses the existing Kokoro JS 1.2.1 full-precision model
cache and `af_heart` model voice. It does not clone a person's voice or require an
API key. Defaults point to the existing workspace runtime; override
`PROTACTA_TTS_MODULES` and `PROTACTA_TTS_CACHE` to select another installed copy.
Model download is disabled. A narration plan contains `videos` with `id`,
`source`, `duration` and timed `segments` (`id`, `start`, `end`, `text`).

```sh
node tools/demo_video/generate_narration.mjs PLAN.json output/new-voice/raw
python3 tools/demo_video/prepare_narration.py \
  --manifest output/new-voice/raw/voice-manifest.json \
  --output-dir output/new-voice/audio
python3 tools/demo_video/align_narration_captions.py \
  --manifest output/new-voice/raw/voice-manifest.json \
  --audio-dir output/new-voice/audio \
  --output-dir output/new-voice/captions \
  --model /absolute/path/to/ggml-base.bin \
  --video-output-dir output/new-voice/exports
python3 tools/demo_video/add_narration.py output/new-voice/captions/compositor-plan.json
```

Speech retains its generated speed; shorten an overlong script instead of
accelerating or cutting speech. Preparation validates exact PCM insertion times
and applies full-track two-pass loudness normalization. Local `whisper-cli`
recognition supplies approximate token timing and an independent text check;
authored spelling is retained. Review proper-name differences and sampled frames.
Recognition is not a substitute for a human listening audit.

The compositor insets the complete original video and adds a separate caption
footer. SRTs remain available for editing. An optional `embedClosedCaptions: true`
adds a selectable `mov_text` track, but some MP4 players enable that track despite
the requested disposition and duplicate the burned text. The delivered edition
uses burned captions only. The tool encodes AAC 48 kHz stereo, verifies frame/stream counts, and
fully decodes audio and video. Prior videos and recording sources remain intact.

The installed ONNX runtime can fault during process shutdown after writing all
WAVs. Check persisted phrase counts and independently decode source WAVs before
assembly; a completed log message alone is insufficient. See
`docs/DEMO_NARRATION_2026-10-26.md` for this run's evidence.
