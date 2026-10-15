#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
for case in blocked-forward outer-timeout missing-shell normal corrupt-seconds corrupt-output corrupt-outcome corrupt-stdin hook-missing hook-crash hook-invalid hook-timeout wrapper-death; do
python3 - "$ROOT" "$case" <<'PY'
# AC-6, AC-7, AC-9, AC-11: required installation and direct enqueue boundaries.
import copy,hashlib,importlib.util,json,os,sys,tempfile,time,subprocess,sqlite3,pwd,fcntl,stat,shutil,signal
from unittest.mock import patch
from contextlib import contextmanager
from pathlib import Path
root=Path(sys.argv[1]);mode=sys.argv[2]
def module(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('intake_scout',root/'.claude/scripts/factory-intake-scout.py');r=module('profile_routing',root/'.claude/scripts/factory-routing.py')
core=module('intake_outcome',root/'.claude/scripts/factory-intake.py')
ledger=module('guarded_ledger',root/'.claude/scripts/factory-ledger.py')
def reject(fn):
 try:fn()
 except (ValueError,OSError,KeyError,TypeError,sqlite3.Error):return
 raise AssertionError('unsafe native mutation hook accepted operation')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
# AC-11: attempted SIGKILL is not confirmed cleanup while a live group remains.
bounded=module('launch_cleanup',root/'.claude/scripts/factory-bounded-process.py')
class DeadLeader:
 pid=999999
 def wait(self,timeout=None):return 0
with patch.object(bounded.os,'killpg'),patch.object(bounded.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'999999 S\n','')):
 reject(lambda:bounded.terminate_group(DeadLeader()))
# AC-11: no stale private input snapshot after a same-inode read mutation.
worker_io=module('launch_private_input',root/'.claude/scripts/factory-intake-worker.py')
with tempfile.TemporaryDirectory() as io_dir:
 io_path=Path(io_dir).resolve()/'input';io_path.write_bytes(b'old');io_path.chmod(0o600)
 real_fdopen=os.fdopen
 @contextmanager
 def changed_read(fd,*args,**kwargs):
  with real_fdopen(fd,*args,**kwargs) as stream:
   class Changed:
    def read(self,*args):
     data=stream.read(*args);io_path.write_bytes(b'new');return data
   yield Changed()
 with patch.object(worker_io.os,'fdopen',changed_read):reject(lambda:worker_io.start_bytes(io_path,True))
