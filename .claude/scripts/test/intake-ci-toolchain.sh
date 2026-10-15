#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import ast,re,shlex,sys,textwrap,yaml
root=Path(sys.argv[1]);manifest='factory/feedback-crypto-requirements.txt'
requirements=(root/manifest).read_text().splitlines()
assert requirements and all(re.fullmatch(r'[A-Za-z0-9_-]+==[0-9]+(?:\.[0-9]+)+(?:[A-Za-z0-9.]*)',line) for line in requirements),'crypto toolchain must use exact pinned requirements'
def tokens(line):
 try:return shlex.split(line)
 except ValueError:return []
workflow=yaml.safe_load((root/'.github/workflows/evidence-gate.yml').read_text())
command=['python3','-m','pip','install','-r',manifest]
verified=0
for job in workflow['jobs'].values():
 steps=job.get('steps',[])
 for index,step in enumerate(steps):
  if 'bash .claude/scripts/verify.sh' not in step.get('run',''):continue
  installs=[candidate for candidate in steps[:index] if any(tokens(line)==command for line in candidate.get('run','').splitlines() if line.strip() and not line.lstrip().startswith('#'))]
  assert installs,'evidence G49 verification lacks prior pinned crypto dependency installation'
  assert any(candidate.get('if')==step.get('if') and not candidate.get('continue-on-error',False) for candidate in installs),'crypto install must share verification condition and propagate failure'
  verified+=1
assert verified==1,'expected actual G49 verify entrypoint'
harness=yaml.safe_load((root/'.github/workflows/harness-validate.yml').read_text())
assert any(tokens(line)==command for job in harness['jobs'].values() for step in job.get('steps',[]) for line in step.get('run','').splitlines() if line.strip() and not line.lstrip().startswith('#')),'evidence dependency command must match maintained harness setup'
# Scan every maintained factory fixture, including copied/inherited builders.
# Host Python is the test runner, not an 8 MB protected source artifact.
offenders=[]
for fixture in sorted((root/'.claude/scripts/test').glob('factory*')):
 if not fixture.is_file():continue
 lines=fixture.read_text().splitlines()
 for number,line in enumerate(lines,1):
  direct='sys.executable' in line and re.search(r'\b(?:pins|trusted_files)\b',line)
  indirect=False
  if re.match(r'^\s*pins(?:\s*[+=]|\.(?:extend|append)\s*\()',line):
   for end in range(number,min(len(lines),number+30)+1):
    try:statement=ast.parse(textwrap.dedent('\n'.join(lines[number-1:end])))
    except SyntaxError:continue
    indirect=any(isinstance(node,ast.Attribute) and node.attr=='executable' and isinstance(node.value,ast.Name) and node.value.id=='sys' for node in ast.walk(statement));break
  if direct or indirect:offenders.append(str(fixture.relative_to(root))+':'+str(number))
assert not offenders,'redundant host interpreter in fixture source/probe pin closure: '+', '.join(offenders)
print('intake-ci-toolchain: actual G49 verify preceded by matching fail-closed pinned crypto install; requirements exact-pinned')
PY
