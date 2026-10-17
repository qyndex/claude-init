#!/usr/bin/env bash
# Spec029 AC-9: read-only historical acceptance, never current delivery authority.
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
from pathlib import Path
import importlib.util
path=Path('.claude/scripts/factory-operational-replay.py')
assert path.is_file(), 'independent protected-registry historical replay consumer missing'
s=importlib.util.spec_from_file_location('operational_replay',path);replay=importlib.util.module_from_spec(s);s.loader.exec_module(replay)
# Reuse the committed real-Git fixture without rerunning a producer history suite.
fixture=Path('.claude/scripts/test/factory-operational-producer.sh').read_text()
header="python3 - <<'PY'\n";stop=" patches=api.patches;assert m.retain(api,entry,*materials,guard=still_trusted)"
assert fixture.count(header)==1 and fixture.count(stop)==1, 'fixture splice contract changed'
code=fixture.split(header,1)[1].split(stop,1)[0]
assert 'result=m.retain_completed' in code, 'authenticated fixture setup missing'
# Further replay assertions are appended within the fixture's temporary Git scope.
cases = r"""
 # AC-9: this file is appended inside the committed producer's real-Git fixture.
 class ReplayAPI(API):
  main=new;protected=True;registry=None;number=0
  def __init__(self):
   super().__init__();self.registry={'schema_version':1,'profiles':[copy.deepcopy(entry)]};self.seen={}
  def request(self,path,method='GET',payload=None,raw=False):
   assert method=='GET' and payload is None and raw is False, 'consumer attempted a write/raw request'
   assert '/actions/' not in path, 'expired native run endpoints must not be needed'
   self.number+=1;tail=path.removeprefix('repos/org/repo')
   if tail=='/git/ref/heads/main':value={'ref':'refs/heads/main','object':{'type':'commit','sha':self.main}}
   elif tail=='/branches/main':value={'name':'main','protected':self.protected,'commit':{'sha':self.main}}
   elif tail.startswith('/contents/'+m.REGISTRY+'?ref='):
    encoded=self.registry if type(self.registry) is bytes else m.proof.canonical(self.registry)
    value={'type':'file','path':m.REGISTRY,'sha':m.state.git_hash(encoded),'size':len(encoded),'encoding':'base64','content':base64.b64encode(encoded).decode()}
   else:value=super().request(path,method,payload,raw=raw)
   self.seen[path]=copy.deepcopy(value);return value
 replay_api=ReplayAPI()
 # Deliberately invalid candidate registry is not the protected API trust source.
 with tempfile.TemporaryDirectory() as candidate_directory:
  candidate_root=Path(candidate_directory).resolve();(candidate_root/'factory').mkdir()
  (candidate_root/m.REGISTRY).write_text('{"schema_version":1,"profiles":[{"untrusted":true}]}')
  previous_cwd=Path.cwd()
  try:
   os.chdir(candidate_root)
   assert json.loads(Path(m.REGISTRY).read_bytes())['profiles']==[{'untrusted':True}]
   answer=replay.replay(replay_api,'test',runner=verified_runner,now=late)
  finally:os.chdir(previous_cwd)
 assert answer['type']=='historical-operational-replay' and not any(answer['authority'].values())
 assert answer['record_sha256']==hashlib.sha256(raw).hexdigest() and replay_api.number<128
 replay_checks=0
 def denied(call):
  global replay_checks
  try:call()
  except (ValueError,RuntimeError):replay_checks+=1;return
  raise AssertionError('invalid historical replay accepted')
 for status in ('withdrawn','inactive'):
  negative=ReplayAPI();negative.registry['profiles'][0]['status']=status
  denied(lambda:replay.replay(negative,'test',runner=verified_runner,now=late))
 negative=ReplayAPI();negative.registry['profiles']=[]
 denied(lambda:replay.replay(negative,'test',runner=verified_runner,now=late))
 negative=ReplayAPI();negative.protected=False
 denied(lambda:replay.replay(negative,'test',runner=verified_runner,now=late))
 for area,key,value in [('selections','repeat',{'run_id':22,'attempt':2}),('queue_config','destination','C2'),('original_state','frozen_sha','9'*40),('retention','bootstrap_sha','8'*40)]:
  negative=ReplayAPI();negative.registry['profiles'][0][area][key]=value
  denied(lambda:replay.replay(negative,'test',runner=verified_runner,now=late))
 negative=ReplayAPI();negative.registry['profiles'][0]['repository']['name']='foreign/repo'
 denied(lambda:replay.replay(negative,'test',runner=verified_runner,now=late))
 for malformed in (b'{"schema_version":1,"schema_version":1,"profiles":[]}',b'{"schema_version":1,"profiles":[],"ready":true}'):
  negative=ReplayAPI();negative.registry=malformed
  denied(lambda:replay.replay(negative,'test',runner=verified_runner,now=late))
 # Benign later state publication is accepted if the exact retained leaf stays intact.
 original_leaf=git('show',ref+':'+result['path']).stdout
 moved=[False]
 def advancing_runner(command,**kwargs):
  verified=verified_runner(command,**kwargs)
  if not moved[0]:moved[0]=True;publish('reports/'+'d'*64+'.json',b'later opaque feedback','2026-10-17T03:00:00Z')
  return verified
 assert replay.replay(ReplayAPI(),'test',runner=advancing_runner,now=late)['retained_head']==out('rev-parse',ref)
 negative=ReplayAPI();moved[0]=False
 def profile_race(command,**kwargs):
  verified=verified_runner(command,**kwargs)
  if not moved[0]:moved[0]=True;negative.main='9'*40
  return verified
 denied(lambda:replay.replay(negative,'test',runner=profile_race,now=late))
 moved[0]=False
 def target_race(command,**kwargs):
  verified=verified_runner(command,**kwargs)
  if not moved[0]:moved[0]=True;publish(result['path'],b'changed target','2026-10-17T03:00:01Z')
  return verified
 denied(lambda:replay.replay(ReplayAPI(),'test',runner=target_race,now=late))
 publish(result['path'],original_leaf,'2026-10-17T03:00:02Z')
 # Wrong/corrupted signed material must not gain purpose authority from its location.
 envelope=json.loads(original_leaf)
 for part,key,value in [('record','type','delivery'),('completion','purpose','current-readiness'),('record','profile_sha256','0'*64)]:
  altered=copy.deepcopy(envelope);altered[part][key]=value;publish(result['path'],m.proof.canonical(altered),'2026-10-17T03:00:03Z')
  denied(lambda:replay.replay(ReplayAPI(),'test',runner=verified_runner,now=late))
 altered=copy.deepcopy(envelope);altered['bundle']=base64.b64encode(b'swapped signature').decode();publish(result['path'],m.proof.canonical(altered),'2026-10-17T03:00:04Z')
 denied(lambda:replay.replay(ReplayAPI(),'test',runner=verified_runner,now=late))
 publish(result['path'],original_leaf,'2026-10-17T03:00:05Z')
 class Truncated(ReplayAPI):
  def request(self,path,method='GET',payload=None,raw=False):
   value=super().request(path,method,payload,raw=raw)
   if '/git/trees/' in path:value['truncated']=True
   return value
 denied(lambda:replay.replay(Truncated(),'test',runner=verified_runner,now=late))
 reader=replay.ReadOnly(ReplayAPI())
 for unused in range(128):reader.request('repos/org/repo')
 denied(lambda:reader.request('repos/org/repo'))
 # Actual existing authority boundaries refuse operational subjects.
 coordinator=m.state.digest.coordinator;contract=coordinator.contract
 context={'schema_version':1,'repository':'org/repo','pull_request':1,'head_sha':'a'*40,'base_sha':'b'*40,'spec_sha256':'c'*64,'policy_sha256':'d'*64,'ac_ids':['AC-9'],'implementer':'author','allowed_verifiers':['v'],'allowed_reviewers':['r'],'required_checks':{'test':1},'window_start':'2026-10-17T00:00:00Z','window_end':'2026-10-18T00:00:00Z'}
 denied(lambda:contract.validate(context,record))
 ledger=m.module('operational_ledger_boundary','factory-ledger.py')
 database=root/'must-not-exist.sqlite'
 denied(lambda:ledger.confirm_merge(database,'T-318','a'*64,record));assert not database.exists()
 denied(lambda:coordinator.coordinate(None,record,1,merge=True))
 preflight=m.module('operational_readiness_boundary','factory-preflight.py')
 readiness=preflight.reporting_readiness(record,None,None)
 assert readiness['checks']['protected_origin']['status']=='failed'
 assert all(readiness['checks'][name]['status']=='not_checked' for name in ('installed_app','native_cadence','operator_cutover'))
 # Isolate the actual delivery-document schema boundary after synthetic source auth.
 receipts=m.module('operational_delivery_boundary','factory-receipts.py')
 saved_source=receipts.authenticate_source;saved_artifact=receipts.receipt_artifact
 class DeliveryAPI:
  repo='org/repo'
  def get(self,path):return {'id':99,'run_attempt':1,'repository':{'full_name':'org/repo'},'workflow_id':999,'event':'workflow_dispatch','head_branch':'main','status':'completed','conclusion':'success','path':receipts.RUNTIME_PATHS[0],'head_sha':'a'*40}
 try:
  receipts.authenticate_source=lambda *a,**kw:({}, {}, None, None)
  receipts.receipt_artifact=lambda *a,**kw:(record,{})
  denied(lambda:receipts.authenticate(DeliveryAPI(),{'repository':'org/repo','base_branch':'main','receipts':{'workflow_id':999}},99))
 finally:receipts.authenticate_source=saved_source;receipts.receipt_artifact=saved_artifact
 # Fresh process replays the actual retained Git fixture through read-only API snapshots.
 snapshot_api=ReplayAPI();replay.replay(snapshot_api,'test',runner=verified_runner,now=late)
 snapshot=root/'replay-source-fixture.json';snapshot.write_text(json.dumps({'responses':snapshot_api.seen,'certificate':cert,'now':late.isoformat()}))
 child=root/'replay-child.py';child.write_text('''import importlib.util,json,sys,subprocess,hashlib
from pathlib import Path
from datetime import datetime
spec=importlib.util.spec_from_file_location('consumer',sys.argv[1]);consumer=importlib.util.module_from_spec(spec);spec.loader.exec_module(consumer)
fixture=json.loads(Path(sys.argv[2]).read_text())
class API:
 repo='org/repo'
 def request(self,path,method='GET',payload=None):
  assert method=='GET' and payload is None and '/actions/' not in path
  return fixture['responses'][path]
def runner(command,**kwargs):
 raw=Path(command[3]).read_bytes();body=json.loads(raw);cert=dict(fixture['certificate']);when='2026-10-17T02:00:01.9Z'
 cert['runInvocationURI']='https://github.com/org/repo/actions/runs/'+str(body['verification']['run_id'])+'/attempts/'+str(body['verification']['attempt'])
 if body['type']=='historical-queue-completion-observation':
  uri='https://github.com/org/repo/'+consumer.producer.RETAINER+'@refs/heads/main';cert.update(subjectAlternativeName=uri,buildSignerURI=uri,buildTrigger='workflow_run');when='2026-10-17T02:30:01.9Z'
 value=[{'verificationResult':{'signature':{'certificate':cert},'verifiedTimestamps':[{'type':'Tlog','uri':'https://rekor.example.test','timestamp':when}],'statement':{'_type':'https://in-toto.io/Statement/v1','predicateType':'https://slsa.dev/provenance/v1','subject':[{'digest':{'sha256':hashlib.sha256(raw).hexdigest()}}]}}}]
 return subprocess.CompletedProcess(command,0,json.dumps(value).encode(),b'')
result=consumer.replay(API(),'test',runner=runner,now=datetime.fromisoformat(fixture['now']))
assert result['type']=='historical-operational-replay' and not any(result['authority'].values())
print('fresh-process read-only replay PASS; synthetic API/certificate fixture, no native credit')
''')
 child_result=m.transport.process.run([__import__('sys').executable,str(child),str(Path('.claude/scripts/factory-operational-replay.py').resolve()),str(snapshot)],env={key:os.environ[key] for key in ('PATH','HOME') if key in os.environ},cwd=root,timeout=60,limit=100000)
 assert child_result.returncode==0,child_result.stderr.decode();print(child_result.stdout.decode().strip())
 # Real57-file immutable source families: current working files/registry are untrusted.
 with tempfile.TemporaryDirectory() as directory:
  history=Path(directory).resolve();(history/'.claude/scripts').mkdir(parents=True);(history/'.github/workflows').mkdir(parents=True);(history/'factory').mkdir()
  def history_git(*args):return subprocess.run(['git','-C',str(history),*args],capture_output=True,check=True).stdout.decode().strip()
  history_git('init','-q');history_git('config','user.name','Fixture');history_git('config','user.email','fixture@example.invalid')
  for i in range(57):(history/f'.claude/scripts/module-{i:02}.py').write_text(f'value={i}\n')
  for name in (m.evidence.WORKFLOW,m.SIGNER,m.RETAINER):(history/name).write_text('reviewed workflow fixture\n')
  (history/m.REGISTRY).write_text('{"schema_version":1,"profiles":[]}')
  history_git('add','.');history_git('commit','-qm','original source');old_source=history_git('rev-parse','HEAD')
  old_runtime={'.claude/scripts/'+p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (history/'.claude/scripts').iterdir()};old_runtime[m.evidence.WORKFLOW]=hashlib.sha256((history/m.evidence.WORKFLOW).read_bytes()).hexdigest()
  for i in range(57):(history/f'.claude/scripts/module-{i:02}.py').write_text(f'value={i+100}\n')
  history_git('add','.');history_git('commit','-qm','producer source');new_source=history_git('rev-parse','HEAD')
  large=copy.deepcopy(entry);large['original'].update(source_sha=old_source,runtime=old_runtime);large['retention']['bootstrap_sha']=out('rev-parse',ref)
  family={'.claude/scripts/'+p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (history/'.claude/scripts').iterdir()}
  large['producer']['runtime']=dict(family,**{m.SIGNER:hashlib.sha256((history/m.SIGNER).read_bytes()).hexdigest()});large['retainer']['runtime']=dict(family,**{m.RETAINER:hashlib.sha256((history/m.RETAINER).read_bytes()).hexdigest()})
  large_record=copy.deepcopy(record);large_record['original'].update(large['original']);large_record['verification'].update(source_sha=new_source,runtime=large['producer']['runtime']);large_record['profile_sha256']=hashlib.sha256(m.proof.canonical(large)).hexdigest();large_raw=m.proof.canonical(large_record)
  large_completion=json.loads(completion_raw);large_completion['profile_sha256']=large_record['profile_sha256'];large_completion['upstream'].update(source_sha=new_source,record_sha256=hashlib.sha256(large_raw).hexdigest());large_completion['verification'].update(source_sha=new_source,runtime=large['retainer']['runtime'])
  large_materials=(large_raw,bundle,m.proof.canonical(large_completion),completion_bundle)
  m.retain(api,large,*large_materials,guard=lambda:True)  # Mechanical synthetic fixture, not native authentication.
  large_api=ReplayAPI();large_api.registry={'schema_version':1,'profiles':[large]};large_api.main=new_source
  (history/'.claude/scripts/module-00.py').write_text('untrusted current working content')
  saved_cert=copy.deepcopy(cert);cert.update(buildSignerDigest=new_source,sourceRepositoryDigest=new_source)
  try:
   large_answer=replay.replay(large_api,'test',checkout=history,runner=verified_runner,now=late)
   assert large_answer['original_source_sha']==old_source and large_api.number<128
   assert not any('/contents/.claude/scripts' in path for path in large_api.seen)
   empty=history/'empty';empty.mkdir();subprocess.run(['git','-C',str(empty),'init','-q'],check=True)
   denied(lambda:replay.replay(large_api,'test',checkout=empty,runner=verified_runner,now=late))
  finally:cert.clear();cert.update(saved_cert)
 print('operational replay PASS; negatives='+str(replay_checks)+'; fresh-process and57-file realGit runtime families; synthetic signature/API fixtures only')
"""
exec(compile(code+'\n'+cases,'<operational-replay-cases>','exec'))
PY
