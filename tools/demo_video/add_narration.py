#!/usr/bin/env python3
"""Add timed narration and open/closed captions to an existing Simulator video.

Usage: python3 tools/demo_video/add_narration.py PLAN.json [--overwrite]
PLAN may contain a single video object, a list, or {"videos": [...]}.
Each video requires sourceSilentVideo, duration, narrationWav, captionsSrt,
cues [{start, end, text}], and outputPath. Paths resolve relative to PLAN.json.
Optional embedClosedCaptions enables a second selectable subtitle track; it is
off by default to avoid players automatically duplicating the burned captions.
Pillow is invoked through --render-python; the main process uses stdlib only.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import sys
from fractions import Fraction
from pathlib import Path

FFMPEG = Path('/opt/homebrew/bin/ffmpeg')
FFPROBE = Path('/opt/homebrew/bin/ffprobe')
BUNDLED_PYTHON = Path('/Users/adrian/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3')
FONT = Path('/System/Library/Fonts/Supplemental/Arial.ttf')
FPS = 30
CREAM = '#F4F1E8'
INK = '#193D35'


def finite(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value):
        raise ValueError(f'{name} must be a finite number')
    return float(value)


def probe(path: Path) -> dict:
    return json.loads(subprocess.check_output([
        str(FFPROBE), '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)
    ], text=True))


def resolve(value: str, base: Path) -> Path:
    path = Path(value).expanduser()
    return (base / path).resolve() if not path.is_absolute() else path.resolve()


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def parse_stamp(text: str) -> float:
    hours, minutes, last = text.strip().split(':')
    return int(hours) * 3600 + int(minutes) * 60 + float(last.replace(',', '.'))


def verify_srt(path: Path, cues: list[dict]) -> None:
    blocks = path.read_text(encoding='utf-8-sig').strip().split('\n\n')
    parsed = []
    for block in blocks:
        lines = block.strip().splitlines()
        if not lines:
            continue
        if '-->' not in lines[0]:
            lines = lines[1:]
        if len(lines) < 2 or '-->' not in lines[0]:
            raise ValueError(f'Malformed SRT block in {path}')
        left, right = lines[0].split('-->')
        parsed.append((parse_stamp(left), parse_stamp(right), ' '.join(' '.join(lines[1:]).split())))
    if len(parsed) != len(cues):
        raise ValueError(f'SRT cue count differs from plan: {len(parsed)} != {len(cues)}')
    for actual, cue in zip(parsed, cues):
        if (abs(actual[0] - cue['start']) > .002 or abs(actual[1] - cue['end']) > .002
                or actual[2] != cue['text']):
            raise ValueError(f'SRT differs from plan cue: {actual} != {cue}')


def validate(raw: dict, base: Path) -> dict:
    result = dict(raw)
    for name in ('sourceSilentVideo', 'narrationWav', 'captionsSrt', 'outputPath'):
        result[name] = resolve(raw[name], base)
    for name in ('sourceSilentVideo', 'narrationWav', 'captionsSrt'):
        if not result[name].is_file():
            raise ValueError(f'Missing {name}: {result[name]}')
    duration = finite(raw['duration'], 'duration')
    if duration <= 0 or abs(round(duration * FPS) - duration * FPS) > .003:
        raise ValueError('Duration must be positive and match an integer number of 30-fps frames')
    frames = round(duration * FPS)
    duration = frames / FPS
    source = probe(result['sourceSilentVideo'])
    video = next((s for s in source['streams'] if s['codec_type'] == 'video'), None)
    if not video or (video['width'], video['height']) not in ((1920, 1080), (1080, 1920)):
        raise ValueError('Expected a 1920×1080 or 1080×1920 source video')
    source_duration = float(source['format']['duration'])
    if abs(source_duration - duration) > 1 / FPS + .002:
        raise ValueError(f'Source duration differs from plan: {source_duration} != {duration}')
    audio = probe(result['narrationWav'])
    if not any(s['codec_type'] == 'audio' for s in audio['streams']):
        raise ValueError('Narration has no audio stream')
    audio_duration = float(audio['format']['duration'])
    if audio_duration > duration + .002:
        raise ValueError(f'Narration would be truncated: {audio_duration} > {duration}')
    cues = []
    previous = 0.0
    for index, cue in enumerate(raw['cues']):
        start, end = finite(cue['start'], 'cue start'), finite(cue['end'], 'cue end')
        text = ' '.join(str(cue['text']).split())
        if start < previous - .000001 or start < 0 or end <= start or end > duration + .002 or not text:
            raise ValueError(f'Cue {index} is empty, overlaps, or exceeds the video bounds')
        start_frame, end_frame = round(start * FPS), min(frames, round(end * FPS))
        if end_frame <= start_frame:
            raise ValueError(f'Cue {index} is shorter than a frame')
        cues.append(dict(start=start, end=end, text=text, start_frame=start_frame, end_frame=end_frame))
        previous = end
    if not cues:
        raise ValueError('At least one caption cue is required')
    verify_srt(result['captionsSrt'], cues)
    result.update(duration=duration, frames=frames, cues=cues,
                  embedClosedCaptions=bool(raw.get('embedClosedCaptions', False)),
                  width=video['width'], height=video['height'], sourceProbe=source,
                  audioProbe=audio)
    return result


def render_strips(spec_path: Path) -> None:
    # This branch executes only in the selected Pillow-capable runtime.
    from PIL import Image, ImageDraw, ImageFont
    spec = json.loads(spec_path.read_text())
    font = ImageFont.truetype(str(FONT), spec['fontSize'])
    width, height = spec['width'], spec['bandHeight']
    max_width = width - 120
    metrics = []
    for item in spec['strips']:
        canvas = Image.new('RGB', (width, height), CREAM)
        draw = ImageDraw.Draw(canvas)
        lines = []
        current = ''
        for word in item['text'].split():
            candidate = f'{current} {word}'.strip()
            if current and draw.textlength(candidate, font=font) > max_width:
                lines.append(current)
                current = word
            else:
                current = candidate
            if draw.textlength(current, font=font) > max_width:
                raise ValueError(f'Unwrappable caption word: {current}')
        if current:
            lines.append(current)
        if len(lines) > 2:
            raise ValueError(f'Caption needs more than two lines; shorten its cue: {item["text"]}')
        line_height = spec['lineHeight']
        top = (height - line_height * len(lines)) / 2
        for index, line in enumerate(lines):
            # Anchor is left/top relative to the visible glyph box, not baseline.
            x = (width - draw.textlength(line, font=font)) / 2
            draw.text((x, top + index * line_height), line, font=font, fill=INK, anchor='lt')
        canvas.save(item['path'])
        metrics.append({'text': item['text'], 'lines': lines, 'path': item['path']})
    spec_path.with_name('caption-layout.json').write_text(json.dumps(metrics, indent=2) + '\n')


def compose(plan: dict, render_python: Path, overwrite: bool, preset: str, crf: int) -> None:
    output = plan['outputPath']
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() and not overwrite:
        raise ValueError(f'Output exists; use --overwrite explicitly: {output}')
    work = output.parent / f'{output.stem}_work'
    if work.exists() and not overwrite:
        raise ValueError(f'Work directory exists; use --overwrite explicitly: {work}')
    work.mkdir(exist_ok=True)
    portrait = plan['height'] > plan['width']
    width, height = plan['width'], plan['height']
    band = 192 if portrait else 108
    strips = [{'text': '', 'path': str(work / 'caption-blank.png')}]
    for index, cue in enumerate(plan['cues']):
        strips.append({'text': cue['text'], 'path': str(work / f'caption-{index:03}.png')})
    spec_path = work / 'caption-render-spec.json'
    spec_path.write_text(json.dumps({'width': width, 'bandHeight': band,
        'fontSize': 42 if portrait else 36, 'lineHeight': 52 if portrait else 44,
        'strips': strips}, indent=2) + '\n')
    subprocess.run([str(render_python), str(Path(__file__).resolve()), '--render-strips', str(spec_path)], check=True)
    segments = []
    previous = 0
    for index, cue in enumerate(plan['cues']):
        if cue['start_frame'] > previous:
            segments.append(('caption-blank.png', cue['start_frame'] - previous))
        if cue['start_frame'] < previous:
            raise ValueError('Cue frame rounding caused overlap')
        segments.append((f'caption-{index:03}.png', cue['end_frame'] - cue['start_frame']))
        previous = cue['end_frame']
    if previous < plan['frames']:
        segments.append(('caption-blank.png', plan['frames'] - previous))
    concat_lines = ['ffconcat version 1.0']
    for name, frames in segments:
        concat_lines.extend([f"file '{name}'", 'option framerate 30', f'duration {frames / FPS:.9f}'])
    concat_lines.extend([f"file '{segments[-1][0]}'", 'option framerate 30'])
    concat_path = work / 'caption-strips.ffconcat'
    concat_path.write_text('\n'.join(concat_lines) + '\n')
    max_w, max_h = (960, 1706) if portrait else (1728, 972)
    graph = (
        f'[0:v]scale={max_w}:{max_h}:force_original_aspect_ratio=decrease:force_divisible_by=2,'
        f'setsar=1,pad={width}:{height}:(ow-iw)/2:0:color=0xF4F1E8[base];'
        f'[1:v]fps=30,format=rgba[caption];'
        f'[base][caption]overlay=0:{height-band}:eof_action=repeat:shortest=0,'
        'format=yuv420p[video];'
        f'[2:a]aresample=48000,aformat=channel_layouts=stereo,apad,'
        f'atrim=duration={plan["duration"]:.9f},asetpts=PTS-STARTPTS[audio]'
    )
    command = [str(FFMPEG), '-y' if overwrite else '-n', '-v', 'warning', '-nostats',
        '-filter_complex_threads', '2', '-i', str(plan['sourceSilentVideo']),
        '-f', 'concat', '-safe', '0', '-i', str(concat_path),
        '-i', str(plan['narrationWav'])]
    if plan['embedClosedCaptions']:
        command.extend(['-i', str(plan['captionsSrt'])])
    command.extend(['-filter_complex', graph, '-map', '[video]', '-map', '[audio]'])
    if plan['embedClosedCaptions']:
        command.extend(['-map', '3:s:0'])
    command.extend([
        '-c:v', 'libx264', '-preset', preset, '-crf', str(crf), '-pix_fmt', 'yuv420p',
        '-r', '30', '-fps_mode', 'cfr', '-frames:v', str(plan['frames']),
        '-c:a', 'aac', '-b:a', '192k', '-ar', '48000', '-ac', '2',
    ])
    if plan['embedClosedCaptions']:
        command.extend(['-c:s', 'mov_text', '-metadata:s:s:0', 'language=eng',
                        '-metadata:s:s:0', 'title=English', '-disposition:s:0', '0'])
    command.extend([
        '-metadata:s:a:0', 'language=eng',
        '-metadata:s:a:0', 'title=English narration',
        '-metadata', 'title=Protacta — visual guidance prototype',
        '-metadata', 'comment=Actual iOS Simulator footage; AI-generated narration with Kokoro af_heart. Synthetic paper scenes are explicitly labeled.',
        '-movflags', '+faststart', '-t', f'{plan["duration"]:.9f}', str(output)])
    (work / 'encode-command.json').write_text(json.dumps(command, indent=2) + '\n')
    print(f'Encoding {output.name}: {plan["frames"]} frames, {len(plan["cues"])} captions', flush=True)
    with (work / 'encode.log').open('w') as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    result = probe(output)
    video = next(s for s in result['streams'] if s['codec_type'] == 'video')
    audio = next(s for s in result['streams'] if s['codec_type'] == 'audio')
    subtitles = [s for s in result['streams'] if s['codec_type'] == 'subtitle']
    if (int(video.get('nb_frames', -1)) != plan['frames'] or Fraction(video['avg_frame_rate']) != FPS
            or (video['width'], video['height']) != (width, height)
            or audio['codec_name'] != 'aac' or int(audio['sample_rate']) != 48000
            or len(subtitles) != int(plan['embedClosedCaptions'])
            or (subtitles and subtitles[0]['codec_name'] != 'mov_text')):
        raise ValueError(f'Delivery stream verification failed: {output}')
    with (work / 'decode.log').open('w') as log:
        subprocess.run([str(FFMPEG), '-v', 'error', '-xerror', '-i', str(output),
                        '-map', '0:v:0', '-map', '0:a:0', '-f', 'null', '-'],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    receipt = {'output': str(output), 'sha256': digest(output), 'probe': result,
        'fullDecodeErrorLogBytes': (work / 'decode.log').stat().st_size,
        'sourceVideo': str(plan['sourceSilentVideo']), 'sourceSHA256': digest(plan['sourceSilentVideo']),
        'narrationWav': str(plan['narrationWav']), 'narrationSHA256': digest(plan['narrationWav']),
        'openCaptions': True, 'closedCaptions': plan['embedClosedCaptions'], 'syntheticVoice': 'Kokoro af_heart',
        'physicalAcceptance': False}
    (work / 'verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'Verified: {output}', flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('plan', nargs='?', type=Path)
    parser.add_argument('--overwrite', action='store_true')
    parser.add_argument('--render-python', type=Path, default=BUNDLED_PYTHON if BUNDLED_PYTHON.exists() else Path(sys.executable))
    parser.add_argument('--preset', default='medium')
    parser.add_argument('--crf', type=int, default=18)
    parser.add_argument('--render-strips', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.render_strips:
        render_strips(args.render_strips)
        return
    if args.plan is None:
        parser.error('a JSON plan is required')
    plan_path = args.plan.resolve()
    raw = json.loads(plan_path.read_text())
    videos = raw if isinstance(raw, list) else raw.get('videos', [raw])
    plans = [validate(video, plan_path.parent) for video in videos]
    targets = [plan['outputPath'] for plan in plans]
    if len(set(targets)) != len(targets):
        raise ValueError('Each outputPath must be unique')
    for plan in plans:
        compose(plan, args.render_python, args.overwrite, args.preset, args.crf)


if __name__ == '__main__':
    main()
