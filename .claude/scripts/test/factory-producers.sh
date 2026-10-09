#!/usr/bin/env bash
set -euo pipefail
ROOT="${PRODUCER_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PY'
import copy,hashlib,importlib.util,json,os,subprocess,sys,tempfile
from pathlib import Path
root=Path(sys.argv[1])
assert (root/'.claude/scripts/factory-producer.py').is_file(), 'protected producer not implemented'
spec=importlib.util.spec_from_file_location('producer',root/'.claude/scripts/factory-producer.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
head='a'*40;base='b'*40;repo='qyndex/claude-init';content=b'**AC-1**: works\n'
p={'enabled':True,'repository':repo,'base_branch':'main','protected_paths':['.github/*','.claude/scripts/factory-*','.claude/scripts/validate-candidate-evidence.py','factory/*'],
 'specs':{'010':{'path':'specs/active/010.md','sha256':hashlib.sha256(content).hexdigest(),'ac_ids':['AC-1'],'allowed_paths':['src/*'],
 'acceptance_commands':{'AC-1':['python3','test.py']},'verification_image':'python@sha256:'+'c'*64}},
 'producers':{'verification':{'workflow_id':10,'event':'pull_request_target','trusted_files':{'.github/proof.yml':hashlib.sha256(b'trusted').hexdigest()}}}}
p['producers']['verification']['trusted_files']={path:hashlib.sha256(b'trusted').hexdigest() for path in m.coordinator.runtime_paths('verification')}
pr={'state':'open','draft':False,'merged':False,'changed_files':1,'head':{'sha':head,'ref':'factory/spec-010/pilot','repo':{'full_name':repo}},'base':{'sha':base,'ref':'main','repo':{'full_name':repo}}}
run={'workflow_id':10,'event':'pull_request_target','head_sha':base,'head_repository':{'full_name':repo}}
class API:
 def __init__(self):self.pr=copy.deepcopy(pr);self.run=copy.deepcopy(run);self.files=[{'filename':'src/app.py','status':'modified'}];self.bad_spec=False;self.bad_runtime=False
 def get(self,path):
  if path.endswith('/files'):return self.files
  if '/actions/runs/' in path:return self.run
  return self.pr
 def source(self,path,sha):
  if path.startswith('specs/'):return b'bad' if self.bad_spec else content
  if path.startswith('.github/') or path.startswith('.claude/'):return b'bad' if self.bad_runtime else b'trusted'
  return b'print("before")' if sha==base else b'print("after")'
passed=0
def succeeds(fn):
 global passed
 fn();passed+=1
def rejects(fn):
 global passed
 try:fn()
 except (ValueError,KeyError,TypeError):passed+=1;return
 raise AssertionError('invalid producer input accepted')
succeeds(lambda:m.candidate(API(),p,42,1,'verification'))
for change in [lambda a:a.pr.update(draft=True),lambda a:a.pr['head']['repo'].update(full_name='foreign/repo'),lambda a:a.run.update(head_sha=head),lambda a:a.run.update(event='pull_request'),lambda a:a.run.update(workflow_id=99),lambda a:a.pr.update(changed_files=2),lambda a:a.files[0].update(filename='factory/policy.json'),lambda a:a.files[0].update(filename='other/app.py'),lambda a:setattr(a,'bad_spec',True),lambda a:setattr(a,'bad_runtime',True),lambda a:a.files[0].update(previous_filename='.github/old.yml')]:
 a=API();change(a);rejects(lambda:m.candidate(a,p,42,1,'verification'))
bad=copy.deepcopy(p);bad['enabled']=False;rejects(lambda:m.candidate(API(),bad,42,1,'verification'))
bad=copy.deepcopy(p);bad['specs']['010']['ac_ids']=['AC-1','AC-2'];rejects(lambda:m.candidate(API(),bad,42,1,'verification'))
approved=p['specs']['010'];binding=m.candidate(API(),p,42,1,'verification')[4];actor='workflow:10/run:1'
with tempfile.TemporaryDirectory() as folder:
 out=Path(folder);(out/'artifacts').mkdir()
 def runner(command,**kw):
  assert '--network' in command and command[command.index('--network')+1]=='none'
  assert '--read-only' in command and '--cap-drop' in command and 'ALL' in command
  assert not any('TOKEN' in word or 'docker.sock' in word for word in command)
  kw['stdout'].write(b'observed behaviour');return subprocess.CompletedProcess(command,0)
 document=m.verify(approved,out,out,binding,actor,runner)
 assert document['verification']['verdict']=='pass'
 observed=json.loads((out/'artifacts'/document['acceptance'][0]['artifact_sha256']).read_bytes());assert observed['output']=='observed behaviour' and observed['exit_code']==0 and observed['argv']==approved['acceptance_commands']['AC-1'];passed+=2
 def failed(command,**kw):kw['stdout'].write(b'FAIL');return subprocess.CompletedProcess(command,1)
 assert m.verify(approved,out,out,binding,actor,failed)['verification']['verdict']=='fail';passed+=1
 bad=copy.deepcopy(approved);bad['acceptance_commands']={};rejects(lambda:m.verify(bad,out,out,binding,actor,runner))
 rejects(lambda:m.sandbox_command('python:latest',out,'test',['true']))
 rejects(lambda:m.sandbox_command(approved['verification_image'],out,'test','bash -c true'))
 prompt=m.review_prompt(API(),repo,approved,API().files,content,binding)
 assert 'before' in prompt and 'after' in prompt and 'AC-1' in prompt;passed+=1
 os.environ['FACTORY_REVIEW_PROVIDER']='oauth';os.environ['CLAUDE_CODE_OAUTH_TOKEN']='fixture';os.environ['GH_TOKEN']='must-not-inherit';os.environ['FACTORY_APP_PRIVATE_KEY']='must-not-inherit'
 def reviewer(command,**kw):
  assert command[command.index('--tools')+1]=='' and command[command.index('--setting-sources')+1]==''
  assert kw['input']==prompt and 'GH_TOKEN' not in kw['env'] and 'FACTORY_APP_PRIVATE_KEY' not in kw['env']
  assert kw['env']['CLAUDE_CODE_OAUTH_TOKEN']=='fixture'
  return subprocess.CompletedProcess(command,0,json.dumps({'is_error':False,'subtype':'success','structured_output':{'verdict':'pass','unresolved_findings':[]}}),'')
 assert m.review(prompt,binding,actor,reviewer)['review']['verdict']=='pass';passed+=1
 def quota(command,**kw):return subprocess.CompletedProcess(command,1,'{"api_error":"usage_limit_reached"}','')
 rejects(lambda:m.review(prompt,binding,actor,quota))
 def fake_pass(command,**kw):return subprocess.CompletedProcess(command,0,json.dumps({'is_error':True,'subtype':'success','structured_output':{'verdict':'pass','unresolved_findings':[]}}),'')
 rejects(lambda:m.review(prompt,binding,actor,fake_pass))
 def unresolved(command,**kw):return subprocess.CompletedProcess(command,0,json.dumps({'is_error':False,'subtype':'success','structured_output':{'verdict':'pass','unresolved_findings':['src/app.py:1 defect']}}),'')
 rejects(lambda:m.review(prompt,binding,actor,unresolved))
 del os.environ['CLAUDE_CODE_OAUTH_TOKEN'];rejects(lambda:m.review(prompt,binding,actor,reviewer))
spec=importlib.util.spec_from_file_location('publisher',root/'.claude/scripts/factory-producer-check.py')
publisher=importlib.util.module_from_spec(spec);spec.loader.exec_module(publisher)
class Checks(API):
 def __init__(self):super().__init__();self.calls=[]
 def post(self,path,payload):self.calls.append((path,payload));return {'id':77}
 def request(self,path,method,payload):self.calls.append((path,payload));return {}
with tempfile.TemporaryDirectory() as folder:
 state=Path(folder)/'state.json';api=Checks()
 publisher.publish(api,repo,42,1,'verification',state)
 assert api.calls[0][1]['head_sha']==head and api.calls[0][1]['details_url'].endswith('/runs/1');passed+=1
 publisher.publish(api,repo,42,1,'verification',state,'failure')
 assert api.calls[-1][1]['conclusion']=='failure';passed+=1
 rejects(lambda:publisher.publish(api,repo,43,1,'verification',state,'success'))
 rejects(lambda:publisher.publish(api,repo,42,1,'review',state,'success'))
print(f'passed: {passed}; failed: 0')
PY
