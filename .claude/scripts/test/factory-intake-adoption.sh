#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
case "${1:-package}" in package) ;; *) exit 2 ;; esac
python3 - "$ROOT" <<'PYTEST'
import hashlib,importlib.util,json,os,shutil,stat,subprocess,sys,tempfile
from pathlib import Path
root=Path(sys.argv[1])
def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
adopt=module('adoption',root/'.claude/scripts/factory-adopt.py')
def git(path,*args):return subprocess.check_output(['git','-C',str(path),*args],text=True,stderr=subprocess.DEVNULL,env={**os.environ,'GIT_CONFIG_GLOBAL':os.devnull,'GIT_CONFIG_NOSYSTEM':'1'}).strip()
def initialize(path):
 path.mkdir();git(path,'init','-b','main');git(path,'config','user.name','Fixture');git(path,'config','user.email','fixture@example.invalid')
def put(root,name,data):
 path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(data)
def snapshot(path):return {str(file.relative_to(path)):file.read_bytes() for file in path.rglob('*') if file.is_file() and '.git' not in file.relative_to(path).parts}
with tempfile.TemporaryDirectory(prefix='neutral intake adoption ') as tmp:
 base=Path(tmp).resolve();source=base/'source';initialize(source)
 # Capture current tracked package bytes, never HEAD-only or unrelated untracked/private data.
 task_files={'factory/request-intake.example.json','docs/FACTORY-REQUEST-INTAKE.md','.claude/scripts/test/factory-intake-adoption.sh'}
 tracked=set(subprocess.check_output(['git','-C',str(root),'ls-files','-z']).decode().split('\0'))-{''}
 selected={name for name in tracked if adopt.allowed(name)}|task_files
 for name in selected:
  origin=root/name;assert origin.is_file() and not origin.is_symlink(),name
  destination=source/name;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(origin,destination);destination.chmod(stat.S_IMODE(origin.stat().st_mode))
 # Synthetic exclusions prove the source package cannot import pilot or product authority.
 excluded=['factory/policy.json','.claude/state/private.json','.claude/memory/topics/private.md','specs/active/999-private.md','tasks/TASKS.md','.claude/settings.local.json','factory/private.sqlite']
 for name in excluded:put(source,name,'SOURCE-ONLY-PRIVATE-SENTINEL')
 git(source,'add','-f','.');git(source,'commit','-m','isolated current package image');source_sha=git(source,'rev-parse','HEAD');assert not git(source,'status','--porcelain')
 for name in task_files|{'.claude/scripts/factory-adopt.py'}:assert (source/name).read_bytes()==(root/name).read_bytes()
 target=base/'target';initialize(target)
 own={'README.md':'my product','.claude/memory/MEMORY.md':'my memory','tasks/TASKS.md':'my approved product tasks','.claude/state/owned.json':'my private state','.claude/settings.local.json':'my private settings'}
 for name,data in own.items():put(target,name,data)
 git(target,'add','.');git(target,'commit','-m','target product state');before=snapshot(target)
 home=base/'home';home.mkdir();audit=base/'audit';audit.mkdir();log=base/'audit.log'
 # The actual adopter subprocess may only issue local read-only Git commands. No installed script runs.
 (audit/'sitecustomize.py').write_text("""import os,sys
from pathlib import Path
def guard(event,args):
 if event=='subprocess.Popen':
  command=args[1]
  with open(os.environ['ADOPTION_AUDIT'],'a') as out:out.write(str(command)+'\\n')
  assert isinstance(command,(list,tuple)) and Path(command[0]).name=='git' and command[1]=='-C' and command[3] in {'rev-parse','status','ls-files'},'unexpected subprocess during adoption'
 if event in {'socket.connect','socket.connect_ex','os.system','os.posix_spawn','os.exec'}:raise AssertionError('external effect during adoption')
sys.addaudithook(guard)
""")
 env={'PATH':os.environ['PATH'],'HOME':str(home),'PYTHONPATH':str(audit),'PYTHONDONTWRITEBYTECODE':'1','ADOPTION_AUDIT':str(log),'GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':os.devnull,'GIT_TERMINAL_PROMPT':'0'}
 state=base/'journal';command=[sys.executable,str(source/'.claude/scripts/factory-adopt.py'),'--from',str(source),'--into',str(target),'--state-root',str(state)]
 process=subprocess.run(command,env=env,text=True,capture_output=True,timeout=60)
 assert process.returncode==0,(process.stdout,process.stderr)
 result=json.loads(process.stdout);assert result['source_sha']==source_sha and result['activation_enabled'] is False and not process.stderr
 expected=task_files|{'.claude/scripts/factory-intake.py','.claude/scripts/factory-intake-scout.py','.claude/scripts/factory-intake-console.py','.claude/hooks/request-intake.sh','.claude/hooks/pre-intake-action.sh','.claude/hooks/post-intake-action.sh'}
 manifest=json.loads((target/adopt.MANIFEST).read_text())
 for name in expected:
  assert (target/name).is_file(),'neutral intake package omitted '+name
  assert (target/name).read_bytes()==(source/name).read_bytes()
  entry=manifest['files'][name];assert entry=={'sha256':hashlib.sha256((source/name).read_bytes()).hexdigest(),'mode':stat.S_IMODE((source/name).stat().st_mode)}
 print('AC-14: actual CLI packages current immutable intake scripts, hooks, neutral example and guide with exact ownership hashes/modes')
 core=module('installed_intake',target/'.claude/scripts/factory-intake.py');neutral=json.loads((target/'factory/request-intake.example.json').read_text());core.validate_contract(neutral)
 assert neutral['enabled'] is False and neutral['trusted_files']=={} and all(neutral[name] is None for name in core.CONTRACT_FIELDS-{'schema_version','enabled','trusted_files','limits'})
 assert neutral['limits']==core.DEFAULT_LIMITS
 feedback=json.loads((target/'factory/feedback.example.json').read_text());assert feedback['enabled'] is feedback['feedback_enabled'] is False and 'intake_config' not in feedback
 core.HostedSlackIntake.validate_assessment_policy({'enabled':False,'dataflow':None,'profile_sha256':None,'trusted_files':{},'limits':core.DEFAULT_LIMITS})
 for name,data in before.items():assert (target/name).read_bytes()==data,'target-owned state changed: '+name
 for name in excluded:
  if name not in own:assert not (target/name).exists(),name
 assert not any(b'SOURCE-ONLY-PRIVATE-SENTINEL' in content for name,content in snapshot(target).items() if not name.startswith('.claude/scripts/test/'))
 settings=json.loads((target/'.claude/settings.json').read_text());hooks=json.dumps(settings['hooks'])
 assert all(name not in hooks for name in ['request-intake.sh','pre-intake-action.sh','post-intake-action.sh'])
 assert not list(home.iterdir()) and log.read_text() and not (target/'.claude/factory-installations.json').exists()
 assert all(not name.endswith(('.sqlite','.db','.key','.pem')) for name in snapshot(target))
 assert state.stat().st_mode&0o777==0o700 and len(list(state.glob('*.json')))==1
 assert all(path.stat().st_mode&0o777==0o600 for path in state.glob('*.json'))
 print('AC-14: disabled schema validates, feedback intake stays absent, adopter state survives, no private source/keys/DB/registry imported, and audited CLI performs only local Git reads')
PYTEST
