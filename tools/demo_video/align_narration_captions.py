#!/usr/bin/env python3
"""Align authored captions to local Whisper token times for generated phrases.

The authored script supplies spelling; independent recognition supplies timing
and an intelligibility cross-check. Recognition is not a human listening test.
"""
from __future__ import annotations

import argparse
import difflib
import json
import re
import subprocess
from pathlib import Path


def normalized(text: str) -> str:
    return ''.join(c.lower() for c in text if c.isalnum())


def stamp(seconds: float) -> str:
    ms = round(seconds * 1000)
    hour, ms = divmod(ms, 3600000)
    minute, ms = divmod(ms, 60000)
    second, ms = divmod(ms, 1000)
    return f'{hour:02}:{minute:02}:{second:02},{ms:03}'


def aligned_word_times(text: str, recognized: dict, duration: float) -> tuple[list[dict], dict]:
    chars, starts, ends, spoken = [], [], [], []
    for segment in recognized['transcription']:
        spoken.append(segment['text'].strip())
        for token in segment.get('tokens', []):
            if token['text'].startswith('[_'):
                continue
            value = normalized(token['text'])
            start = max(0, token['offsets']['from'] / 1000)
            end = min(duration, token['offsets']['to'] / 1000)
            if not value or end < start:
                continue
            for i, char in enumerate(value):
                chars.append(char)
                starts.append(start + (end-start)*i/len(value))
                ends.append(start + (end-start)*(i+1)/len(value))
    expected = normalized(text)
    actual = ''.join(chars)
    matcher = difflib.SequenceMatcher(None, expected, actual, autojunk=False)
    ratio = matcher.ratio()
    if not actual or ratio < .80:
        raise ValueError(f'Recognition differs materially from script ({ratio:.3f}): {text!r} / {" ".join(spoken)!r}')
    matched = {}
    for block in matcher.get_matching_blocks():
        for offset in range(block.size):
            matched[block.a+offset] = block.b+offset
    # A word boundary can fall in a proper name whose spelling recognition
    # changes. Use the nearest matching character rather than inventing speech.
    keys = sorted(matched)
    if not keys:
        raise ValueError('No recognized character timing matches the script')

    def time_at(index: int, ending: bool) -> float:
        if index in matched:
            return (ends if ending else starts)[matched[index]]
        near = min(keys, key=lambda key: abs(key-index))
        return (ends if ending else starts)[matched[near]]

    words, position = [], 0
    previous = 0.0
    for word in text.split():
        length = len(normalized(word))
        if not length:
            continue
        start = max(previous, time_at(position, False))
        end = max(start + .025, time_at(position+length-1, True))
        end = min(duration, end)
        words.append(dict(text=word, start=start, end=end))
        position += length
        previous = start
    return words, dict(script=text, recognized=' '.join(spoken), characterMatchRatio=ratio,
        differences=[dict(operation=op, script=expected[a:b], recognized=actual[c:d])
                     for op,a,b,c,d in matcher.get_opcodes() if op != 'equal'])


def balanced_groups(words: list[dict]) -> list[list[dict]]:
    # Balance whole phrases so a greedy line break cannot leave a flashing
    # one-word subtitle. Prefer sentence/clause endings and readable durations.
    count = len(words)
    costs = [float('inf')] * (count+1)
    paths: list[list[list[dict]] | None] = [None] * (count+1)
    costs[0], paths[0] = 0, []
    for end in range(1, count+1):
        for start in range(end):
            group = words[start:end]
            text = ' '.join(w['text'] for w in group)
            if len(text) > 80 or paths[start] is None:
                continue
            duration = group[-1]['end'] - group[0]['start']
            penalty = 1 + ((len(text)-58)/58)**2
            penalty += max(0, 3-len(group))*2 + max(0, 1.15-duration)*4
            if end < count:
                penalty += 0 if re.search(r'[.!?]$', group[-1]['text']) else (.15 if group[-1]['text'].endswith(',') else .45)
            candidate = costs[start] + penalty
            if candidate < costs[end]:
                costs[end], paths[end] = candidate, paths[start] + [group]
    if paths[count] is None:
        raise ValueError('No readable caption grouping exists')
    return paths[count]


def caption_groups(words: list[dict]) -> list[list[dict]]:
    sentences, current = [], []
    for index, word in enumerate(words):
        current.append(word)
        remaining = len(words)-index-1
        if re.search(r'[.!?]$', word['text']) and len(current) >= 4 and remaining >= 4:
            sentences.append(current)
            current = []
    if current:
        sentences.append(current)
    return [group for sentence in sentences for group in balanced_groups(sentence)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--audio-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--video-output-dir', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    voice_dir = args.manifest.resolve().parent
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    asr_dir = output/'asr'
    asr_dir.mkdir(exist_ok=True)
    plans, report = [], []
    for video in manifest['videos']:
        cues = []
        clips = sorted((c for c in manifest['clips'] if c['videoID'] == video['id']), key=lambda c:c['slotStart'])
        for clip in clips:
            wav = voice_dir/clip['file']
            recognized_file = asr_dir/f'{wav.stem}.json'
            if not recognized_file.exists():
                with (asr_dir/f'{wav.stem}.log').open('w') as log:
                    subprocess.run(['whisper-cli', '-m', str(args.model), '-f', str(wav),
                        '-l', 'en', '-t', '4', '-ojf', '-of', str(recognized_file.with_suffix(''))],
                        check=True, stdout=log, stderr=subprocess.STDOUT)
            words, match = aligned_word_times(clip['text'], json.loads(recognized_file.read_text()), clip['duration'])
            report.append(dict(id=clip['id'], **match))
            groups = caption_groups(words)
            for index, group in enumerate(groups):
                start = clip['audioStart'] + group[0]['start'] - .05
                next_start = (clip['audioStart'] + groups[index+1][0]['start'] - .05
                              if index+1 < len(groups) else clip['slotEnd']-.04)
                end = min(next_start, clip['audioStart'] + group[-1]['end'] + .20)
                start = max(clip['slotStart'], start, cues[-1]['end'] if cues else 0)
                end = min(clip['slotEnd']-.04, max(end, start+.15))
                if end <= start:
                    raise ValueError(f'Invalid aligned caption: {clip["id"]}')
                cues.append(dict(start=round(start,3), end=round(end,3), text=' '.join(w['text'] for w in group)))
            print(f'Aligned {clip["id"]}: recognition character match {match["characterMatchRatio"]:.3f}', flush=True)
        srt = output/f'{video["id"]}.en.srt'
        srt.write_text('\n'.join(f'{i+1}\n{stamp(c["start"])} --> {stamp(c["end"])}\n{c["text"]}\n' for i,c in enumerate(cues))+'\n')
        file_name = Path(video['source']).stem+'_Narrated_EN.mp4'
        plans.append(dict(id=video['id'], sourceSilentVideo=video['source'], duration=video['duration'],
            narrationWav=str(args.audio_dir.resolve()/video['id']/'narration.wav'),
            captionsSrt=str(srt), cues=cues, outputPath=str(args.video_output_dir.resolve()/file_name)))
    (output/'compositor-plan.json').write_text(json.dumps(dict(videos=plans),indent=2)+'\n')
    (output/'recognition-review.json').write_text(json.dumps(dict(method='Local Whisper base; per-phrase token timing; authored spelling retained; automated cross-check, not human listening', clips=report),indent=2)+'\n')


if __name__ == '__main__':
    main()
