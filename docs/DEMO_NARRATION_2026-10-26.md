# Narrated Protacta videos — 2026-10-26

Delivered in `/Users/adrian/Desktop/QCRI/Protacta_Demo_Videos_2026-10-26_Narrated/`.
The original silent edition and raw recordings remain intact in the adjacent
`Protacta_Demo_Videos_2026-10-26` folder.

- 90-second landscape master, 1920×1080, 2700 frames.
- Four portrait clips, 1080×1920: 23 s / 690 frames, 26 s / 780 frames,
  22 s / 660 frames, 24.067 s / 722 frames.
- All five contain natural-style English AI narration, burned English captions,
  and AAC 48 kHz stereo audio. Editable SRTs are supplied separately.
- The full package also includes five SRTs, five standalone M4A tracks, the
  actual narration script, previews/contact sheets and verification metadata.
  The sharing ZIP includes all 21 delivery files; no render intermediates.

## Voice and editorial treatment

Used the existing local Kokoro JS 1.2.1 / Kokoro-82M fp32 cache and `af_heart`
original model voice, at generation speed 0.98. No voice was cloned. Cloud API
access and app AI features were not changed. This is post-production narration.

Generated 27 phrases across the five videos. Short windows received shorter
wording rather than accelerated or truncated audio. Picture boundaries remain
unchanged. Narration occupies its assigned time windows with natural gaps.
The original complete video is proportionally inset to leave a separate subtitle
footer, preserving the Simulator, synthetic-paper and virtual-product labels.

The paper footage remains explicitly synthetic; the AERIS manual uses a virtual
concept product. Physical A4 and learning-outcome acceptance remain pending.

## Validation

Evidence is under ignored `output/demo-voice-2026-10-26/`:

- `narration_plan.json`, `voice-run04/voice-manifest.json`: final authored script,
  27 persisted utterances, their exact durations and absolute starts. Earlier
  runs were preserved while short phrases were revised. Matching successful WAVs
  were copied into later runs and independently checked against their manifests.
  The installed ONNX runtime emitted a shutdown mutex fault after generation;
  all 27 phrases were persisted and independently decoded/resampled afterward.
  This is not a clean speech-process exit claim.
- `audio-prepared-run01/narration_manifest.json`: exact-duration 48 kHz stereo
  PCM assembly passed for five videos, without time stretching, overlap or
  truncation. Full-track two-pass loudness normalization measured -15.98 to
  -16.18 LUFS and -1.50 dBTP or lower in the normalized WAVs. Four tracks used
  ffmpeg's dynamic fallback; the AERIS track used linear gain.
- `captions-final/recognition-review.json`: independent local Whisper base
  recognition of all utterances. Character match ratios are 0.975–1.0; all
  differences are spellings of Protacta/AERIS. Authored proper-name spelling was
  retained. Token timing supports captions; it is approximate alignment and not
  an independent human listening audit.
- `exports-final/*_work/verification.json`: all five captioned H.264/AAC renders
  passed complete audio/video decoding with empty error logs, exact 30-fps video
  counts and expected resolution. An extra mov_text track was removed in
  `exports-release/` after independent QA found that MP4 marked it default despite
  the requested disposition. Burned captions and editable SRTs remain; this avoids
  player-dependent duplicate text. Final release A/V streams are bit-identical to
  the captioned renders and passed full decoding again. Master audio and
  picture are both 90.000 seconds. The final short clip's audio differs by less
  than one millisecond from the 24.066667-second picture.
- `qa-final/`: 37 actual final frames, one at each subtitle midpoint, inspected
  via contact sheets and representative full-resolution frames. Captions are
  readable without covering the original UI. This is sampled visual QA; no
  claim of real-time viewing or human listening of every frame/word is made.

The delivery `media_verified.json` contains five final file hashes and technical
properties. Encoded master audio measured -15.99 LUFS / -1.50 dBTP. Sharing ZIP
CRC and byte equality against the delivery folder passed.
No application source, build number, Simulator/device state or remote service was
changed for the narrated edition.
