#!/usr/bin/env python3
"""Prepare a separate export workspace from the reviewed MIT geometry source.

No upstream files are edited, and no upstream package/lifecycle scripts run.
Install pinned Three.js in the resulting workspace with npm --ignore-scripts.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

REVIEWED_COMMIT = '4acb4da958d34a367b11c0293235329e394baa21'
THREE_VERSION = '0.185.1'


def prepare(source, workspace):
    source, workspace = Path(source).resolve(), Path(workspace).resolve()
    if source == workspace or source in workspace.parents or workspace in source.parents:
        raise ValueError('Export workspace must be separate from the original checkout')
    commit = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if commit != REVIEWED_COMMIT:
        raise ValueError('This source revision has not been reviewed')
    if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True).strip():
        raise ValueError('Original checkout must be unchanged')
    workspace.mkdir(parents=True, exist_ok=False)
    hashes = {}
    for name in ('engine.js', 'blade.js'):
        data = (source / 'src' / name).read_bytes()
        (workspace / name).write_bytes(data)
        hashes[name] = hashlib.sha256(data).hexdigest()
    shutil.copyfile(source / 'LICENSE', workspace / 'LICENSE')
    shutil.copyfile(Path(__file__).with_name('export_turbofan.mjs'), workspace / 'export_turbofan.mjs')
    engine = (workspace / 'engine.js').read_text()
    needle = "import { makeBladeGeometry, bladeRow } from './blade.js';"
    if engine.count(needle) != 1:
        raise ValueError('The reviewed blade-generator import has changed')
    replacement = """import { makeBladeGeometry as sourceBladeGeometry, bladeRow } from './blade.js';
// Mobile derivative: retain all blade rows and source profile parameters.
function makeBladeGeometry(options = {}) {
  return sourceBladeGeometry({...options,
    radialSegments: Math.min(options.radialSegments ?? 12, 3),
    chordSegments: Math.min(options.chordSegments ?? 16, 6)});
}"""
    (workspace / 'engine_mobile.js').write_text(engine.replace(needle, replacement))
    (workspace / 'package.json').write_text(json.dumps({
        'name': 'protacta-reviewed-engine-export', 'private': True, 'type': 'module',
        'dependencies': {'three': THREE_VERSION}
    }, indent=2) + '\n')
    (workspace / 'source-review.json').write_text(json.dumps({
        'source': 'https://github.com/jubbon/jet-engine-3d', 'sourceCommit': commit,
        'license': 'MIT', 'author': 'Dmitry Kulikov', 'originalSHA256': hashes,
        'mobileSampling': {'radialMaximum': 3, 'chordMaximum': 6},
        'upstreamOperationOrPhysicsCodeIncluded': False
    }, indent=2) + '\n')
    print(workspace)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('workspace', type=Path)
    args = parser.parse_args()
    prepare(args.source, args.workspace)
