#!/usr/bin/env python3
"""Compose real simulator captures; orchestration uses Python's standard library.

Typography/contact sheets use the already bundled Pillow runtime through the
separate render_plates.py helper. No ffmpeg drawtext or external asset is needed.
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

HERE = Path(__file__).resolve().parent
BUNDLED_PYTHON = Path('/Users/adrian/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3')
FFMPEG = '/opt/homebrew/bin/ffmpeg'
FFPROBE = '/opt/homebrew/bin/ffprobe'
FPS = 30
SCOPES = {'native', 'everyday', 'synthetic', 'aeris'}


def run(command: list[str], log: Path | None = None) -> None:
    if log:
        with log.open('w') as stream:
            subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True)
    else:
        subprocess.run(command, check=True)


def probe(path: Path) -> dict:
    result = subprocess.check_output([FFPROBE, '-v', 'error', '-show_streams',
                                      '-show_format', '-of', 'json', str(path)], text=True)
    return json.loads(result)


def number(value: object, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f'{label} must be a finite number')
    value = float(value)
    if not math.isfinite(value):
        raise ValueError(f'{label} must be finite')
    return value


def resolve_segment(raw: dict, base: Path, index: int) -> dict:
    source = Path(raw['source']).expanduser()
    source = (base / source).resolve() if not source.is_absolute() else source.resolve()
    if not source.is_file():
        raise ValueError(f'Capture does not exist: {source}')
    start = number(raw['start'], 'start')
    end = number(raw['end'], 'end')
    if start < 0 or end <= start:
        raise ValueError('Each segment needs explicit 0 <= start < end')
    scope = raw.get('scope', 'native')
    if scope not in SCOPES:
        raise ValueError(f'scope must be one of {sorted(SCOPES)}')
    data = probe(source)
    video = next((item for item in data['streams'] if item['codec_type'] == 'video'), None)
    if video is None:
        raise ValueError(f'No video stream: {source}')
    duration = float(data.get('format', {}).get('duration', video.get('duration', 0)))
    if end > duration + 0.08:
        raise ValueError(f'Trim ends beyond source duration: {end} > {duration}: {source}')
    frames = round((end - start) * FPS)
    if frames < 3:
        raise ValueError('Trim must contain at least three frames')
    rotation = 0
    for side in video.get('side_data_list', []):
        if 'rotation' in side:
            rotation = round(float(side['rotation'])) % 360
    if 'rotate' in video.get('tags', {}):
        rotation = round(float(video['tags']['rotate'])) % 360
    if rotation not in (0, 90, 180, 270):
        raise ValueError('Capture has a non-right-angle display rotation; review it before editing')
    width, height = int(video['width']), int(video['height'])
    if rotation in (90, 270):
        width, height = height, width
    result = dict(raw)
    result.update(source=str(source), start=start, end=end, scope=scope,
                  duration=frames / FPS, frames=frames, width=width,
                  height=height, source_display_rotation=rotation, index=index)
    return result


def composition_geometry(segment: dict, portrait: bool) -> tuple[int, int, int, int]:
    canvas_w, canvas_h = (1080, 1920) if portrait else (1920, 1080)
    if portrait:
        max_w, max_h, center_x, top = 1004, 1780, 540, 54
    elif segment['width'] > segment['height']:
        max_w, max_h, center_x, top = 1136, 880, 1296, 100
    else:
        max_w, max_h, center_x, top = 800, 956, 1426, 62
    ratio = min(max_w / segment['width'], max_h / segment['height'])
    width = max(2, round(segment['width'] * ratio / 2) * 2)
    height = max(2, round(segment['height'] * ratio / 2) * 2)
    return (round(center_x - width / 2), top + round((max_h - height) / 2), width, height)


def encode(segment: dict, plate: Path, target: Path, geometry: tuple[int, int, int, int],
           preset: str, crf: int) -> None:
    x, y, width, height = geometry
    # Text is part of a static plate outside the app pixels. The captured app is
    # uniformly scaled and never stretched, generated, repainted or inferred.
    graph = (f'[0:v]fps={FPS},setpts=PTS-STARTPTS,'
             f'scale={width}:{height}:flags=lanczos,setsar=1,format=rgba[screen];'
             f'[1:v]format=rgba[plate];'
             f'[plate][screen]overlay={x}:{y}:shortest=1:format=auto,'
             'scale=iw:ih:out_color_matrix=bt709:out_range=tv,format=yuv420p[out]')
    args = [FFMPEG, '-hide_banner', '-y', '-ss', f"{segment['start']:.6f}",
            '-t', f"{segment['duration']:.6f}", '-i', segment['source'],
            '-loop', '1', '-framerate', str(FPS), '-i', str(plate),
            '-filter_complex', graph, '-map', '[out]', '-an',
            '-frames:v', str(segment['frames']), '-r', str(FPS),
            '-c:v', 'libx264', '-preset', preset, '-crf', str(crf), '-threads', '4',
            '-profile:v', 'high', '-level:v', '4.2', '-pix_fmt', 'yuv420p',
            '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
            '-video_track_timescale', '30000', '-movflags', '+faststart', str(target)]
    run(args, target.with_suffix('.encode.log'))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path)
    parser.add_argument('--render-python', default=str(BUNDLED_PYTHON if BUNDLED_PYTHON.exists() else Path(sys.executable)))
    parser.add_argument('--preset', default='medium')
    parser.add_argument('--crf', type=int, default=18)
    parser.add_argument('--render-standalones', action='store_true')
    args = parser.parse_args()
    if not 0 <= args.crf <= 30:
        raise ValueError('crf must be between 0 and 30')
    manifest_path = args.manifest.resolve()
    manifest = json.loads(manifest_path.read_text())
    output = args.output.resolve()
    work = args.work_dir.resolve() if args.work_dir else output.parent / (output.stem + '_work')
    output.parent.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    chapters = [resolve_segment(item, manifest_path.parent, index) for index, item in enumerate(manifest['chapters'], 1)]
    if not chapters:
        raise ValueError('chapters must contain real footage')
    expected_frames = sum(item['frames'] for item in chapters)
    if 'target_duration' in manifest and abs(expected_frames / FPS - number(manifest['target_duration'], 'target_duration')) > 1 / FPS:
        raise ValueError('Explicit trims do not total the declared target_duration')
    render_spec = dict(manifest)
    render_spec['chapters'] = chapters
    display_total = manifest.get('display_total_chapters', len(chapters))
    if type(display_total) is not int or display_total < 1:
        raise ValueError('display_total_chapters must be a positive integer')
    for chapter in chapters:
        display_index = chapter.get('display_index', chapter['index'])
        if type(display_index) is not int or not 1 <= display_index <= display_total:
            raise ValueError('Every display_index must lie within display_total_chapters')
    render_spec['total_chapters'] = display_total
    render_spec['plates'] = []
    for segment in chapters:
        g = composition_geometry(segment, False)
        plate = work / f"chapter_{segment['index']:02d}_plate.png"
        render_spec['plates'].append(dict(segment=segment, portrait=False, geometry=g, output=str(plate)))
    standalones = []
    if args.render_standalones:
        supplied = manifest.get('standalones', manifest['chapters'])
        for group_index, raw in enumerate(supplied, 1):
            cuts = raw.get('segments', [raw])
            if not cuts:
                raise ValueError('A standalone needs at least one real segment')
            segments = [resolve_segment(item, manifest_path.parent, index) for index, item in enumerate(cuts, 1)]
            name = raw.get('name', f"{group_index:02d}_{segments[0].get('scope', 'app')}")
            standalones.append(dict(index=group_index, name=name, segments=segments))
            for segment in segments:
                plate = work / f"portrait_{group_index:02d}_{segment['index']:02d}_plate.png"
                render_spec['plates'].append(dict(segment=segment, portrait=True,
                                                 geometry=composition_geometry(segment, True), output=str(plate)))
    spec_path = work / 'resolved_manifest.json'
    spec_path.write_text(json.dumps(render_spec, indent=2, ensure_ascii=False) + '\n')
    run([args.render_python, str(HERE / 'render_plates.py'), 'plates', str(spec_path)])
    parts = []
    timeline = []
    cursor = 0
    for segment in chapters:
        print(f"Rendering chapter {segment['index']}/{len(chapters)}: {segment['title']}", flush=True)
        part = work / f"chapter_{segment['index']:02d}.mp4"
        encode(segment, work / f"chapter_{segment['index']:02d}_plate.png", part,
               composition_geometry(segment, False), args.preset, args.crf)
        parts.append(part)
        timeline.append(dict(index=segment['index'], title=segment['title'], start=cursor,
                             end=cursor + segment['duration'], scope=segment['scope']))
        cursor += segment['duration']
    concat = work / 'concat.ffconcat'
    # Generated local part basenames contain no apostrophes or arbitrary text.
    concat.write_text('ffconcat version 1.0\n' + ''.join(f"file '{part.name}'\n" for part in parts))
    run([FFMPEG, '-hide_banner', '-y', '-safe', '1', '-f', 'concat', '-i', str(concat),
         '-map', '0:v:0', '-c', 'copy', '-an', '-movflags', '+faststart', str(output)], work / 'concat.log')
    standalone_outputs = []
    for group in standalones:
        name = group['name']
        if not name.replace('_', '').replace('-', '').isalnum():
            raise ValueError('Standalone name must contain only letters/numbers/hyphens/underscores')
        dest = output.parent / f'{name}_portrait.mp4'
        print(f'Rendering portrait export: {dest.name}', flush=True)
        portrait_parts = []
        for segment in group['segments']:
            part = work / f"portrait_{group['index']:02d}_{segment['index']:02d}.mp4"
            encode(segment, work / f"portrait_{group['index']:02d}_{segment['index']:02d}_plate.png", part,
                   composition_geometry(segment, True), args.preset, args.crf)
            portrait_parts.append(part)
        portrait_concat = work / f"portrait_{group['index']:02d}.ffconcat"
        portrait_concat.write_text('ffconcat version 1.0\n' + ''.join(f"file '{part.name}'\n" for part in portrait_parts))
        run([FFMPEG, '-hide_banner', '-y', '-safe', '1', '-f', 'concat', '-i', str(portrait_concat),
             '-map', '0:v:0', '-c', 'copy', '-an', '-movflags', '+faststart', str(dest)],
            dest.with_suffix('.concat.log'))
        run([FFMPEG, '-v', 'error', '-i', str(dest), '-f', 'null', '-'],
            dest.with_suffix('.decode.log'))
        portrait_probe = probe(dest)
        portrait_stream = next(item for item in portrait_probe['streams'] if item['codec_type'] == 'video')
        if (portrait_stream['width'], portrait_stream['height'], portrait_stream['pix_fmt'], portrait_stream['codec_name']) != (1080, 1920, 'yuv420p', 'h264'):
            raise ValueError('Portrait export identity is not 1080×1920 H264 yuv420p')
        if int(portrait_stream.get('nb_frames', 0)) != sum(item['frames'] for item in group['segments']):
            raise ValueError('Portrait frame count does not equal its explicit source cuts')
        standalone_outputs.append(str(dest))
    run([FFMPEG, '-v', 'error', '-i', str(output), '-f', 'null', '-'], work / 'full_decode.log')
    qa = dict(output=str(output), timeline=timeline, standalone_outputs=standalone_outputs)
    qa_path = work / 'qa_spec.json'; qa_path.write_text(json.dumps(qa, indent=2) + '\n')
    run([args.render_python, str(HERE / 'render_plates.py'), 'contact', str(qa_path)])
    metadata = probe(output)
    stream = next(item for item in metadata['streams'] if item['codec_type'] == 'video')
    if (stream['width'], stream['height'], stream['pix_fmt'], stream['codec_name']) != (1920, 1080, 'yuv420p', 'h264'):
        raise ValueError('Final export identity is not 1080p H264 yuv420p')
    if int(stream.get('nb_frames', 0)) != expected_frames:
        raise ValueError('Final frame count does not equal the explicit chapter trims')
    if Fraction(stream['avg_frame_rate']) != FPS:
        raise ValueError('Final export frame rate is not exactly 30fps')
    receipt = dict(output=str(output), sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                   duration=metadata['format']['duration'], width=1920, height=1080,
                   frame_rate=stream['avg_frame_rate'], frames=stream.get('nb_frames'),
                   expected_frames=expected_frames, full_decode='passed', audio='silent',
                   timeline=timeline, standalones=standalone_outputs,
                   source_provenance=manifest.get('source_provenance', 'unspecified by manifest'),
                   scope='Composited supplied footage. This renderer does not certify source provenance or physical AR/camera acceptance.')
    (work / 'render_receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2), flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
