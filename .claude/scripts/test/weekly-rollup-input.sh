#!/usr/bin/env bash
# Spec006 AC-9 / T327: execute the active workflow step without GitHub effects.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
workflow = (root / '.github/workflows/memory-rollup-weekly.yml').read_text()
start = workflow.index('      - name: Generate weekly rollup\n')
end = workflow.index('\n      - name:', start + 1)
step = workflow[start:end]
lines = step.splitlines()
run_index = lines.index('        run: |')
body = '\n'.join(line[10:] for line in lines[run_index+1:] if line.startswith('          ')) + '\n'
assert body.strip(), 'actual workflow run body missing'
expression = '${{ github.event.inputs.week }}'
env_values = {}
in_env = False
for line in lines[:run_index]:
    if line == '        env:':
        in_env = True
    elif in_env and line.startswith('          '):
        key, value = line.strip().split(':', 1)
        env_values[key] = value.strip()
    elif in_env:
        in_env = False

with tempfile.TemporaryDirectory(prefix='weekly-input-') as directory:
    temp = Path(directory)
    fixture = temp / 'workflow'
    (fixture / '.claude/scripts').mkdir(parents=True)
    bin_dir = temp / 'bin'
    bin_dir.mkdir()
    (bin_dir / 'git').write_text('#!/usr/bin/env bash\nexit 0\n')
    (bin_dir / 'git').chmod(0o755)
    # Mock only side-effecting commands; execute the actual extracted run body.
    (fixture / '.claude/scripts/memory-rollup.sh').write_text('''#!/usr/bin/env bash
python3 - "$@" <<'ARGS'
import json,os,sys
with open(os.environ['ARGS_FILE'], 'w') as out: json.dump(sys.argv[1:], out)
ARGS
''')
    marker = temp / 'injection-marker'
    payloads = [f'$(touch {marker})', f'`touch {marker}`', f'"; touch {marker}; #', '2026-W30', '', '2026-W30\nsecond-line']
    for index, payload in enumerate(payloads):
        args_file = temp / f'argv-{index}.json'
        environment = {'PATH': str(bin_dir) + os.pathsep + os.environ['PATH'], 'GITHUB_OUTPUT': str(temp / 'output'), 'ARGS_FILE': str(args_file)}
        for key, value in env_values.items():
            environment[key] = value.replace(expression, payload)
        generated = body.replace(expression, payload)
        result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', generated], cwd=fixture, env=environment, text=True, capture_output=True)
        assert not marker.exists(), ('workflow input executed a shell command', index)
        assert result.returncode == 0, (index, result.stderr)
        assert json.loads(args_file.read_text()) == ['weekly', payload], (index, args_file.read_text())
        print(f'PASS actual workflow step literal argv case {index}')

    # Exercise unchanged real script defaults/validation inside a disposable repo.
    actual = temp / 'real'
    scripts = actual / '.claude/scripts'
    (scripts / 'lib').mkdir(parents=True)
    shutil.copyfile(root / '.claude/scripts/memory-rollup.sh', scripts / 'memory-rollup.sh')
    shutil.copyfile(root / '.claude/scripts/lib/with-lock.sh', scripts / 'lib/with-lock.sh')
    subprocess.run(['git', 'init', '-q', str(actual)], check=True)
    fixed = datetime.datetime(2026, 10, 12, tzinfo=datetime.timezone.utc)
    environment = dict(os.environ, ROLLUP_NOW=str(int(fixed.timestamp())))
    for value, expected in [('2026-W30', '2026-W30'), ('', fixed.strftime('%G-W%V'))]:
        result = subprocess.run(['bash', str(scripts / 'memory-rollup.sh'), 'weekly', value], cwd=actual, env=environment, text=True, capture_output=True)
        assert result.returncode == 0, (value, result.stderr)
        assert (actual / f'.claude/memory/rollups/{expected}.md').is_file(), (value, expected)
    invalid = subprocess.run(['bash', str(scripts / 'memory-rollup.sh'), 'weekly', '2026-W00'], cwd=actual, env=environment, text=True, capture_output=True)
    assert invalid.returncode != 0 and 'invalid' in invalid.stderr, invalid
    assert not (actual / '.claude/memory/rollups/2026-W00.md').exists()
    print('PASS real rollup explicit week/current week/invalid ISO-week behavior')
PY
