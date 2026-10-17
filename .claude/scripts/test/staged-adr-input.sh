#!/usr/bin/env bash
# Spec006 AC-10 / T328: actual supported payload and installer, no network writes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
staged_path = Path('verify/2026-06-12-gap-fixes/staged')
workflow_path = Path('.github/workflows/adr-gate.yml')
expression = '${{ github.base_ref }}'

def step_document(path):
    text = path.read_text()
    start = text.index('      - name: Check architectural surfaces vs ADR presence\n')
    step = text[start:]
    lines = step.splitlines()
    run_index = lines.index('        run: |')
    script = '\n'.join(line[10:] for line in lines[run_index+1:] if line.startswith('          ')) + '\n'
    assert script.strip(), 'actual ADR run body missing'
    values = {}
    inside = False
    for line in lines[:run_index]:
        if line == '        env:':
            inside = True
        elif inside and line.startswith('          '):
            key, value = line.strip().split(':', 1)
            values[key] = value.strip()
        elif inside:
            inside = False
    return script, values

with tempfile.TemporaryDirectory(prefix='staged-adr-input-') as directory:
    temp = Path(directory)
    fixture = temp / 'target'
    (fixture / '.claude').mkdir(parents=True)
    (fixture / '.claude/CLAUDE.md').write_text('Disposable installer target.\n')
    # Run the real installer over the full actual payload, only in this fixture.
    shutil.copytree(root / staged_path, fixture / staged_path)
    installed = subprocess.run(['bash', str(fixture / staged_path / 'install.sh')], cwd=fixture, text=True, capture_output=True)
    assert installed.returncode == 0, installed.stderr
    assert (fixture / workflow_path).read_bytes() == (root / staged_path / workflow_path).read_bytes(), 'installer changed supported workflow'
    shutil.copyfile(root / '.claude/adr-surfaces.txt', fixture / '.claude/adr-surfaces.txt')
    bins = temp / 'bin'
    bins.mkdir()
    (bins / 'git').write_text('''#!/usr/bin/env python3
import json,os,sys
with open(os.environ['GIT_TRACE_FILE'], 'a') as stream: stream.write(json.dumps(sys.argv[1:])+'\\n')
if sys.argv[1]=='diff': print(os.environ.get('CHANGED_FILES',''))
elif sys.argv[1]=='log': print(os.environ.get('COMMIT_BODY',''))
''')
    (bins / 'git').chmod(0o755)
    marker = temp / 'never-created'
    # Main branch is the current trigger; hostile values are controlled shell-data regressions.
    cases = [
        ('substitution', f'$(touch {marker})', '', '', 0),
        ('backtick', f'`touch {marker}`', '', '', 0),
        ('quote', f'"; touch {marker}; #', '', '', 0),
        ('newline', 'main\nsecond-line', '', '', 0),
        ('no-architecture', 'main', 'README.md', '', 0),
        ('architecture-missing-ADR', 'main', '.mcp.json', '', 1),
        ('ADR-file', 'main', '.mcp.json\n.claude/memory/decisions/0123-fixture.md', '', 0),
        ('ADR-commit', 'main', '.mcp.json', 'Implement ADR-0123', 0),
    ]
    for label, workflow in [('supported', root / staged_path / workflow_path), ('installed', fixture / workflow_path)]:
        script, values = step_document(workflow)
        for name, payload, changed, commit, expected in cases:
            trace = temp / f'{label}-{name}.jsonl'
            env = {'PATH': str(bins)+os.pathsep+os.environ['PATH'], 'GIT_TRACE_FILE': str(trace), 'CHANGED_FILES': changed, 'COMMIT_BODY': commit}
            for key, value in values.items(): env[key] = value.replace(expression, payload)
            generated = script.replace(expression, payload)
            result = subprocess.run(['bash', '-e', '-o', 'pipefail', '-c', generated], cwd=fixture, env=env, text=True, capture_output=True)
            assert not marker.exists(), (label, name, 'shell payload executed')
            assert result.returncode == expected, (label, name, result.returncode, result.stdout, result.stderr)
            calls = [json.loads(line) for line in trace.read_text().splitlines()]
            assert calls[0] == ['fetch', 'origin', payload, '--depth=50'], (label, name, calls)
            assert calls[1] == ['diff', '--name-only', 'origin/'+payload+'...HEAD'], (label, name, calls)
            print(f'PASS {label} actual ADR step: {name}')
    print('PASS actual full-payload installer preserves maintained workflow identity')
PY
