#!/usr/bin/env python3
"""Download pinned candidate artifacts; verify every SHA256 before accepting."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def download(artifact, destination):
    target = destination / artifact['relativePath']
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and digest(target) == artifact['sha256']:
        print('Verified cached:', artifact['name'], flush=True)
        return
    partial = target.with_name(target.name + '.partial')
    subprocess.run(['curl', '--fail', '--location', '--show-error', '--retry', '2',
                    '--connect-timeout', '30', '--max-time', '1800',
                    '--output', str(partial), artifact['url']], check=True)
    if digest(partial) != artifact['sha256']:
        partial.unlink()
        raise ValueError('Checksum mismatch: ' + artifact['name'])
    partial.replace(target)
    print('Verified download:', artifact['name'], target.stat().st_size, 'bytes', flush=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--group', choices=['required', 'model', 'model-large', 'runtime', 'mac-tools', 'all'], default='required')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--destination', type=Path, default=ROOT / 'downloads')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'config/materials-lock.json').read_text())
    for artifact in lock['artifacts']:
        if args.group == 'required' and artifact['group'] not in ('model-large', 'runtime'):
            continue
        if args.group not in ('all', 'required') and artifact['group'] != args.group:
            continue
        print(artifact['group'] + ': ' + artifact['name'], flush=True)
        if not args.dry_run:
            download(artifact, args.destination)
    if args.dry_run:
        print('Dry run complete; no files downloaded.')
    else:
        print('Candidate downloads ready. Phone inference and Taglish quality still require testing.')

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('Download failed:', error, file=sys.stderr)
        sys.exit(1)
