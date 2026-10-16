#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: separately protected positive writer facts, never invented actors."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 from datetime import datetime,timezone,timedelta
 neutral=r.coordinator.policy_observation
 now=datetime(2026,10,16,tzinfo=timezone.utc)
 repo={'id':101,'full_name':'org/repo'}
 for identity,value in policies.items():
  value.update(name='reviewed-'+str(identity),node_id='R_'+str(identity),created_at='2026-10-13T00:00:00Z')
 original=json.loads(approval.read_bytes());original['policies']={str(i):a.digest(a.canonical(value)) for i,value in policies.items()};approval.write_text(json.dumps(original))
 assert a.verify_bootstrap(State(),approval,now=now)['head']==initial
 print('existing exact full-metadata real-Git bootstrap passes before new feature',flush=True)
 def observed(identity,value):
  return {'schema_version':1,'repository':'org/repo','repository_id':101,'ruleset_id':identity,'branch':branch,'writer_app_id':7,'role':'update' if identity==1 else 'protection','metadata_sha256':neutral.identity(repo,value),'updated_at':value['updated_at'],'observed_at':now.isoformat(),'bypass_actors':copy.deepcopy(value['bypass_actors'])}
 packet={'schema_version':1,'repository':'org/repo','repository_id':101,'branch':branch,'writer_app_id':7,'policies':{str(i):observed(i,value) for i,value in policies.items()}}
 sidecar=root/'receipt-policy-observations.json';sidecar.write_text(json.dumps(packet))
 selected=copy.deepcopy(original);selected.update(schema_version=2,observed_at=now.isoformat(),policies={str(i):neutral.identity(repo,value) for i,value in policies.items()});approval.write_text(json.dumps(selected))
 class Hidden(State):
  writes=0
  def request(self,path,method='GET',payload=None):
   assert method=='GET' and payload is None,'policy proof must remain GET-only'
   result=copy.deepcopy(super().request(path,method,payload))
   if '/rulesets/' in path:result.pop('bypass_actors')
   return result
 hidden=Hidden();before=out('rev-parse',ref)
 result=a.verify_bootstrap(hidden,approval,now=now)
 assert result['head']==initial and out('rev-parse',ref)==before
 assert 'bypass_actors' in policies[1] and policies[1]['bypass_actors'][0]['actor_id']==7
 module_spec=importlib.util.spec_from_file_location('reporting_policy',scripts/'factory-reporting-policy.py');rp=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(rp)
 count=2
 def reject(fn,reason):
  global count
  try:fn()
  except ValueError as error:assert reason in str(error),(reason,str(error));count+=1
  else:raise AssertionError('accepted '+reason)
 for identity,value in policies.items():
  capture=rp.capture(repo,value,branch,7,now=now);assert capture==packet['policies'][str(identity)];count+=1
  assert rp.validate(repo,value,branch,7,now=now)['mode']=='direct';count+=1
  hidden_policy=copy.deepcopy(value);hidden_policy.pop('bypass_actors')
  assert rp.validate(repo,hidden_policy,branch,7,capture,now=now)['mode']=='operator-observation';count+=1
  reject(lambda:rp.validate(repo,hidden_policy,branch,7,None,now=now),'observation')
  for key,bad in [('repository','other/repo'),('repository_id',True),('ruleset_id',identity+10),('writer_app_id',8),('branch','other'),('role','unknown'),('metadata_sha256','f'*64),('schema_version',True),('extra','unknown')]:
   changed=copy.deepcopy(capture);changed[key]=bad
   reject(lambda:rp.validate(repo,hidden_policy,branch,7,changed,now=now),'observation')
  changed=copy.deepcopy(capture);changed['observed_at']=(now+timedelta(seconds=1)).isoformat();reject(lambda:rp.validate(repo,hidden_policy,branch,7,changed,now=now),'observation')
  changed=copy.deepcopy(capture);changed['observed_at']=value['updated_at'];reject(lambda:rp.validate(repo,hidden_policy,branch,7,changed,now=now),'observation')
  changed=copy.deepcopy(hidden_policy);changed['name']='changed';reject(lambda:rp.validate(repo,changed,branch,7,capture,now=now),'metadata')
  changed=copy.deepcopy(hidden_policy);changed['updated_at']='2026-10-14T00:00:00.000001Z';reject(lambda:rp.validate(repo,changed,branch,7,capture,now=now),'metadata')
  for actors in (None,[],[{'actor_id':8,'actor_type':'Integration','bypass_mode':'always'}],[{'actor_id':True,'actor_type':'Integration','bypass_mode':'always'}]):
   changed=copy.deepcopy(value);changed['bypass_actors']=actors
   if actors==value['bypass_actors']:continue
   reject(lambda:rp.validate(repo,changed,branch,7,capture,now=now),'actors')
  reject(lambda:rp.capture(repo,hidden_policy,branch,7,now=now),'explicit')
  changed=copy.deepcopy(value);changed['conditions']['ref_name']['include']=['refs/heads/other'];reject(lambda:rp.capture(repo,changed,branch,7,now=now),'scope')
  changed=copy.deepcopy(value);changed['updated_at']=(now-timedelta(seconds=59)).isoformat();reject(lambda:rp.capture(repo,changed,branch,7,now=now),'settle')
 # A positive actor must never become a rewrite/deletion bypass.
 bad=copy.deepcopy(policies[1]);bad['rules'].append({'type':'deletion'});reject(lambda:rp.capture(repo,bad,branch,7,now=now),'update-only')
 bad=copy.deepcopy(policies[2]);bad['bypass_actors']=copy.deepcopy(policies[1]['bypass_actors']);reject(lambda:rp.capture(repo,bad,branch,7,now=now),'actors')
 reject(lambda:neutral.capture(repo,policies[1],now=now),'empty')
 empty=neutral.capture(repo,policies[2],now=now);positive=copy.deepcopy(policies[1]);positive.pop('bypass_actors');reject(lambda:rp.validate(repo,positive,branch,7,empty,now=now),'observation')
 for target in ('../other','branch//child','branch%2Fchild','x\\y','main.lock','x\n'):
  reject(lambda:rp.capture(repo,policies[1],target,7,now=now),'branch')
 reject(lambda:rp.capture(repo,policies[1],branch,True,now=now),'writer')
 assert rp.load(sidecar,'org/repo',101,branch,7)==packet['policies'];count+=1
 raw=sidecar.read_bytes()
 for value in (b'[]',b'null',b'1',b'{"schema_version":1,"schema_version":1}',b'['*10000,b' '*(rp.MAX_BYTES+1)):
  sidecar.write_bytes(value);reject(lambda:rp.load(sidecar,'org/repo',101,branch,7),'observation')
 sidecar.write_bytes(raw)
 changed=copy.deepcopy(packet);changed['extra']=False;sidecar.write_text(json.dumps(changed));reject(lambda:rp.load(sidecar,'org/repo',101,branch,7),'observation');sidecar.write_bytes(raw)
 for key,bad in [('repository','other/repo'),('repository_id',True),('branch','other'),('writer_app_id',8),('schema_version',True)]:
  changed=copy.deepcopy(packet);changed[key]=bad;sidecar.write_text(json.dumps(changed));reject(lambda:rp.load(sidecar,'org/repo',101,branch,7),'observation')
 sidecar.write_bytes(raw)
 # Fixed GET capture preserves actual actor evidence and refuses foreign responses.
 class CaptureAPI:
  def __init__(self):self.paths=[];self.foreign=False
  def get(self,path):
   self.paths.append(path)
   if path=='repos/org/repo':return dict(repo)
   assert path=='repos/org/repo/rulesets/1'
   result=copy.deepcopy(policies[1])
   if self.foreign:result['id']=2
   return result
 transport=CaptureAPI();assert rp.observe(transport,'org/repo',1,branch,7,now=now)==packet['policies']['1'];count+=1
 assert transport.paths==['repos/org/repo','repos/org/repo/rulesets/1'];count+=1
 transport.foreign=True;reject(lambda:rp.observe(transport,'org/repo',1,branch,7,now=now),'scope')
 reject(lambda:rp.observe(transport,'org/repo',True,branch,7,now=now),'identity')
 # Input bounds apply before canonicalization, including cycles and wide frontiers.
 for value in ({'wide':[None]*8192},{'large':'x'*(rp.MAX_BYTES+1)}):
  reject(lambda:rp._canonical(value),'bound')
 cycle=[];cycle.append(cycle);reject(lambda:rp._canonical(cycle),'bound')
 equivalent=copy.deepcopy(policies[1]);equivalent['updated_at']='2026-10-14T11:00:00+11:00'
 assert rp.validate(repo,equivalent,branch,7,now=now)['metadata_sha256']==packet['policies']['1']['metadata_sha256'];count+=1
 # Current live facts are rechecked, including actors omitted from the stable hash.
 class ChangedActors(State):
  def request(self,path,method='GET',payload=None):
   value=copy.deepcopy(super().request(path,method,payload))
   if path.endswith('/rulesets/1'):value['bypass_actors'][0]['actor_id']=8
   return value
 reject(lambda:a.verify_bootstrap(ChangedActors(),approval,now=now),'actors')
 class ChangedDuringVerification(Hidden):
  reads=0
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if path.endswith('/rulesets/1'):
    self.reads+=1
    if self.reads>1:value['name']='changed-during-verification'
   return value
 reject(lambda:a.verify_bootstrap(ChangedDuringVerification(),approval,now=now),'metadata')

 sidecar.unlink();reject(lambda:a.verify_bootstrap(Hidden(),approval,now=now),'observation');sidecar.write_bytes(raw)
 # Version1 remains the exact raw-policy contract, with no automatic fallback.
 approval.write_text(json.dumps(original));reject(lambda:a.verify_bootstrap(Hidden(),approval,now=now),'policy changed')
 assert a.verify_bootstrap(State(),approval,now=now)['head']==initial;count+=1
 assert out('rev-parse',ref)==before and git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print(str(count)+' reporting-only positive policy and real-Git bootstrap cases passed; no live/App capability claim')
'''
exec(compile(fixture+cases,'reporting-positive-policy-fixture','exec'))
PY
