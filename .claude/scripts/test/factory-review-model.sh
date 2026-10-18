#!/usr/bin/env bash
# AC-3: selected reviewer model, strict observed usage and routing drift.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'CHECK'
import pathlib,sys,tempfile,shutil,subprocess
root=pathlib.Path(sys.argv[1]); model='claude-sonnet-5-5'
for file in ['.claude/agents/quality/reviewer.md','.claude/skills/review/SKILL.md']:
 assert 'model: '+model+'\n' in (root/file).read_text(), file+' must select Sonnet 5.5'
assert '--model '+model in (root/'.github/workflows/pr-review.yml').read_text()
assert "MODEL = '"+model+"'" in (root/'.claude/scripts/retain-claude-review.py').read_text()
for file in ['claude-review','claude-security']:
 assert 'ordinary-review-runtime/run-claude-review.py' in (root/'.github/workflows'/str(file+'.yml')).read_text(), file
assert "'--model', proof.MODEL" in (root/'.claude/scripts/run-claude-review.py').read_text()
# Retain 4.x rows: a skipped 5.5 row must not turn drift into a false pass.
with tempfile.TemporaryDirectory() as folder:
 fixture=pathlib.Path(folder)
 shutil.copytree(root/'.claude/agents',fixture/'.claude/agents')
 (fixture/'.claude/scripts').mkdir()
 shutil.copy(root/'.claude/scripts/check-doc-consistency.sh',fixture/'.claude/scripts/check-doc-consistency.sh')
 routing='- Opus 4.8: implementer\n- Sonnet 4.6: planner\n- Sonnet 5.5: reviewer\n'
 (fixture/'CLAUDE.md').write_text(routing);(fixture/'.claude/CLAUDE.md').write_text(routing)
 command=['bash',str(fixture/'.claude/scripts/check-doc-consistency.sh')]
 assert subprocess.run(command,capture_output=True).returncode==0, 'matching 5.5 pair rejected'
 (fixture/'CLAUDE.md').write_text(routing.replace('Sonnet 5.5','Opus 5.5'))
 result=subprocess.run(command,capture_output=True,text=True)
 assert result.returncode!=0 and 'reviewer' in result.stdout, '5.5 reviewer drift silently skipped'
CHECK
bash "$ROOT/.claude/scripts/test/factory-review-runtime.sh"
bash "$ROOT/.claude/scripts/check-model-consistency.sh"
bash "$ROOT/.claude/scripts/check-doc-consistency.sh"
