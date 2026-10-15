#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
# AC-6, AC-7, AC-9, AC-11: required installation and direct enqueue boundaries.
import copy,hashlib,importlib.util,json,os,sys,tempfile,time,subprocess,sqlite3,pwd,fcntl,stat,shutil
from unittest.mock import patch
from contextlib import contextmanager
from pathlib import Path
root=Path(sys.argv[1])
def module(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('intake_scout',root/'.claude/scripts/factory-intake-scout.py');r=module('profile_routing',root/'.claude/scripts/factory-routing.py')
core=module('intake_outcome',root/'.claude/scripts/factory-intake.py')
ledger=module('guarded_ledger',root/'.claude/scripts/factory-ledger.py')
def reject(fn):
 try:fn()
 except (ValueError,OSError,KeyError,TypeError,sqlite3.Error):return
 raise AssertionError('hostile assessor profile accepted')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory() as d:
 base=Path(d).resolve();private=base/'private';private.mkdir(mode=0o700);fake_home=base/'os-account';fake_home.mkdir(mode=0o700);patch('pwd.getpwuid',return_value=type('Account',(),{'pw_dir':str(fake_home)})).start();candidate=base/'candidate';candidate.mkdir()
 binary=private/'native';binary.write_text('#!/bin/sh\ntouch '+str(private/'executed')+'\nexit 99\n');binary.chmod(0o700)
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
 if hook.exists():pins.append(hook)
 for name in ('request-intake.sh','pre-intake-action.sh'):
  shim=root/'.claude/hooks'/name
  if shim.exists():pins.append(shim)
 for p in pins:
  if p not in [policy_path,config]:profile['runtimes']['primary']['probe']['trusted_files'][str(p)]=sha(p)
 save();policy['runtime']['routing_profile_sha256']=hashlib.sha256(r.canonical(profile).encode()).hexdigest();policy_path.write_text(json.dumps(policy))
 contract={'schema_version':1,'enabled':True,'repository':'fixture/intake','candidate_root':str(candidate),'authority_root':str(authority),'database':str(private/'runtime.sqlite'),'profile':str(config),'policy':str(policy_path),'trusted_files':{str(p):sha(p) for p in pins},'limits':{'request_chars':20000,'context_bytes':500000,'output_bytes':65536,'assessment_seconds':1}}
 intake_config=private/'intake.json';intake_config.write_text(json.dumps(contract));intake_config.chmod(0o600)
 closure=private/'pinned-controller-helper';closure.write_text('trusted controller closure')
 contract['trusted_files'][str(closure)]=sha(closure);intake_config.write_text(json.dumps(contract))
 store=core.Intake(intake_config);session=store.new_session()
 def request(text='new feature',head=ref):return store.submit_console(session,text,head)['request_id']
 # AC-6, AC-9, AC-11: real Read hook subprocess and disclosure boundary.
 bound=request('continue T-1');store.lightweight(bound);store.enqueue_task(bound);start_id,_=store.start_intent(bound,'T-1')
 supervisor=module('read_supervisor',root/'.claude/scripts/factory-supervisor.py');supervisor.claim_intake(store,start_id,300)
 descriptor=supervisor.prepare_intake_worker(store,start_id);doc=json.loads(Path(descriptor).read_text())
 submit={'hook_event_name':'UserPromptSubmit','session_id':doc['native_session'],'cwd':doc['cwd'],'prompt':doc['prompt']}
 def invoke(payload,event='PreToolUse',arguments=None):
  cmd=arguments if arguments is not None else [str(driver),'-I','-S',str(hook),'--descriptor',str(descriptor),'--event',event]
  return subprocess.run(cmd,input=json.dumps(payload),text=True,capture_output=True,cwd=doc['cwd'],env={'PATH':'/usr/bin:/bin','HOME':str(private),'LANG':'C','LC_ALL':'C'},timeout=15)
 assert invoke(submit,'UserPromptSubmit').returncode==0
 read={'hook_event_name':'PreToolUse','session_id':doc['native_session'],'cwd':doc['cwd'],'tool_name':'Read','tool_use_id':'read-1','tool_input':{'file_path':str(candidate/'src/a.txt')}}
 assert invoke(read).returncode==2,'claimed stage admitted tool'
 store.begin_implementation(start_id,doc['owner'],doc['fence'])
 result=invoke(read);assert result.returncode==0,result.stderr
 decision=json.loads(result.stdout);assert decision['hookSpecificOutput']['permissionDecision']=='allow'
 shim=root/'.claude/hooks/pre-intake-action.sh';assert invoke(read,arguments=['/bin/bash',str(shim),str(driver),str(hook),str(descriptor)]).returncode==0
 for name in ['Bash','Agent','Glob','Grep','Write','Edit','mcp__fixture__read','Unknown']:
  assert invoke({**read,'tool_name':name}).returncode==2,name
 for name in [str(candidate/'src/uncited.txt'),str(candidate/'.env'),str(candidate/'.git/config'),str(private/'policy.json'),str(authority/'specs/active/001-a.md'),'src/a.txt',str(candidate/'src/../src/a.txt')]:
  assert invoke({**read,'tool_input':{'file_path':name}}).returncode==2,name
 for change in [{'session_id':'foreign'},{'cwd':str(candidate)},{'run_in_background':True},{'agent_id':'subagent'},{'agent_type':'general-purpose'},{'background':True},{'unknown_callback':True},{'tool_input':{'file_path':str(candidate/'src/a.txt'),'unknown':'x'}},{'tool_input':{'file_path':str(candidate/'src/a.txt'),'offset':True}},{'tool_use_id':None}]:assert invoke({**read,**change}).returncode==2
 invalid=invoke(read,arguments=[str(driver),'-I','-S',str(hook),'--bad']);assert invalid.returncode==2
 logic=module('read_hook_logic',hook);original_doc=Path(descriptor).read_bytes();original_sha=sha(Path(descriptor))
 for change in [{'prompt':doc['prompt']+'malformed'},{'task':'T-2'},{'worker_guard_sha256':'0'*64}]:
  malformed={**doc,**change};encoded=json.dumps(malformed,sort_keys=True,separators=(',',':'),ensure_ascii=False)
  Path(descriptor).write_text(encoded)
  with store.transaction() as db:db.execute('UPDATE intake_worker_descriptors SET document=?,sha256=? WHERE start_id=?',(encoded,hashlib.sha256(encoded.encode()).hexdigest(),start_id))
  reject(lambda:logic.validate_descriptor(store,descriptor))
  with store.transaction() as db:assert db.execute('SELECT state FROM intake_worker_descriptors WHERE start_id=?',(start_id,)).fetchone()[0]=='unknown','malformed immutable binding treated as temporary authority denial'
  Path(descriptor).write_bytes(original_doc)
  with store.transaction() as db:db.execute("UPDATE intake_worker_descriptors SET document=?,sha256=?,state='consumed' WHERE start_id=?",(original_doc.decode(),original_sha,start_id))
 mutation=store.mutation_intent(bound,start_id,doc['owner'],doc['fence'],'src/output.txt','task output only')
 assert invoke(read).returncode==2,'pending write did not fence Read'
 with store.transaction() as db:assert db.execute('SELECT state FROM intake_worker_descriptors WHERE start_id=?',(start_id,)).fetchone()[0]=='consumed','pending effect poisoned intact descriptor'
 store.apply_mutation(mutation,doc['owner'],doc['fence'])
 output=invoke({**read,'tool_input':{'file_path':str(candidate/'src/output.txt')}});assert output.returncode==0,output.stderr
 marker=candidate/'src/a.txt';original=marker.read_text();marker.write_text('changed context');assert invoke(read).returncode==2
 assert not (private/'executed').exists(),'Read guard invoked native executable'
 print('tool-read: real implementing claim and consumed submit, selected disclosure/exact task outputs only; unselected/control/private/changed data and unsupported tools reject; pending effects fence')
PY
