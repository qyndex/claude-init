#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import copy,importlib.util,json,os,subprocess,sys,tempfile
from pathlib import Path
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-adopt.py';assert path.exists(),'transactional harness ownership adapter absent'
spec=importlib.util.spec_from_file_location('adopt',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def git(path,*args):return subprocess.check_output(['git','-C',str(path),*args],text=True,stderr=subprocess.DEVNULL).strip()
def initialize(path):
 path.mkdir();git(path,'init','-b','main');git(path,'config','user.email','fixture@example.invalid');git(path,'config','user.name','Fixture')
def reject(fn):
 try:fn()
 except (ValueError,OSError):return
 raise AssertionError('unsafe adoption accepted')
def files(path):return {str(item.relative_to(path)):item.read_bytes() for item in path.rglob('*') if item.is_file() and '.git' not in item.relative_to(path).parts}
with tempfile.TemporaryDirectory(prefix="owned harness ' ") as tmp:
 base=Path(tmp).resolve();source=base/'source';initialize(source);(source/'.claude/commands').mkdir(parents=True);(source/'.claude/VERSION').write_text('v1');(source/'.claude/commands/deploy.md').write_text('factory deploy v1')
 for name in ['.claude/state/fleet.json','.claude/memory/topics/customer.md','specs/active/001-secret.md','tasks/TASKS.md','factory/policy.json','.github/workflows/auto-merge.yml']:
  file=source/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('qyndex-only live state')
 git(source,'add','.');git(source,'commit','-m','source v1');first=git(source,'rev-parse','HEAD')
 target=base/'target';initialize(target);(target/'README.md').write_text('my product');(target/'.claude/commands').mkdir(parents=True);(target/'.claude/commands/local.md').write_text('my custom command');(target/'.claude/settings.local.json').write_text('private token');(target/'.claude/memory').mkdir();(target/'.claude/memory/MEMORY.md').write_text('my exact memory')
 git(target,'add','.');git(target,'commit','-m','product');state=base/'private-journals'
 before=files(target);result=m.adopt(source,target,state,dry=True);assert result['changed_files']==7 and files(target)==before and not state.exists()
 result=m.adopt(source,target,state);journal=result['journal'];assert result['source_sha']==first and result['activation_enabled'] is False
 assert m.adopt(source,target,state)['changed_files']==0 and len(list(state.glob('*.json')))==1
 for name,value in before.items():assert (target/name).read_bytes()==value
 for name in ['.claude/state/fleet.json','.claude/memory/topics/customer.md','specs/active/001-secret.md','factory/policy.json','.github/workflows/auto-merge.yml']:assert not (target/name).exists()
 assert 'qyndex' not in (target/'tasks/TASKS.md').read_text() and (target/'tasks/TASKS.md').read_text().startswith('# Tasks')
 manifest=m.load(target/m.MANIFEST);assert manifest['source_sha']==first and set(manifest['files'])=={'.claude/VERSION','.claude/commands/deploy.md'}
 assert state.stat().st_mode&0o777==0o700 and (state/(journal+'.json')).stat().st_mode&0o777==0o600
 (target/'tasks/TASKS.md').write_text('# My approved project tasks\n')
 print('AC-1: actual new/brownfield Git adoption, dry-run and repeat preserve user files and exclude active backlog, secrets, runtime and pilot workflows')
 (source/'.claude/commands/deploy.md').write_text('factory deploy v2');git(source,'add','.');git(source,'commit','-m','source v2')
 baseline=files(target);reject(lambda:m.adopt(source,target,state));assert files(target)==baseline
 (target/'.claude/commands/deploy.md').write_text('my customized deploy');custom=files(target);reject(lambda:m.adopt(source,target,state,upgrade=True));assert files(target)==custom
 (target/'.claude/commands/deploy.md').write_text('factory deploy v1');result=m.adopt(source,target,state,upgrade=True);second=result['journal'];assert (target/'.claude/commands/deploy.md').read_text()=='factory deploy v2'
 m.restore(target,m.load(state/(second+'.json')),state/(second+'.json'));assert files(target)==baseline
 foreign=base/'foreign';initialize(foreign);(foreign/'.claude/commands').mkdir(parents=True);(foreign/'.claude/commands/deploy.md').write_text('foreign customized deployment');original=files(foreign);reject(lambda:m.adopt(source,foreign,state));assert files(foreign)==original
 (target/'.claude/VERSION').chmod(0o755);changed=files(target);reject(lambda:m.adopt(source,target,state,upgrade=True));assert files(target)==changed;(target/'.claude/VERSION').chmod(0o644)
 print('AC-2: version/hash/mode ownership blocks customized and foreign collisions before mutation; explicit upgrades and guarded revert preserve exact previous files')
 def crash(number):
  if number==1:raise OSError('injected partial write')
 reject(lambda:m.adopt(source,target,state,upgrade=True,fault=crash));assert files(target)==baseline
 result=m.adopt(source,target,state,upgrade=True);last=state/(result['journal']+'.json');(target/'.claude/commands/deploy.md').write_text('later user edit');later=files(target);reject(lambda:m.restore(target,m.load(last),last));assert files(target)==later
 (target/'.claude/commands/deploy.md').write_text('factory deploy v2');m.restore(target,m.load(last),last)
 # A killed process leaves a pending journal; recovery accepts only each exact before/after image.
 pending=m.load(last);pending['status']='pending';m.persist(last,pending);m.write(target/'.claude/commands/deploy.md',pending['changes']['.claude/commands/deploy.md']['after']);m.restore(target,pending,last);assert files(target)==baseline
 old_which=m.shutil.which;m.shutil.which=lambda tool:None if tool=='jq' else old_which(tool)
 try:reject(lambda:m.adopt(source,target,state,upgrade=True,check_tools=True))
 finally:m.shutil.which=old_which
 assert files(target)==baseline
 print('AC-3: partial write rollback, exact pending recovery, later-edit protection and required tool failure preserve target and private journal')
 linked=base/'linked';git(target,'worktree','add','-b','linked',str(linked));result=m.adopt(source,linked,state);assert result['changed_files']==7 and (linked/'.git').is_file()
 symlinked=base/'symlinked';initialize(symlinked);(symlinked/'.claude').symlink_to(target/'.claude');reject(lambda:m.adopt(source,symlinked,state))
 dirty=source/'.claude/commands/deploy.md';dirty.write_text('dirty source');reject(lambda:m.adopt(source,linked,state,upgrade=True));git(source,'checkout','--','.claude/commands/deploy.md')
 invalid=copy.deepcopy(manifest);invalid['files']['.claude/scripts/../../private']={'sha256':'a'*64,'mode':0o644};m.write(target/m.MANIFEST,m.json_image(invalid));reject(lambda:m.adopt(source,target,state,upgrade=True));m.write(target/m.MANIFEST,m.json_image(manifest))
 nested=target/'subdir';nested.mkdir();reject(lambda:m.adopt(source,nested,state,upgrade=True))
 git(source,'rm','.claude/commands/deploy.md');git(source,'commit','-m','remove owned command');original=files(target);removed=m.adopt(source,target,state,upgrade=True);assert not (target/'.claude/commands/deploy.md').exists();m.restore(target,m.load(state/(removed['journal']+'.json')),state/(removed['journal']+'.json'));assert files(target)==original
 command=[sys.executable,str(path),'--from',str(source),'--into',str(linked),'--state-root',str(state),'--upgrade'];workers=[subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) for _ in range(2)];results=[worker.communicate(timeout=30) for worker in workers];assert all(worker.returncode==0 for worker in workers),results;assert sorted(json.loads(out)['changed_files'] for out,error in results)==[0,2]
 assert (target/'tasks/TASKS.md').read_text()=='# My approved project tasks\n'
 command=(root/'.claude/commands/adopt.md').read_text();function=command.split('_verify_gates() {',1)[1].split('\ncase \"$verb\"',1)[0];check=subprocess.run(['bash','-c','_verify_gates() {'+function+'\n_verify_gates'],cwd=target,capture_output=True,text=True);assert check.returncode!=0 and 'handoff blocked' in check.stdout
 assert (target/'README.md').read_text()=='my product' and (target/'.claude/settings.local.json').read_text()=='private token'
 print('AC-4: linked worktrees and apostrophe paths work; symlink/traversal, dirty source and non-root targets block; adoption performs no activation or candidate setup execution')
PYTEST
