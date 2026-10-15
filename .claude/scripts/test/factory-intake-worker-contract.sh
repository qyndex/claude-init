#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
# AC-5, AC-6, AC-9, AC-11, AC-12: pure protected contract validation.
import copy,hashlib,importlib.util,json,os,sys,tempfile
from unittest.mock import patch
from pathlib import Path
root=Path(sys.argv[1]);helper=root/'.claude/scripts/factory-intake-worker.py'
assert helper.is_file(), 'protected worker contract validator absent'
def module(name,path):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
m=module('worker_contract',helper);r=module('worker_routing',helper.with_name('factory-routing.py'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def reject(fn):
 try:fn()
 except (ValueError,OSError):return
 raise AssertionError('unsafe worker contract accepted')
with tempfile.TemporaryDirectory() as d:
 base=Path(d).resolve();private=base/'private';private.mkdir(mode=0o700)
 candidate=base/'candidate';candidate.mkdir();authority=base/'authority';authority.mkdir()
 native=private/'native';interpreter=private/'interpreter'
 for p in (native,interpreter):p.write_text('#!/bin/sh\ntouch '+str(private/'executed')+'\nexit 99\n');p.chmod(0o700)
 capabilities=['foreground','model-selection','structured-output','config-isolation','hook-failure-block','guarded-read-write-edit','unmanaged-instructions-excluded','auto-memory-disabled','managed-policy-compatible']
 proof=private/'worker-observation.json';guard={'native_executable':str(native),'interpreter':str(interpreter),'version':'2.1.295','capabilities':capabilities,'observation':{'path':str(proof),'sha256':''}}
 observed={'schema_version':1,'runtime':'primary','model':'fixture-model','native_sha256':sha(native),'interpreter_sha256':sha(interpreter),'version':guard['version'],'capabilities':capabilities}
 proof.write_text(json.dumps(observed));proof.chmod(0o600);guard['observation']['sha256']=sha(proof)
 closure=[helper.with_name(name) for name in ['factory-intake-worker.py','factory-intake.py','factory-runtime.py','factory-routing.py','factory-supervisor.py','factory-bounded-process.py','factory-worker-guard.py']]
 runtime_pins={str(p):sha(p) for p in closure+[native,interpreter,proof]}
 runtime={'kind':'claude-cli','model':'fixture-model','billing':'subscription','location':'local','allowed_model_usage':['fixture-model'],'command':[str(interpreter),'-I','-S',str(helper),'--safe-mode','--model','{model}','--output-format','json','--print'],'probe':{'argv':[str(native),'--version'],'trusted_files':runtime_pins,'timeout':5}}
 checks={'kind':'command','model':None,'billing':'unknown','location':'actions','allowed_model_usage':[],'command':[str(native)],'probe':{'argv':[str(native)],'trusted_files':{str(native):sha(native)},'timeout':5}}
 profile={'schema_version':1,'enabled':True,'repository':'fixture/intake','source_roots':['src'],'stacks':{'python':{'tools':[str(native)],'acceptance':[str(native),'test']}},'runtimes':{'primary':runtime,'fallback':copy.deepcopy(runtime),'review':{**copy.deepcopy(runtime),'location':'actions','command':runtime['command']+['--no-session-persistence']},'checks':checks},'roles':{role:{'primary':name,'fallbacks':[],'capabilities':sorted(r.FLOORS[role])} for role,name in [('planning','primary'),('implementation','primary'),('review','review'),('verification','checks'),('security','checks')]}}
 config=private/'profile.json';policy_path=private/'policy.json';contract_path=private/'intake.json'
 policy={'repository':'fixture/intake','runtime':{'routing_profile_sha256':'','roles_by_task':{'T-1':'implementation'},'worker_guard':guard}}
 contract={'schema_version':1,'enabled':True,'repository':'fixture/intake','candidate_root':str(candidate),'authority_root':str(authority),'database':str(private/'runtime.sqlite'),'profile':str(config),'policy':str(policy_path),'trusted_files':{},'limits':{'request_chars':20000,'context_bytes':500000,'output_bytes':65536,'assessment_seconds':60}}
 def save(pdoc=profile,ydoc=policy,cdoc=contract):
  config.write_text(json.dumps(pdoc));config.chmod(0o600)
  ydoc=copy.deepcopy(ydoc);ydoc['runtime']['routing_profile_sha256']=hashlib.sha256(r.canonical(pdoc).encode()).hexdigest();policy_path.write_text(json.dumps(ydoc));policy_path.chmod(0o600)
  cdoc=copy.deepcopy(cdoc);cdoc['trusted_files']={str(p):sha(p) for p in closure+[native,interpreter,proof,config,policy_path]};contract_path.write_text(json.dumps(cdoc));contract_path.chmod(0o600)
 save();selected=m.load_worker_contract(contract_path,'T-1');assert selected['runtime']=='primary' and selected['model']=='fixture-model';assert selected['capability_evidence']=='protected-observation';assert not (private/'executed').exists()
 for field,value in [('version','2.1.294'),('version','2.1.295-extra'),('capabilities',capabilities[:-1]),('capabilities',capabilities+[capabilities[0]]),('extra',True),('native_executable',str(candidate/'native')),('interpreter',str(private/'.env'))]:
  bad=copy.deepcopy(policy);bad['runtime']['worker_guard'][field]=value;save(ydoc=bad);reject(lambda:m.load_worker_contract(contract_path,'T-1'))
 for change in ['missing','role','repo','model','argv','fallback','pin']:
  bad=copy.deepcopy(profile);yp=copy.deepcopy(policy)
  if change=='missing':yp['runtime'].pop('worker_guard')
  if change=='role':yp['runtime']['roles_by_task']['T-1']='review'
  if change=='repo':bad['repository']='other/repository'
  if change=='model':bad['runtimes']['primary']['model']='different-model'
  if change=='argv':bad['runtimes']['primary']['command']+=['--resume','session']
  if change=='fallback':bad['roles']['implementation']['primary']='fallback'
  if change=='pin':bad['runtimes']['primary']['probe']['trusted_files'].pop(str(interpreter))
  save(bad,yp);reject(lambda:m.load_worker_contract(contract_path,'T-1'))
 save();reject(lambda:m.load_worker_contract(contract_path,'T-999'))
 raw=proof.read_bytes();proof.write_text('[]');guard['observation']['sha256']=sha(proof);profile['runtimes']['primary']['probe']['trusted_files'][str(proof)]=sha(proof);save();reject(lambda:m.load_worker_contract(contract_path,'T-1'));proof.write_bytes(raw);guard['observation']['sha256']=sha(proof);profile['runtimes']['primary']['probe']['trusted_files'][str(proof)]=sha(proof);save()
 raw=proof.read_bytes();doc=json.loads(raw);doc['model']='different';proof.write_text(json.dumps(doc));guard['observation']['sha256']=sha(proof);profile['runtimes']['primary']['probe']['trusted_files'][str(proof)]=sha(proof);save();reject(lambda:m.load_worker_contract(contract_path,'T-1'));proof.write_bytes(raw);guard['observation']['sha256']=sha(proof);profile['runtimes']['primary']['probe']['trusted_files'][str(proof)]=sha(proof);save()
 doc=json.loads(contract_path.read_text());doc['trusted_files'].pop(str(helper.with_name('factory-supervisor.py')));contract_path.write_text(json.dumps(doc));reject(lambda:m.load_worker_contract(contract_path,'T-1'));save()
 native.write_text('drift');reject(lambda:m.load_worker_contract(contract_path,'T-1'))
 native.write_text('#!/bin/sh\ntouch '+str(private/'executed')+'\nexit 99\n');native.chmod(0o700);save()
 interpreter.chmod(0o777);reject(lambda:m.load_worker_contract(contract_path,'T-1'));interpreter.chmod(0o700)
 proof.chmod(0o644);reject(lambda:m.load_worker_contract(contract_path,'T-1'));proof.chmod(0o600)
 link=private/'hardlink';os.link(proof,link);reject(lambda:m.load_worker_contract(contract_path,'T-1'));link.unlink()
 contract_path.chmod(0o644);reject(lambda:m.load_worker_contract(contract_path,'T-1'));contract_path.chmod(0o600)
 # Review regressions run independently so RED records all three concrete failures.
 errors=[]
 class AccessTimeOnly:
  def __init__(self,value):self.value=value
  def __getattr__(self,name):return self.value.st_atime+10 if name=='st_atime' else getattr(self.value,name)
  def __eq__(self,other):return False
 real_fstat=os.fstat
 try:
  with patch.object(m.os,'fstat',side_effect=lambda fd:AccessTimeOnly(real_fstat(fd))):
   assert m.read_artifact(str(proof),private=True)==proof.read_bytes()
 except (ValueError,AssertionError):errors.append('atime-only read must preserve valid artifact')
 original_native=native.read_bytes();original_proof=proof.read_bytes();original_profile=copy.deepcopy(profile)
 native.write_bytes(b'x'*8000001);profile['runtimes']['primary']['probe']['trusted_files'][str(native)]=sha(native)
 doc=json.loads(original_proof);doc['native_sha256']=sha(native);proof.write_text(json.dumps(doc));guard['observation']['sha256']=sha(proof);profile['runtimes']['primary']['probe']['trusted_files'][str(proof)]=sha(proof)
 save();doc=json.loads(contract_path.read_text());doc['trusted_files'].pop(str(native));doc['trusted_files'].pop(str(interpreter));contract_path.write_text(json.dumps(doc))
 try:assert m.load_worker_contract(contract_path,'T-1')['model']=='fixture-model'
 except (ValueError,AssertionError):errors.append('large pinned executable must use protected indirect pin chain')
 with native.open('wb') as stream:stream.truncate(512*1024*1024+1)
 reject(lambda:m.load_worker_contract(contract_path,'T-1'))
 native.write_bytes(original_native);proof.write_bytes(original_proof);profile.clear();profile.update(original_profile);guard['observation']['sha256']=sha(proof);save()
 # Designated interpreters use the executable pin chain, not the 8 MB source bound.
 original_interpreter=interpreter.read_bytes()
 interpreter.write_bytes(original_interpreter+b'#'+b'x'*8000001+b'\n')
 profile['runtimes']['primary']['probe']['trusted_files'][str(interpreter)]=sha(interpreter)
 doc=json.loads(proof.read_text());doc['interpreter_sha256']=sha(interpreter);proof.write_text(json.dumps(doc));guard['observation']['sha256']=sha(proof);profile['runtimes']['primary']['probe']['trusted_files'][str(proof)]=sha(proof)
 save();doc=json.loads(contract_path.read_text());doc['trusted_files'].pop(str(interpreter));contract_path.write_text(json.dumps(doc))
 assert interpreter.stat().st_size>8000000
 reject(lambda:m.read_artifact(str(interpreter)))
 assert m.load_worker_contract(contract_path,'T-1')['interpreter']==str(interpreter)
 with interpreter.open('ab') as stream:stream.write(b'# drift\n')
 reject(lambda:m.load_worker_contract(contract_path,'T-1'))
 interpreter.write_bytes(original_interpreter+b'#'+b'x'*8000001+b'\n')
 bad=copy.deepcopy(profile);bad['runtimes']['primary']['probe']['trusted_files'][str(interpreter)]='0'*64
 save(bad);doc=json.loads(contract_path.read_text());doc['trusted_files'].pop(str(interpreter));contract_path.write_text(json.dumps(doc));reject(lambda:m.load_worker_contract(contract_path,'T-1'))
 interpreter.write_bytes(original_interpreter);proof.write_bytes(original_proof);profile.clear();profile.update(original_profile);guard['observation']['sha256']=sha(proof);save()
 print('worker-contract: >8MB designated interpreter indirect closure accepted; byte and hash drift rejected; source bound unchanged')
 bundle=private/'bundle';bundle.mkdir(mode=0o700)
 for source in closure:(bundle/source.name).write_bytes(source.read_bytes())
 copied_worker=bundle/helper.name;copied_core=bundle/'factory-intake.py';marker=private/'attacker-imported'
 copied=module('copied_worker_contract',copied_worker);pd=copy.deepcopy(profile)
 pd['runtimes']['primary']['command'][3]=str(copied_worker)
 for source in closure:
  pd['runtimes']['primary']['probe']['trusted_files'].pop(str(source))
  pd['runtimes']['primary']['probe']['trusted_files'][str(bundle/source.name)]=sha(bundle/source.name)
 save(pd);doc=json.loads(contract_path.read_text())
 for source in closure:doc['trusted_files'].pop(str(source));doc['trusted_files'][str(bundle/source.name)]=sha(bundle/source.name)
 contract_path.write_text(json.dumps(doc));read=copied.read_artifact;swapped=[False]
 def swapped_read(value,**kwargs):
  result=read(value,**kwargs)
  if str(value)==str(copied_core) and not swapped[0]:
   swapped[0]=True;copied_core.write_text('from pathlib import Path\nPath('+repr(str(marker))+').write_text("executed")\nraise ValueError("attacker source reopened")\n')
  return result
 with patch.object(copied,'read_artifact',side_effect=swapped_read):reject(lambda:copied.load_worker_contract(contract_path,'T-1'))
 if marker.exists():errors.append('verified helper bytes must execute without reopening source or pycache')
 save();assert not errors,errors
 neutral={name:None for name in contract};neutral.update(schema_version=1,enabled=False,trusted_files={},limits=contract['limits']);contract_path.write_text(json.dumps(neutral));assert m.load_worker_contract(contract_path,'T-1') is None
 neutral['limits']['output_bytes']=True;contract_path.write_text(json.dumps(neutral));reject(lambda:m.load_worker_contract(contract_path,'T-1'))
 assert not (private/'executed').exists(), 'validation invoked native or interpreter'
 print('worker-contract: protected primary binding, exact closure and observation, hostile controls rejected; disabled unchanged; no process launched')
PYTEST
