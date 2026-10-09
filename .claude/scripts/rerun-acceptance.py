#!/usr/bin/env python3
"""Rerun newly completed candidate tasks. Execute only in an isolated runner."""
import argparse
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

HEADER = re.compile(r'^- \[([ x~!sb])\] (T-\d+)\b')


def tasks(text):
    result = {}
    current = None
    for line in text.splitlines():
        match = HEADER.match(line)
        if match:
            state, current = match.groups()
            if current in result:
                raise ValueError(f'duplicate task identity: {current}')
            result[current] = {'state': state, 'accept': None}
        elif line.startswith('- [') or line.startswith('## '):
            current = None
        elif current and re.match(r'^\s+accept:', line):
            if result[current]['accept'] is not None:
                raise ValueError(f'duplicate acceptance command: {current}')
            result[current]['accept'] = line.split('accept:', 1)[1].strip()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--base')
    parser.add_argument('--timeout', type=float, default=300)
    args = parser.parse_args()
    root = args.root.resolve(strict=True)
    if not args.timeout > 0 or args.timeout > 3600:
        raise ValueError('timeout must be between 0 and 3600 seconds')

    def git(*words):
        return subprocess.check_output(['git', '-C', str(root), *words], text=True, stderr=subprocess.DEVNULL).strip()

    git('rev-parse', '--verify', 'HEAD^{commit}')
    base = args.base
    if not base:
        for ref in ('origin/main', 'main', 'origin/master', 'master'):
            try:
                base = git('merge-base', ref, 'HEAD')
                break
            except subprocess.CalledProcessError:
                pass
    if not base:
        raise ValueError('acceptance base unavailable; fetch base history and pass --base')
    base = git('rev-parse', '--verify', f'{base}^{{commit}}')
    # Missing a base ledger is legitimate for its first introduction. Missing git
    # objects/errors must not be mistaken for that case.
    paths = git('ls-tree', '--name-only', base, '--', 'tasks/TASKS.md')
    previous = tasks(git('show', f'{base}:tasks/TASKS.md')) if paths else {}
    candidate = tasks((root / 'tasks/TASKS.md').read_text())
    selected = [tid for tid, task in candidate.items()
                if task['state'] == 'x' and previous.get(tid, {}).get('state') != 'x']
    for tid in selected:
        command = candidate[tid]['accept']
        if not command or command.startswith('<') or command.lower() in ('tbd', 'human', 'todo'):
            raise ValueError(f'{tid}: executable acceptance command required')
        proc = subprocess.Popen(['bash', '-o', 'pipefail', '-c', command], cwd=root, start_new_session=True)
        try:
            code = proc.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            raise ValueError(f'{tid}: acceptance timed out') from None
        if code:
            raise ValueError(f'{tid}: acceptance failed ({code})')
        print(f'{tid}: acceptance PASS', flush=True)
    print(f'acceptance: PASS ({len(selected)} newly completed tasks; base={base})')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'acceptance: FAIL: {error}', file=sys.stderr)
        sys.exit(1)
