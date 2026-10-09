#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy,importlib.util,json,os,subprocess,sys,tempfile,textwrap
from pathlib import Path
root=Path(sys.argv[1]);module=importlib.util.spec_from_file_location('local',root/'.claude/scripts/check-local-evidence.py');m=importlib.util.module_from_spec(module);module.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
 folder=Path(tmp);subprocess.run(['git','init','-q',tmp],check=True)
 subprocess.run(['git','-C',tmp,'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','base'],check=True)
 commit=subprocess.check_output(['git','-C',tmp,'rev-parse','HEAD'],text=True).strip()
 (folder/'specs/active').mkdir(parents=True);(folder/'.claude/scripts').mkdir(parents=True)
 for file in ('spec-match.sh',): (folder/'.claude/scripts'/file).write_bytes((root/'.claude/scripts'/file).read_bytes())
 paths=[];base={'commit':commit,'ac_total':1,'ac_proven':1,'ac_unproven':[],'verdict':'PASS','smoke_exit_max':0,'runner_exit':0}
 for sid in ('001','002'):
  (folder/f'specs/active/{sid}-example.md').write_text('## Acceptance criteria\n1. **AC-1**: proved\n')
  d=folder/f'verify/{sid}';d.mkdir(parents=True);path=f'verify/{sid}/evidence.json';paths.append(path)
  (folder/path).write_text(json.dumps(dict(base,spec=sid)))
  (d/'results.json').write_text(json.dumps({'testResults':[{'assertionResults':[{'fullName':'AC-1 observable check','status':'passed'}]}]}))
 if os.environ.get('LEGACY_GATE_SCRIPT'):
  old=Path(os.environ['LEGACY_GATE_SCRIPT']).read_text()
  start=old.index('          # G53: the bundle must RIDE');end=old.index('      # e2e-audit e2e-rig-2',start)
  changed=folder/'changed.txt';changed.write_text('specs/active/001-example.md\nspecs/active/002-example.md\n'+paths[0]+'\n')
  (folder/paths[0]).write_text(json.dumps(dict(base,spec='001',ac_total=0,ac_proven=0)))
  script=textwrap.dedent(old[start:end]).replace('/tmp/pr-changed-files.txt',str(changed))
  result=subprocess.run(['bash','-e','-c',script],cwd=folder,env=dict(os.environ,GITHUB_ENV=str(folder/'env')),capture_output=True,text=True)
  print(result.stdout+result.stderr)
  assert result.returncode!=0,'zero-AC bundle and missing second spec were accepted'
  raise SystemExit(0)
 m.validate(folder,['001','002'],paths)
 failed=0
 for expected,selected,mutation in [(['001','002'],paths[:1],None),(['001'],paths,{'ac_total':0}),(['001'],paths,{'runner_exit':1}),(['001'],paths,{'commit':'f'*40}),(['001'],paths,{'ac_unproven':None})]:
  (folder/paths[0]).write_text(json.dumps(dict(base,spec='001',**(mutation or {}))))
  try:m.validate(folder,expected,selected)
  except (ValueError,TypeError):failed+=1
  else:raise AssertionError('invalid/missing proof accepted')
 print(f'passed: {failed+1}; failed: 0')
PY
