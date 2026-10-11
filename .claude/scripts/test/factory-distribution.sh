#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import importlib.util,json,shutil,subprocess,sys,tempfile
from unittest.mock import patch
root=Path(sys.argv[1]);spec=importlib.util.spec_from_file_location('adopt',root/'.claude/scripts/factory-adopt.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
required={'factory/feedback-crypto-requirements.txt','factory/runtime.example.json','factory/release.example.json','factory/feedback.example.json','factory/digest.example.json','docs/FACTORY-ADOPTER-SETUP.md','docs/FACTORY-RUNTIME.md','docs/FACTORY-FEEDBACK.md','docs/DEPLOY-INTEGRATION.md'}
assert all(m.allowed(name) for name in required),'adopter package omits pinned dependencies or neutral references'
def git(path,*args):return subprocess.check_output(['git','-C',str(path),*args],text=True,stderr=subprocess.DEVNULL).strip()
def init(path):
 path.mkdir();git(path,'init','-b','main');git(path,'config','user.email','fixture@example.invalid');git(path,'config','user.name','Fixture')
def files(path):return {str(p.relative_to(path)):p.read_bytes() for p in path.rglob('*') if p.is_file() and '.git' not in p.relative_to(path).parts}
def reject(fn):
 try:fn()
 except (ValueError,OSError):return
 raise AssertionError('unsafe package update accepted')
with tempfile.TemporaryDirectory() as temporary:
 base=Path(temporary).resolve();source=base/'source';init(source);state=base/'private'
 for name in required|{'.claude/scripts/factory-adopt.py'}:
  path=source/name;path.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,path)
 (source/'.claude/VERSION').write_text('fixture-v1')
 excluded={'factory/policy.json','factory/github-app-manifest.json','factory/live-credentials.json','.github/workflows/factory-hosted-feedback.yml','.claude/state/private-feedback.sqlite'}
 for name in excluded:
  path=source/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('PILOT ONLY SECRET CANARY')
 git(source,'add','.');git(source,'commit','-m','fixture source')
 targets=[]
 for name in ('new','existing'):
  target=base/name;init(target);(target/'README.md').write_text('my product');(target/'own-config.json').write_text('{"keep":true}');git(target,'add','.');git(target,'commit','-m','my product');before=files(target)
  result=m.adopt(source,target,state);assert result['activation_enabled'] is False
  assert all((target/name).read_bytes()==(source/name).read_bytes() for name in required)
  assert all((target/name).read_bytes()==value for name,value in before.items());targets.append(target)
 print('AC-1: actual new/existing Git adopters receive pinned requirements and neutral references with immutable ownership while retaining their own content')
 target=targets[0]
 for name in excluded:assert not (target/name).exists()
 for name in ('factory/release.example.json','factory/runtime.example.json','factory/feedback.example.json','factory/digest.example.json'):
  example=json.loads((target/name).read_text());assert example['enabled'] is False and example['repository'] is None
  assert all(value not in (target/name).read_text() for value in ('qyndex','C0C7T1Y29K5','U0B3L0TRCTA','5251754'))
 print('AC-2: pilot policy, App identity, workflow, private state and credentials stay excluded; all installed examples are disabled and repository neutral')
 before=files(target);assert m.adopt(source,target,state)['changed_files']==0 and files(target)==before
 dependency=source/'factory/feedback-crypto-requirements.txt';dependency.write_text(dependency.read_text()+'# fixture upgrade\n');git(source,'add','.');git(source,'commit','-m','fixture upgrade')
 reject(lambda:m.adopt(source,target,state));assert files(target)==before
 owned=target/'factory/feedback-crypto-requirements.txt';original=owned.read_text();owned.write_text('customized dependency pins\n');custom=files(target);reject(lambda:m.adopt(source,target,state,upgrade=True));assert files(target)==custom;owned.write_text(original)
 result=m.adopt(source,target,state,upgrade=True);assert owned.read_bytes()==dependency.read_bytes();journal=state/(result['journal']+'.json');m.restore(target,m.load(journal),journal);assert files(target)==before
 foreign=base/'foreign';init(foreign);path=foreign/'factory/runtime.example.json';path.parent.mkdir();path.write_text('my existing config');before=files(foreign);reject(lambda:m.adopt(source,foreign,state));assert files(foreign)==before
 print('AC-3: replay is unchanged; explicit dependency upgrades and guarded revert preserve ownership; customized/foreign config collisions block before partial changes')
 last=base/'no-execution';init(last);original_call=m.subprocess.check_output
 def git_only(command,*args,**kwargs):
  assert command[0]=='git','installer invoked provider, package manager or target code'
  return original_call(command,*args,**kwargs)
 with patch.object(m.subprocess,'check_output',git_only):result=m.adopt(source,last,state)
 guide=(last/'docs/FACTORY-ADOPTER-SETUP.md').read_text();assert 'python3 -m venv' in guide and 'feedback-crypto-requirements.txt' in guide and 'outside' in guide and 'disabled' in guide
 assert result['activation_enabled'] is False
 print('AC-4: actual installation invokes only Git inspection, never pip/provider/target setup; isolated pinned dependency provisioning and per-adopter disabled activation are documented')
PYTEST
