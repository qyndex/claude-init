#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy,hashlib,importlib.util,io,json,sys,tempfile,zipfile
from pathlib import Path
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'.claude/scripts'))
spec=importlib.util.spec_from_file_location('coordinator',root/'.claude/scripts/factory-coordinator.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
head='a'*40;base='b'*40
policy={'schema_version':1,'enabled':True,'merge_enabled':True,'repository':'qyndex/claude-init','base_branch':'main','app_id':99,
 'protected_paths':['factory/*','.github/*','.claude/scripts/factory-*'],
 'required_checks':{'tests':123},'specs':{'007':{'sha256':'c'*64,'ac_ids':['AC-1'],'allowed_paths':['src/*']}},
 'producers':{'verification':{'workflow_id':10,'artifact_name':'factory-verification','trusted_files':{'.github/verify.yml':hashlib.sha256(b'trusted').hexdigest()}},
              'review':{'workflow_id':20,'artifact_name':'factory-review','trusted_files':{'.github/review.yml':hashlib.sha256(b'trusted').hexdigest()}}}}
pr={'number':42,'state':'open','draft':False,'merged':False,'user':{'login':'builder'},
 'head':{'sha':head,'ref':'factory/spec-007/feature','repo':{'full_name':policy['repository']}},
 'base':{'sha':base,'ref':'main','repo':{'full_name':policy['repository']}}}
rules=[{'type':'pull_request'},{'type':'required_status_checks','ruleset_id':1,'parameters':{'strict_required_status_checks_policy':True,'required_status_checks':[{'context':'factory-eligibility','integration_id':99},{'context':'tests','integration_id':123}]}}]
runs=[{'id':i,'workflow_id':w,'head_sha':head,'head_repository':{'full_name':policy['repository']},'event':'pull_request','status':'completed','conclusion':'success','created_at':'2026-10-09T00:00:00Z','updated_at':'2026-10-09T00:30:00Z','pull_requests':[{'number':42}]} for i,w in [(1,10),(2,20)]]
checks=[{'name':'tests','head_sha':head,'app':{'id':123},'id':88,'status':'completed','conclusion':'success'}]
ph=hashlib.sha256(json.dumps(policy,sort_keys=True,separators=(',',':')).encode()).hexdigest()
proof=b'observed behaviour'
common={'schema_version':1,'repository':policy['repository'],'pull_request':42,'head_sha':head,'base_sha':base,'spec_sha256':'c'*64,'policy_sha256':ph,'generated_at':'2026-10-09T00:15:00Z'}
documents={1:dict(common,acceptance=[{'id':'AC-1','status':'pass','artifact_sha256':hashlib.sha256(proof).hexdigest()}],verification={'actor':'workflow:10/run:1','head_sha':head,'verdict':'pass','unresolved_findings':[]}),2:dict(common,review={'actor':'workflow:20/run:2','head_sha':head,'verdict':'pass','unresolved_findings':[]})}
class Fake:
 def __init__(self):
  self.pr=copy.deepcopy(pr);self.rules=copy.deepcopy(rules);self.runs=copy.deepcopy(runs);self.checks=copy.deepcopy(checks);self.docs=copy.deepcopy(documents);self.files=[{'filename':'src/app.py'}];self.calls=[];self.drift=False;self.bad_source=False;self.bad_artifact=False;self.fail=False;self.bypass=False
 def get(self,path):
  if self.fail:raise ValueError('API unavailable')
  if '/pulls/' in path and path.endswith('/files'):return self.files
  if '/pulls/' in path:
   self.calls.append('read-pr');out=copy.deepcopy(self.pr)
   if self.drift and self.calls.count('read-pr')>1:out['base']['sha']='f'*40
   return out
  if '/rules/branches/' in path:return self.rules
  if '/rulesets/' in path:return {'enforcement':'active','bypass_actors':[{'actor_id':99}] if self.bypass else []}
  if '/check-runs' in path:return self.checks
  if '/actions/runs?' in path:return self.runs
  raise AssertionError(path)
 def source(self,path,sha):return b'tampered' if self.bad_source else b'trusted'
 def artifact(self,run,name):
  if self.bad_artifact:raise ValueError('artifact digest mismatch')
  return self.docs[run['id']],{hashlib.sha256(proof).hexdigest():proof}
 def post(self,path,payload):self.calls.append((path,payload));return {'id':123,'merged':True,'sha':'d'*40}
 def put(self,path,payload):return self.post(path,payload)
def check(fake,p=policy,valid=False):
 try:result=m.coordinate(fake,p,42,merge=True)
 except (ValueError,KeyError,TypeError):
  assert not any(isinstance(call,tuple) and call[0].endswith('/merge') for call in fake.calls)
  assert not valid
 else:
  assert valid,result
  call=[call for call in fake.calls if isinstance(call,tuple) and call[0].endswith('/merge')][0]
  assert call[1]['sha']==head and result['merge_sha']=='d'*40
check(Fake(),valid=True)
mutations=[lambda f:f.pr['head'].update(ref='arbitrary'),lambda f:f.pr.update(draft=True),lambda f:f.files.append({'filename':'factory/policy.json'}),lambda f:f.files.append({'filename':'src/new','previous_filename':'.github/old'}),lambda f:f.files.append({'filename':'outside.py'}),lambda f:f.rules.clear(),lambda f:f.rules[1]['parameters']['required_status_checks'][0].update(integration_id=1),lambda f:f.checks[0].update(head_sha='f'*40),lambda f:f.checks[0]['app'].update(id=1),lambda f:f.checks[0].update(conclusion='skipped'),lambda f:f.runs[0].update(status='in_progress'),lambda f:f.runs[0].update(head_sha='f'*40),lambda f:f.runs[0].update(pull_requests=[]),lambda f:f.docs[1].update(base_sha='f'*40),lambda f:f.docs[2]['review'].update(unresolved_findings=['critical']),lambda f:setattr(f,'drift',True),lambda f:setattr(f,'bad_source',True),lambda f:setattr(f,'bad_artifact',True),lambda f:setattr(f,'fail',True),lambda f:setattr(f,'bypass',True)]
for mutation in mutations:
 f=Fake();mutation(f);check(f)
p=copy.deepcopy(policy);p['enabled']=False;check(Fake(),p)
p=copy.deepcopy(policy);p['merge_enabled']=False;check(Fake(),p)
# Exercise actual ZIP validation as well as the injected API boundary.
def archive_blob(extra=False):
 buffer=io.BytesIO()
 with zipfile.ZipFile(buffer,'w') as archive:
  archive.writestr('evidence.json',json.dumps(documents[1]))
  archive.writestr('artifacts/'+hashlib.sha256(proof).hexdigest(),proof)
  if extra:archive.writestr('../escape',b'bad')
 return buffer.getvalue()
class ArchiveAPI(m.GitHub):
 def __init__(self,blob,bad_digest=False):super().__init__(policy['repository']);self.blob=blob;self.bad_digest=bad_digest
 def request(self,path,*args,**kwargs):
  if path.endswith('/zip'):return self.blob
  return [{'artifacts':[{'id':1,'name':'proof','expired':False,'size_in_bytes':len(self.blob),'digest':'sha256:'+('0'*64 if self.bad_digest else hashlib.sha256(self.blob).hexdigest())}]}]
doc,blobs=ArchiveAPI(archive_blob()).artifact(runs[0],'proof');assert doc==documents[1] and list(blobs.values())==[proof]
for api in [ArchiveAPI(archive_blob(),True),ArchiveAPI(archive_blob(True))]:
 try:api.artifact(runs[0],'proof')
 except ValueError:pass
 else:raise AssertionError('invalid archive passed')
f=Fake();result=m.coordinate(f,policy,42,merge=False);assert result['eligible'] and not any(isinstance(call,tuple) for call in f.calls)
with tempfile.TemporaryDirectory() as tmp:
 path=Path(tmp)/'policy.json';path.write_text(json.dumps(policy))
 f=Fake();f.docs[2]['review']['verdict']='fail'
 original=m.GitHub;argv=sys.argv
 m.GitHub=lambda repo:f
 sys.argv=['coordinator','--policy',str(path),'--pr','42','--merge','--output',str(Path(tmp)/'receipt.json')]
 try:
  try:m.main()
  except ValueError:pass
  else:raise AssertionError('failed reevaluation accepted')
 finally:m.GitHub=original;sys.argv=argv
 posts=[call for call in f.calls if isinstance(call,tuple)]
 assert len(posts)==1 and posts[0][0].endswith('/check-runs') and posts[0][1]['conclusion']=='failure'
print(f'passed: {len(mutations)+8}; failed: 0')
PY