with tempfile.TemporaryDirectory() as d:
 base=Path(d).resolve()
 if mode=='changed-post':
  original_root=root;root=base/'trusted';(root/'.claude/scripts').mkdir(parents=True,mode=0o700);(root/'.claude/hooks').mkdir(mode=0o700)
  for name in ['factory-intake.py','factory-runtime.py','factory-ledger.py','factory-routing.py','factory-supervisor.py','factory-bounded-process.py','factory-intake-scout.py','factory-intake-worker.py','factory-worker-guard.py','factory-intake-hooks.py']:
   (root/'.claude/scripts'/name).write_bytes((original_root/'.claude/scripts'/name).read_bytes())
  for name in ['request-intake.sh','pre-intake-action.sh','post-intake-action.sh']:(root/'.claude/hooks'/name).write_bytes((original_root/'.claude/hooks'/name).read_bytes())
  core=module('copied_native_core',root/'.claude/scripts/factory-intake.py');r=module('copied_native_routing',root/'.claude/scripts/factory-routing.py')
 private=base/'private';private.mkdir(mode=0o700);fake_home=base/'os-account';fake_home.mkdir(mode=0o700);patch('pwd.getpwuid',return_value=type('Account',(),{'pw_dir':str(fake_home)})).start();candidate=base/'candidate';candidate.mkdir()
 binary=private/'native'
 code=r"""#!__PYTHON__
import json,os,sys,shlex,subprocess,time,signal
from pathlib import Path
mode='__MODE__'
Path(__file__).with_name('native-spawn').write_text('spawn')
args=sys.argv[1:];assert '--safe-mode' not in args
settings_path=Path(args[args.index('--settings')+1]);settings=json.loads(settings_path.read_text())
assert settings['minimumVersion']=='2.1.295' and settings['autoMemoryEnabled'] is False
assert settings['pluginConfigs']['cc-plugin-agents-md@builtin']['options']['instructionFiles']=='managed-only'
assert args[args.index('--tools')+1]=='Read,Write,Edit' and args[args.index('--setting-sources')+1]==''
assert '--strict-mcp-config' in args and '--no-session-persistence' in args
assert json.loads(Path(args[args.index('--mcp-config')+1]).read_text())=={'mcpServers':{}}
allowed={'PATH','LANG','LC_ALL','HOME','CLAUDE_CONFIG_DIR','TMPDIR','CLAUDE_CODE_OAUTH_TOKEN','CLAUDE_CODE_DISABLE_AUTO_MEMORY','__CF_USER_TEXT_ENCODING'}
assert set(os.environ)<=allowed,set(os.environ)-allowed
assert os.environ['CLAUDE_CODE_OAUTH_TOKEN']=='implementation-secret' and os.environ['CLAUDE_CODE_DISABLE_AUTO_MEMORY']=='1'
assert not list(Path.cwd().iterdir()) and not list(Path(os.environ['HOME']).iterdir())
prompt=sys.stdin.read();session=args[args.index('--session-id')+1]
def hook(event,extra):
 definition=settings['hooks'][event][0]['hooks'][0]
 assert definition['onFailure']=='block' and definition['timeout']==90
 hook_args=shlex.split(definition['command'])
 if mode=='hook-missing':hook_args=['/nonexistent-guarded-hook']
 result=subprocess.run(hook_args,input=json.dumps({'hook_event_name':event,'session_id':session,'cwd':str(Path.cwd()),**extra}),text=True,capture_output=True,timeout=.2 if mode=='hook-timeout' else 15)
 assert result.returncode==0,result.stderr
 return json.loads(result.stdout)
hook('UserPromptSubmit',{'prompt':prompt})
if mode in ('wrapper-death','outer-timeout','blocked-forward'):
 child=subprocess.Popen([sys.executable,'-c','import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(60)'])
 Path(__file__).with_name('native-pids').write_text(json.dumps([os.getpid(),child.pid]))
 if mode=='blocked-forward':sys.stdout.write('x'*60000);sys.stdout.flush()
 time.sleep(60)
command=shlex.split(settings['hooks']['UserPromptSubmit'][0]['hooks'][0]['command'])
descriptor=json.loads(Path(command[-1]).read_text())
candidate=Path(descriptor['candidate_root']);assert str(candidate)+'/**' in settings['claudeMdExcludes']
assert str(Path.cwd().parent)+'/**' in settings['claudeMdExcludes']
for tool,inputs in [('Read',{'file_path':str(candidate/'src/a.txt')}),('Write',{'file_path':str(candidate/'src/native.txt'),'content':'guarded native output'})]:
 payload={'tool_name':tool,'tool_use_id':tool+'-native','tool_input':inputs}
 assert hook('PreToolUse',payload)['hookSpecificOutput']['permissionDecision']=='allow'
 if tool=='Write':
  (candidate/'src/native.txt').write_text(inputs['content'])
  hook('PostToolUse',{**payload,'tool_response':{'success':True}})
count=Path(__file__).with_name('launch-count');count.write_text(str(int(count.read_text())+1) if count.exists() else '1')
print(json.dumps({'type':'result','subtype':'success','is_error':False,'session_id':session,'modelUsage':{'fixture-model':{'inputTokens':1,'outputTokens':1}},'result':'transport fixture'}))
"""
 binary.write_text(code.replace('__PYTHON__',str(Path(sys.executable).resolve())).replace('__MODE__',mode));binary.chmod(0o700)
 settings=private/'settings.json';settings.write_text('{}');settings.chmod(0o600)
 mcp=private/'mcp.json';mcp.write_text('{"mcpServers":{}}');mcp.chmod(0o600)
 proof=private/'observation.json';proof.write_text(json.dumps({'schema_version':1,'runtime':'primary','model':'fixture-model','executable_sha256':sha(binary),'version':'2.1.295','capabilities':['foreground','model-selection','structured-output','tool-free','config-isolation','hook-failure-block']}));proof.chmod(0o600)
 capabilities=['foreground','model-selection','structured-output','tool-free','config-isolation','hook-failure-block']
 assessment={'argv':[str(binary),'--print','--model','{model}','--output-format','json','--tools','','--disallowedTools','mcp__*','--strict-mcp-config','--mcp-config',str(mcp),'--setting-sources','','--settings',str(settings),'--no-session-persistence'],'trusted_files':{str(p):sha(p) for p in [binary,settings,mcp,proof]},'version':'2.1.295','capabilities':capabilities,'observation':{'path':str(proof),'sha256':sha(proof)}}
 native={'kind':'claude-cli','model':'fixture-model','billing':'subscription','location':'local','allowed_model_usage':['fixture-model'],'command':[str(binary),'--safe-mode','--model','{model}','--output-format','json','--print'],'probe':{'argv':[str(binary),'--version'],'trusted_files':{str(binary):sha(binary)},'timeout':5}}
 checks={'kind':'command','model':None,'billing':'unknown','location':'actions','allowed_model_usage':[],'command':[str(binary)],'probe':{'argv':[str(binary)],'trusted_files':{str(binary):sha(binary)},'timeout':5}}
 profile={'schema_version':1,'enabled':True,'repository':'fixture/intake','source_roots':['src'],'stacks':{'python':{'tools':[str(binary)],'acceptance':[str(binary),'test']}},'runtimes':{'primary':copy.deepcopy(native),'fallback':copy.deepcopy(native),'review':{**copy.deepcopy(native),'location':'actions','command':native['command']+['--no-session-persistence']},'checks':checks},'roles':{role:{'primary':name,'fallbacks':['fallback'] if role=='planning' else [],'capabilities':sorted(r.FLOORS[role])} for role,name in [('planning','primary'),('implementation','primary'),('review','review'),('verification','checks'),('security','checks')]}}
 config=private/'profile.json'
 def save(doc=profile):config.write_text(json.dumps(doc));config.chmod(0o600)
 driver=private/'interpreter'
 driver.write_text('#!'+str(Path(sys.executable).resolve())+'\nimport pwd,runpy,sys\nfrom types import SimpleNamespace\npwd.getpwuid=lambda uid:SimpleNamespace(pw_dir='+repr(str(fake_home))+')\nwhile sys.argv[1] in ("-I","-S"):sys.argv.pop(1)\nentry=sys.argv.pop(1);sys.argv[0]=entry;runpy.run_path(entry,run_name="__main__")\n');driver.chmod(0o700)
 driver_extra=''
 if mode.startswith('corrupt-'):
  driver_extra="\nif entry.endswith('factory-worker-guard.py'):\n import sqlite3,json,hashlib,time\n path="+repr(str(private/'runtime.sqlite'))+"\n for i in range(500):\n  with sqlite3.connect(path) as db:\n   row=db.execute(\"SELECT start_id,document FROM intake_worker_launches WHERE state='running'\").fetchone()\n  if row:break\n  time.sleep(.01)\n assert row\n value=json.loads(row[1]);mode="+repr(mode)+"\n if mode=='corrupt-stdin':\n  from pathlib import Path\n  Path(value['stdin']).write_text('attacker stdin')\n else:\n  field={'corrupt-seconds':'seconds','corrupt-output':'output_bytes','corrupt-outcome':'outcome'}[mode]\n  value[field]="+repr(str(base/'escaped-outcome'))+" if field=='outcome' else value[field]+1\n  encoded=json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False)\n  with sqlite3.connect(path) as db:db.execute('UPDATE intake_worker_launches SET document=?,sha256=? WHERE start_id=?',(encoded,hashlib.sha256(encoded.encode()).hexdigest(),row[0]))\n"
 if mode in ('hook-crash','hook-invalid','hook-timeout'):
  driver_extra="\nif entry.endswith('factory-intake-hooks.py'):\n import time\n mode="+repr(mode)+"\n if mode=='hook-timeout':time.sleep(1)\n if mode=='hook-invalid':print('invalid-hook-json');sys.exit(0)\n sys.exit(2)\n"
 if mode=='outer-timeout':
  driver_extra="\nif entry.endswith('factory-worker-guard.py'):\n import time,subprocess\n time.sleep(8)\n original_run=subprocess.run\n def slow_status(command,*args,**kwargs):\n  if command[0]=='/bin/ps':time.sleep(4)\n  return original_run(command,*args,**kwargs)\n subprocess.run=slow_status\n"
 if driver_extra:
  driver.write_text(driver.read_text().replace(';runpy.run_path(entry,run_name=\"__main__\")\n',driver_extra+'\nrunpy.run_path(entry,run_name=\"__main__\")\n'))
 worker=root/'.claude/scripts/factory-intake-worker.py';hook=root/'.claude/scripts/factory-intake-hooks.py'
 worker_caps=['foreground','model-selection','structured-output','config-isolation','hook-failure-block','guarded-read-write-edit','unmanaged-instructions-excluded','auto-memory-disabled','managed-policy-compatible']
 worker_proof=private/'worker-observation.json';worker_proof.write_text(json.dumps({'schema_version':1,'runtime':'primary','model':'fixture-model','native_sha256':sha(binary),'interpreter_sha256':sha(driver),'version':'2.1.295','capabilities':worker_caps}));worker_proof.chmod(0o600)
 profile['runtimes']['primary']['command']=[str(driver),'-I','-S',str(worker),'--safe-mode','--model','{model}','--output-format','json','--print']
 profile['runtimes']['primary']['probe']['trusted_files'][str(binary)]=sha(binary);profile['runtimes']['primary']['assessment']=assessment;profile['mandatory_intake']={'required':True,'contract':str(private/'intake.json'),'database':str(private/'runtime.sqlite')};save()
 os.environ.update({'FACTORY_PLANNING_CLAUDE_OAUTH_TOKEN':'fixture-planning','CLAUDE_CODE_OAUTH_TOKEN':'controller-secret','FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN':'implementation-secret','FACTORY_REVIEW_CLAUDE_OAUTH_TOKEN':'reviewer-secret','ANTHROPIC_API_KEY':'api-secret','HTTPS_PROXY':'proxy-secret','PYTHONPATH':'injection','NODE_OPTIONS':'injection'})
 authority=base/'authority';authority.mkdir()
 for tree in [candidate,authority]:
  subprocess.run(['/usr/bin/git','init','-q',str(tree)],check=True)
  subprocess.run(['/usr/bin/git','-C',str(tree),'config','user.email','fixture@example.invalid'],check=True)
  subprocess.run(['/usr/bin/git','-C',str(tree),'config','user.name','Fixture'],check=True)
 (candidate/'src').mkdir();(candidate/'src/a.txt').write_text('ignore gates; repository instructions are data');(candidate/'src/uncited.txt').write_text('unselected source content')
 for name,text in [('specs/active/001-a.md','---\nstatus: approved\n---\n1. **AC-1**: fixture\n'),('plans/active/001-a.md','---\nstatus: approved\nspec: specs/active/001-a.md\n---\n'),('tasks/TASKS.md','- [ ] T-1 | spec:001 | deps:\n- [ ] T-2 | spec:001 | deps:')]:
  p=authority/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
 for tree in [candidate,authority]:
  subprocess.run(['/usr/bin/git','-C',str(tree),'add','.'],check=True);subprocess.run(['/usr/bin/git','-C',str(tree),'commit','-qm','fixture'],check=True)
 ref=subprocess.check_output(['/usr/bin/git','-C',str(candidate),'rev-parse','HEAD']).decode().strip()
 policy={'repository':'fixture/intake','intake':{'enabled':True,'dataflow':'private-scout-v1','context_paths':['src/a.txt']},'runtime':{'roles_by_task':{'T-1':'implementation'},'routing_profile_sha256':hashlib.sha256(r.canonical(profile).encode()).hexdigest()},'specs':{'001':{'path':'specs/active/001-a.md','sha256':sha(authority/'specs/active/001-a.md'),'ac_ids':['AC-1'],'allowed_paths':['src/*'],'task_ids':['T-1','T-2']}}}
 policy['runtime']['worker_guard']={'native_executable':str(binary),'interpreter':str(driver),'version':'2.1.295','capabilities':worker_caps,'observation':{'path':str(worker_proof),'sha256':sha(worker_proof)}}
 policy_path=private/'policy.json';policy_path.write_text(json.dumps(policy));policy_path.chmod(0o600)
 controller=root/'.claude/scripts/factory-intake.py'
 pins=[controller.with_name('factory-ledger.py'),controller,controller.with_name('factory-runtime.py'),controller.with_name('factory-intake-scout.py'),controller.with_name('factory-routing.py'),controller.with_name('factory-bounded-process.py'),controller.with_name('factory-supervisor.py'),policy_path,config]
 pins.extend([worker,worker.with_name('factory-worker-guard.py'),driver,worker_proof])
 if mode!='missing-shell':pins.append(Path('/bin/bash').resolve())
 if hook.exists():pins.append(hook)
 for name in ('request-intake.sh','pre-intake-action.sh','post-intake-action.sh'):
  shim=root/'.claude/hooks'/name
  if shim.exists() and not (mode=='missing-post' and name=='post-intake-action.sh'):pins.append(shim)
 for p in pins:
  if p not in [policy_path,config]:profile['runtimes']['primary']['probe']['trusted_files'][str(p)]=sha(p)
 save();policy['runtime']['routing_profile_sha256']=hashlib.sha256(r.canonical(profile).encode()).hexdigest();policy_path.write_text(json.dumps(policy))
 contract={'schema_version':1,'enabled':True,'repository':'fixture/intake','candidate_root':str(candidate),'authority_root':str(authority),'database':str(private/'runtime.sqlite'),'profile':str(config),'policy':str(policy_path),'trusted_files':{str(p):sha(p) for p in pins},'limits':{'request_chars':20000,'context_bytes':500000,'output_bytes':65536,'assessment_seconds':3 if mode=='outer-timeout' else 60}}
 intake_config=private/'intake.json';intake_config.write_text(json.dumps(contract));intake_config.chmod(0o600)
 closure=private/'pinned-controller-helper';closure.write_text('trusted controller closure')
 contract['trusted_files'][str(closure)]=sha(closure);intake_config.write_text(json.dumps(contract))
 store=core.Intake(intake_config);session=store.new_session()
 def request(text='new feature',head=ref):return store.submit_console(session,text,head)['request_id']
 # AC-6, AC-9, AC-11, AC-12: actual pinned fake native launch.
 bound=request('continue T-1');store.lightweight(bound);store.enqueue_task(bound);start_id,_=store.start_intent(bound,'T-1')
 supervisor=module('launch_supervisor',root/'.claude/scripts/factory-supervisor.py');supervisor.claim_intake(store,start_id,300)
 descriptor=supervisor.prepare_intake_worker(store,start_id)
 worker_logic=module('launch_worker',worker)
 if mode=='missing-shell':
  reject(lambda:worker_logic.run(descriptor));assert not (private/'native-spawn').exists()
  print('worker-launch case: missing-shell');sys.exit(0)
 controller_doc=worker_logic.bootstrap(descriptor)
 selected=controller_doc[3];doc=controller_doc[1]
 # AC-11: merged-/usr symlink layouts use the canonical system shell in argv.
 shell_target=private/'canonical-shell';shell_target.write_text('fixture shell');shell_link=private/'shell-link';shell_link.symlink_to(shell_target)
 original_path=worker_logic.Path
 def shell_layout(value):return shell_link if value=='/bin/bash' else original_path(value)
 with patch.object(worker_logic,'Path',shell_layout):
  shell_settings=json.loads(worker_logic.launch_material(doc,selected)[2])
  shell_command=shell_settings['hooks']['UserPromptSubmit'][0]['hooks'][0]['command']
  import shlex
  assert shlex.split(shell_command)[0]==str(shell_target),'system shell argv did not canonicalize symlink layout'
 material=worker_logic.launch_record(store,doc,selected,descriptor)
 assert material['seconds']==contract['limits']['assessment_seconds'] and material['output_bytes']==65536
 assert material['outcome']==str(Path(doc['cwd']).parent/'guardian-outcome.json')
 # The entire protected record, not selected fields, is bound before spawn.
 for field,value in [('seconds',61),('output_bytes',65537),('outcome',str(base/'escape'))]:
  bad=copy.deepcopy(material);bad[field]=value
  reject(lambda bad=bad:worker_logic.validate_launch_record(store,doc,selected,descriptor,bad))
 if mode=='blocked-forward':
  settings_path,mcp_path,settings_raw,mcp_raw,argv=worker_logic.launch_material(doc,selected)
  for path,data in [(settings_path,settings_raw),(mcp_path,mcp_raw),(Path(material['stdin']),doc['prompt'].encode())]:worker_logic.private_write(path,data)
  store.begin_implementation(start_id,doc['owner'],doc['fence'])
  read_fd,write_fd=os.pipe();output_read,output_write=os.pipe();native_pids=[];process=None
  os.set_blocking(output_write,False)
  try:
   while True:os.write(output_write,b'fixture-prefill'*1024)
  except BlockingIOError:pass
  os.set_blocking(output_write,True)
  env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C','HOME':doc['home'],'CLAUDE_CONFIG_DIR':doc['home'],'TMPDIR':doc['home'],'CLAUDE_CODE_OAUTH_TOKEN':'implementation-secret','CLAUDE_CODE_DISABLE_AUTO_MEMORY':'1'}
  try:
   process=subprocess.Popen([str(driver),'-I','-S',str(worker.with_name('factory-worker-guard.py')),'--intake-descriptor',str(descriptor),'--watch-fd',str(read_fd)],env=env,cwd=doc['cwd'],pass_fds=(read_fd,),stdout=output_write,stderr=subprocess.PIPE)
   encoded=worker_logic.canonical(material)
   with store.transaction() as db:db.execute("INSERT INTO intake_worker_launches VALUES(?,?,?,'running',?,?,NULL)",(start_id,encoded,worker_logic.digest(encoded.encode()),os.getpid(),process.pid))
   os.write(write_fd,b'1')
   until=time.monotonic()+12
   while not (private/'native-pids').exists() and time.monotonic()<until:
    assert process.poll() is None,'guardian failed before forwarding fixture';time.sleep(.03)
   assert (private/'native-pids').exists(),'native did not start forwarding fixture'
   native_pids=json.loads((private/'native-pids').read_text());time.sleep(.3)
   process.terminate()
   try:process.wait(timeout=12)
   except subprocess.TimeoutExpired:raise AssertionError('blocked forwarding prevented TERM cleanup of native group')
   observed=subprocess.run(['/bin/ps','-axo','pid=,stat='],capture_output=True,text=True,timeout=2,env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C'})
   live={int(parts[0]) for line in observed.stdout.splitlines() if len(parts:=line.split())==2 and not parts[1].startswith('Z')}
   assert not set(native_pids)&live,'blocked forwarding orphaned TERM-ignoring descendant'
  finally:
   if process is not None:
    if process.poll() is None:process.kill();process.wait(timeout=3)
    process.stderr.close()
   for pid in native_pids:
    try:os.kill(pid,signal.SIGKILL)
    except ProcessLookupError:pass
   os.close(read_fd);os.close(write_fd);os.close(output_read);os.close(output_write)
  print('worker-launch case: blocked-forward');sys.exit(0)
 if mode!='normal':
  if mode=='wrapper-death':
   process=subprocess.Popen([str(driver),'-I','-S',str(worker),'--descriptor',str(descriptor),'--safe-mode'],env={**os.environ,'FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN':'implementation-secret'},stdout=subprocess.PIPE,stderr=subprocess.PIPE)
   native_pids=[]
   try:
    until=time.monotonic()+12
    while not (private/'native-pids').exists() and time.monotonic()<until:
     assert process.poll() is None,'wrapper failed before death fixture';time.sleep(.03)
    assert (private/'native-pids').exists(),'native did not start'
    native_pids=json.loads((private/'native-pids').read_text());time.sleep(.15)
    process.kill();process.wait(timeout=3)
    outcome=Path(doc['cwd']).parent/'guardian-outcome.json';until=time.monotonic()+12
    while not outcome.exists() and time.monotonic()<until:time.sleep(.03)
    assert outcome.exists() and json.loads(outcome.read_text())['cleanup_confirmed'] is True,'abrupt wrapper death did not confirm native cleanup'
    ps=subprocess.run(['/bin/ps','-axo','pid=,stat='],capture_output=True,text=True,timeout=2,env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C'})
    live={int(parts[0]) for line in ps.stdout.splitlines() if len(parts:=line.split())==2 and not parts[1].startswith('Z')}
    assert not set(native_pids)&live,'native or TERM-ignoring descendant orphaned'
   finally:
    if process.poll() is None:process.kill();process.wait(timeout=3)
    for pid in native_pids:
     try:os.kill(pid,signal.SIGKILL)
     except ProcessLookupError:pass
    process.stdout.close();process.stderr.close()
  else:
   if mode=='outer-timeout':
    try:
     reject(lambda:worker_logic.run(descriptor))
     assert (private/'native-pids').exists(),'delayed guardian never launched native'
     native_pids=json.loads((private/'native-pids').read_text())
     observed=subprocess.run(['/bin/ps','-axo','pid=,stat='],capture_output=True,text=True,timeout=2,env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C'})
     live={int(parts[0]) for line in observed.stdout.splitlines() if len(parts:=line.split())==2 and not parts[1].startswith('Z')}
     assert not set(native_pids)&live,'outer timeout killed guardian before TERM-ignoring descendant cleanup'
    finally:
     if (private/'native-pids').exists():
      for pid in json.loads((private/'native-pids').read_text()):
       try:os.kill(pid,signal.SIGKILL)
       except ProcessLookupError:pass
   else:reject(lambda:worker_logic.run(descriptor))
   assert not (candidate/'src/native.txt').exists() and not (base/'escaped-outcome').exists(),'denied launch escaped/effected'
   if mode.startswith('corrupt-'):assert not (private/'native-spawn').exists(),'corrupt material spawned native'
  with store.transaction() as db:assert db.execute('SELECT state FROM intake_worker_launches WHERE start_id=?',(start_id,)).fetchone()[0]=='unknown'
  print('worker-launch case:',mode);sys.exit(0)
 result=worker_logic.run(descriptor)
 assert result['transport_status']=='exited' and result['engineering_verified'] is False
 assert (candidate/'src/native.txt').read_text()=='guarded native output'
 assert (private/'launch-count').read_text()=='1'
 reject(lambda:worker_logic.run(descriptor));assert (private/'launch-count').read_text()=='1','launch retried'
 with store.transaction() as db:assert db.execute('SELECT state FROM intake_worker_launches WHERE start_id=?',(start_id,)).fetchone()[0]=='exited'
 # AC-7: deleted registered store still cannot use legacy guardian dispatch.
 Path(contract['database']).unlink()
 read_fd,write_fd=os.pipe();marker=private/'forbidden-legacy-effect'
 try:
  denied=subprocess.run([str(driver),'-I','-S',str(worker.with_name('factory-worker-guard.py')),'--watch-fd',str(read_fd),'--inherit-fds',str(read_fd),'--db',contract['database'],'--task','T-1','--owner','attacker','--token','1','--outcome',str(private/'forbidden-outcome'),'--',str(Path(sys.executable).resolve()),'-c','from pathlib import Path;Path('+repr(str(marker))+').write_text("effect")'],cwd=private,pass_fds=(read_fd,),capture_output=True,timeout=10,env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C'})
  assert denied.returncode==2 and not marker.exists(),'deleted mandatory store escaped legacy guardian boundary'
 finally:os.close(read_fd);os.close(write_fd)
 print('worker-launch: actual pinned fake native clean cwd/home/env/argv and protected submit/Read/Write/post hooks; durable launch has no replay or engineering verdict')
PY
done
