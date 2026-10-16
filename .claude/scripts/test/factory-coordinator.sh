#!/usr/bin/env bash
set -euo pipefail
ROOT="${COORDINATOR_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PY'
import copy,hashlib,importlib.util,io,json,sys,tempfile,zipfile
from pathlib import Path
root=Path(sys.argv[1]);sys.path.insert(0,str(root/'.claude/scripts'))
spec=importlib.util.spec_from_file_location('coordinator',root/'.claude/scripts/factory-coordinator.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
head='a'*40;base='b'*40
policy={'schema_version':1,'enabled':True,'merge_enabled':True,'repository':'qyndex/claude-init','base_branch':'main','app_id':99,
 'protected_paths':['factory/*','.github/*','.claude/scripts/factory-*','.claude/scripts/validate-candidate-evidence.py'],
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
  if '/actions/runs/' in path:return next(run for run in self.runs if str(run['id'])==path.rsplit('/',1)[1])
  raise AssertionError(path)
 def source(self,path,sha):return b'tampered' if self.bad_source else b'trusted'
 def artifact(self,run,name,**provenance):
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
# Protected target workflows report candidate checks that link to their authenticated run.
assert callable(getattr(m,'runtime_paths',None)), 'protected producer runtime contract missing'
p=copy.deepcopy(policy)
p['required_checks'].update({'factory-verification':123,'factory-independent-review':123})
for role,name in [('verification','factory-verification'),('review','factory-independent-review')]:
 p['producers'][role].update(event='pull_request_target',check_name=name,trusted_files={path:hashlib.sha256(b'trusted').hexdigest() for path in m.runtime_paths(role)})
f=Fake()
f.rules[1]['parameters']['required_status_checks'] += [{'context':name,'integration_id':123} for name in ('factory-verification','factory-independent-review')]
for index,name in enumerate(('factory-verification','factory-independent-review'),1):
 f.checks.append({'name':name,'head_sha':head,'app':{'id':123},'id':88+index,'status':'completed','conclusion':'success','details_url':f'https://github.com/qyndex/claude-init/runs/{(116718131349,116718157648)[index-1]}','check_suite':{'id':105208672410}})
 f.runs[index-1].update(event='pull_request_target',run_attempt=1,head_sha=head,pull_requests=[],repository={'full_name':policy['repository']},path=f'.github/workflows/factory-{("verification","review")[index-1]}.yml')
ph=m.policy_hash(p)
for document in f.docs.values():document['policy_sha256']=ph
check(f,p,valid=True)
for url in ('https://foreign/run/2','',None,'https://github.com/qyndex/claude-init/actions/runs/999999'):
 bad=copy.deepcopy(f);bad.calls=[];bad.checks[-1]['details_url']=url;check(bad,p,valid=True)
for mutate in [lambda a:a.runs[-1].update(head_sha=base),lambda a:a.runs[-1].update(event='workflow_dispatch'),lambda a:a.runs[-1].update(workflow_id=999)]:
 bad=copy.deepcopy(f);bad.calls=[];mutate(bad);check(bad,p)
# Old immutable candidate cannot be rescued by updated mutable PR associations.
bad=copy.deepcopy(f);bad.calls=[];bad.runs[-1]['head_sha']='f'*40;bad.runs[-1]['pull_requests']=[{'number':42,'head':{'sha':head},'base':{'sha':base}}];check(bad,p)
for mutate in [lambda a:a.pr['base'].update(sha='f'*40),lambda a:[doc.update(base_sha='f'*40) for doc in a.docs.values()],lambda a:a.runs[-1].pop('repository'),lambda a:a.runs[-1].update(repository={'full_name':'foreign/repo'}),lambda a:a.runs[-1].update(path='.github/workflows/foreign.yml')]:
 bad=copy.deepcopy(f);bad.calls=[];mutate(bad);check(bad,p)
# AC-4: select latest by workflow identity BEFORE event/status filtering.
for changes in ({'event':'workflow_dispatch'},{'conclusion':'failure'},{'conclusion':'cancelled'},{'status':'in_progress','conclusion':None},{'head_sha':base},{'repository':{'full_name':'foreign/repo'}},{'run_attempt':0},{'run_attempt':True}):
 bad=copy.deepcopy(f);bad.calls=[];latest=dict(bad.runs[-1],id=99,**changes);bad.runs.append(latest);check(bad,p)
# Another workflow cannot displace the latest required workflow.
bad=copy.deepcopy(f);bad.calls=[];bad.runs.append(dict(bad.runs[-1],id=100,workflow_id=999));check(bad,p,valid=True)
# Detail/list attempt disagreement and duplicate latest identity reject.
class AttemptDrift(Fake):
 def get(self,path):
  result=super().get(path)
  return dict(result,run_attempt=2) if path.endswith('/actions/runs/2') else result
bad=AttemptDrift();bad.__dict__.update(copy.deepcopy(f.__dict__));bad.calls=[];check(bad,p)
bad=copy.deepcopy(f);bad.calls=[];bad.runs.append(copy.deepcopy(bad.runs[-1]));check(bad,p)
# A newer attempt/run appearing during artifact validation invalidates the snapshot.
class LatestRace(Fake):
 reads=0
 def get(self,path):
  result=super().get(path)
  if '/actions/runs?' in path:
   self.reads+=1
   if self.reads>1:return result+[dict(result[-1],id=99,conclusion='failure')]
  return result
bad=LatestRace();bad.__dict__.update(copy.deepcopy(f.__dict__));bad.calls=[];check(bad,p)
for race in ({'run_attempt':2},{'conclusion':'failure'},{'status':'in_progress','conclusion':None},{'event':'workflow_dispatch'},{'head_sha':base},{'path':'.github/workflows/foreign.yml'},{'repository':{'full_name':'foreign/repo'}}):
 class FreshRace(Fake):
  reads=0
  def get(self,path):
   result=super().get(path)
   if '/actions/runs?' in path:
    self.reads+=1
    if self.reads>1:
     result=copy.deepcopy(result);result[-1].update(race)
   return result
 bad=FreshRace();bad.__dict__.update(copy.deepcopy(f.__dict__));bad.calls=[];check(bad,p)
# A current successful rerun attempt is eligible only with matching metadata.
bad=copy.deepcopy(f);bad.calls=[];bad.runs[-1]['run_attempt']=2;check(bad,p,valid=True)
# AC-5: hidden live bypass metadata needs exact protected administrative input.
import datetime
ob_now=datetime.datetime.now(datetime.timezone.utc)
full_rules={'id':1,'node_id':'R_1','name':'main','source':policy['repository'],'source_type':'Repository','target':'branch','enforcement':'active','created_at':'2026-10-15T00:00:00Z','updated_at':(ob_now-datetime.timedelta(minutes=2)).isoformat(),'conditions':{'ref_name':{'include':['refs/heads/main'],'exclude':[]}},'rules':[{'type':'pull_request'}],'bypass_actors':[]}
repository={'id':42,'full_name':policy['repository']}
obs_spec=importlib.util.spec_from_file_location('obs','.claude/scripts/factory-policy-observation.py');obs=importlib.util.module_from_spec(obs_spec);obs_spec.loader.exec_module(obs)
observation=obs.capture(repository,full_rules,now=ob_now)
class Hidden(Fake):
 def __init__(self):super().__init__();self.metadata=copy.deepcopy(full_rules);self.metadata.pop('bypass_actors');self.reads=0;self.change=False
 def get(self,path):
  if path=='repos/'+policy['repository']:return repository
  if '/rulesets/' in path:
   self.reads+=1
   result=copy.deepcopy(self.metadata)
   if self.change and self.reads>1:result['name']='changed'
   return result
  return super().get(path)
def hidden_check(fake,observations,valid=False):
 audit=[]
 try:result=m.coordinate(fake,policy,42,merge=False,observations=observations,audit=audit)
 except ValueError:assert not valid
 else:assert valid and result['eligible'] and audit and audit[-1]['mode']=='operator-observation'
 assert not any(isinstance(call,tuple) for call in fake.calls)
hidden_check(Hidden(),[observation],True)
hidden_check(Hidden(),[])
for field,value in [('repository','foreign/repo'),('ruleset_id',2),('metadata_sha256','0'*64),('observed_at',(ob_now+datetime.timedelta(days=1)).isoformat())]:
 bad=dict(observation);bad[field]=value;hidden_check(Hidden(),[bad])
for actors in (None,{},[{'actor_id':99}]):
 f=Hidden();f.metadata['bypass_actors']=actors;hidden_check(f,[observation])
f=Hidden();f.change=True;hidden_check(f,[observation])
with tempfile.TemporaryDirectory() as temp:
 path=Path(temp)/'observations.json'
 doc={'schema_version':1,'repository':policy['repository'],'observations':[observation]}
 path.write_text(json.dumps(doc));assert m.load_observations(path,policy['repository'])==[observation]
 for raw in ('{"schema_version":1,"schema_version":1}',json.dumps(dict(doc,repository='foreign/repo')),json.dumps(dict(doc,observations=[observation,observation])),json.dumps(dict(doc,extra='x')),'x'*262145):
  path.write_text(raw)
  try:m.load_observations(path,policy['repository'])
  except ValueError:pass
  else:raise AssertionError('protected input invalid schema accepted')
# Exercise actual CLI packaging: audit is bounded, separate from receipt.json.
import contextlib
with tempfile.TemporaryDirectory() as temp:
 directory=Path(temp);policy_path=directory/'policy.json';policy_path.write_text(json.dumps(policy))
 input_path=directory/'observations.json';input_path.write_text(json.dumps({'schema_version':1,'repository':policy['repository'],'observations':[observation]}))
 receipt=directory/'receipt.json';audit_path=directory/'administrative.json'
 previous_api=m.GitHub;previous_args=sys.argv[:]
 try:
  m.GitHub=lambda repository:Hidden()
  sys.argv=['coordinator','--policy',str(policy_path),'--pr','42','--output',str(receipt),'--policy-observations',str(input_path),'--policy-audit',str(audit_path)]
  with contextlib.redirect_stdout(io.StringIO()):m.main()
 finally:m.GitHub=previous_api;sys.argv=previous_args
 audit=json.loads(audit_path.read_text());assert audit['kind']=='administrative-observation-not-native-attestation'
 assert len(audit['checks'])==2 and all(item['observation']==observation for item in audit['checks'])
 assert len(audit_path.read_bytes())<=m.policy_observation.MAX_BYTES
 assert json.loads(receipt.read_text())['eligible'] and 'observation' not in receipt.read_text()
 assert not any(word in audit_path.read_text() for word in ('GH_TOKEN','PRIVATE_KEY','provider_output'))
# AC-5: malformed protected input must invalidate an existing same-head success.
with tempfile.TemporaryDirectory() as temp:
 directory=Path(temp);policy_path=directory/'policy.json';policy_path.write_text(json.dumps(policy))
 path=directory/'input.json';receipt=directory/'receipt.json';fake=Fake()
 # Prior successful eligibility exists; failure must actively replace it.
 fake.calls.append(('existing-success',{'head_sha':head}))
 original_api=m.GitHub;original_args=sys.argv[:]
 try:
  m.GitHub=lambda repository:fake
  sys.argv=['coordinator','--policy',str(policy_path),'--pr','42','--merge','--output',str(receipt),'--policy-observations',str(path)]
  for raw in ('{"schema_version":1,"schema_version":1}','x'*262145,'{"secret":"DO_NOT_ECHO_SENTINEL"}'):
   path.write_text(raw);before=len(fake.calls)
   try:m.main()
   except ValueError:pass
   else:raise AssertionError('invalid protected input accepted')
   failed=[call[1] for call in fake.calls[before:] if isinstance(call,tuple) and call[0].endswith('/check-runs')]
   assert len(failed)==1 and failed[0]['conclusion']=='failure' and failed[0]['head_sha']==head
   assert not receipt.exists() and 'DO_NOT_ECHO_SENTINEL' not in json.dumps(failed)
 finally:m.GitHub=original_api;sys.argv=original_args
print('AC-5: protected hidden observations, visible actor rejection, final drift and bounded strict input PASS')
print(f'passed: {len(mutations)+43}; failed: 0')

PY
