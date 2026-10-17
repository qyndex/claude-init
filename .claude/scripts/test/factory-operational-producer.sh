#!/usr/bin/env bash
# Spec029 AC-9: protected historical producer/retainer, local fixtures only.
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
from pathlib import Path
p=Path('.claude/scripts/factory-operational-producer.py')
assert p.is_file(), 'protected historical producer and completed-run retainer missing'
import importlib.util
s=importlib.util.spec_from_file_location('operational_producer',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
assert hasattr(m.proof,'verify_completion'), 'durable signed upstream-completion assertion missing'
# Test empty-registry semantics without assuming adopter configuration is empty.
import tempfile
with tempfile.TemporaryDirectory() as empty_registry:
 empty_root=Path(empty_registry).resolve();(empty_root/'factory').mkdir()
 (empty_root/m.REGISTRY).write_text('{"schema_version":1,"profiles":[]}')
 assert m.load_registry(empty_root)['profiles']==[]
assert m.role('org/repo','test','a'*40)==m.role('org/repo','test','a'*40)
assert m.role('org/repo','test','a'*40)!=m.role('org/repo','other','a'*40)
# Written before production implementation; real-Git state and native-API fixtures.
import base64,copy,hashlib,json,os,stat,subprocess,tempfile,zipfile,io
from datetime import datetime,timezone
repo={'name':'org/repo','id':101,'private':False};old='a'*40;new='b'*40
queue={'enabled':True,'queue_monitor_enabled':True,'repository':'org/repo','state_repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','grace_minutes':60}
files={'old':{'.github/workflows/factory-reporting-queue.yml':b'old workflow','.claude/scripts/factory-reporting-queue.py':b'old runtime'},'new':{'.github/workflows/factory-operational-proof.yml':b'signer workflow','.claude/scripts/factory-operational-producer.py':b'producer runtime'}}
files['new'][m.RETAINER]=b'retainer workflow'
def runtime(kind,workflow=None):return {p:hashlib.sha256(v).hexdigest() for p,v in files[kind].items() if not p.startswith('.github/workflows/') or p==(workflow or (m.evidence.WORKFLOW if kind=='old' else m.SIGNER))}
entry={'profile_id':'test','status':'active','repository':repo,'branch':'main','original':{'source_sha':old,'workflow_path':'.github/workflows/factory-reporting-queue.yml','workflow_id':10,'runtime':runtime('old')},'producer':{'workflow_path':'.github/workflows/factory-operational-proof.yml','workflow_id':11,'runtime':runtime('new')},'selections':{r:{'run_id':20+i,'attempt':1} for i,r in enumerate(('drill','recovery','repeat'))},'queue_config':queue,'original_state':{'branch':'state','bootstrap_sha':'c'*40,'frozen_sha':'d'*40},'retention':{'branch':'state','bootstrap_sha':'e'*40}}
entry['retainer']={'workflow_path':m.RETAINER,'workflow_id':12,'runtime':runtime('new',m.RETAINER)}
now=datetime(2026,10,17,2,0,0,500000,tzinfo=timezone.utc)
native={'id':40,'run_attempt':2,'workflow_id':11,'path':entry['producer']['workflow_path'],'head_sha':new,'head_branch':'main','event':'workflow_dispatch','status':'in_progress','conclusion':None,'repository':{'id':101,'full_name':'org/repo'},'head_repository':{'id':101,'full_name':'org/repo'},'run_started_at':'2026-10-17T02:00:00Z','updated_at':'2026-10-17T02:00:00Z'}
count=0
def reject(fn):
 global count
 try:fn()
 except (ValueError,RuntimeError):count+=1;return
 raise AssertionError('invalid operational input accepted')
m.validate_entry(entry)
for field,value in [('status','revoked'),('profile_id','../bad')]:
 bad=copy.deepcopy(entry);bad[field]=value;reject(lambda:m.validate_entry(bad))
class Source:
 repo='org/repo'
 def __init__(self):self.calls=[];self.corrupt=False;self.native=copy.deepcopy(native)
 def request(self,path,method='GET',payload=None,raw=False):
  assert method=='GET' and payload is None;self.calls.append((path,raw));tail=path.removeprefix('repos/org/repo')
  if not tail:return {'id':101,'full_name':self.repo,'private':False,'archived':False,'default_branch':'main'}
  if tail=='/git/ref/heads/main':return {'ref':'refs/heads/main','object':{'type':'commit','sha':new}}
  if tail.startswith('/contents/.claude/scripts?ref='):
   sha=tail.split('=')[1]
   return [{'name':p.rsplit('/',1)[1],'path':p,'type':'file'} for p in files['old' if sha==old else 'new'] if p.startswith('.claude/scripts/') and p.endswith('.py')]
  if tail.startswith('/contents/'):
   p,sha=tail[len('/contents/'):].split('?ref=')
   if p not in files['old' if sha==old else 'new']:raise ValueError('native content unavailable')
   data=files['old' if sha==old else 'new'][p]
   return {'type':'file','path':p,'sha':m.state.git_hash(data),'size':len(data),'encoding':'base64','content':base64.b64encode(b'corrupt' if self.corrupt else data).decode()}
  if tail in ('/actions/runs/40','/actions/runs/40/attempts/2'):return copy.deepcopy(self.native)
  if tail.startswith('/actions/runs/') and '/jobs?' not in tail:
   identity=int(tail.split('/')[3]);i=identity-20
   return {'id':identity,'run_attempt':1 if '/attempts/' in tail else 2,'workflow_id':10,'path':entry['original']['workflow_path'],'head_sha':old,'head_branch':'main','event':'workflow_dispatch','status':'completed','conclusion':'success','repository':{'id':101,'full_name':self.repo},'head_repository':{'id':101,'full_name':self.repo},'created_at':f'2026-10-16T01:0{i}:00Z','run_started_at':f'2026-10-16T01:0{i}:00Z','updated_at':f'2026-10-16T01:0{i}:10Z'}
  if '/attempts/' in tail and '/jobs?' in tail:
   identity=int(tail.split('/')[3]);i=identity-20
   return {'total_count':1,'jobs':[{'id':30+i,'run_id':identity,'run_attempt':1,'head_sha':old,'name':'monitor','status':'completed','conclusion':'success','steps':[{'number':1,'name':m.evidence.STEP,'status':'completed','conclusion':'success'}]}]}
  if tail.startswith('/actions/jobs/'):
   i=int(tail.split('/')[3])-30;counts=([1,0],[1],[0])[i]
   return b''.join(('2026-10-16T01:0%d:05Z '%i+json.dumps({'notifications':n,'reconciled':0})+'\n').encode() for n in counts)
  raise AssertionError(path)
source=Source()
omitted=copy.deepcopy(entry);omitted['producer']['runtime'].pop('.claude/scripts/factory-operational-producer.py')
reject(lambda:m.resolve_profile(source,omitted,native))
expected=m.resolve_profile(source,entry,native)
assert expected['producer']['source_sha']==new and expected['original']['source_sha']==old
source.corrupt=True;reject(lambda:m.resolve_profile(source,entry,native));source.corrupt=False
observed=m.observe_runs(source,entry,now)
assert [r['notifications'] for r in observed]==[[1,0],[1],[0]]
assert all('/attempts/1' in path for path,rawflag in source.calls if any(path=='repos/org/repo/actions/runs/'+str(i) or path.startswith('repos/org/repo/actions/runs/'+str(i)+'/attempts/') for i in (20,21,22)))
bad=copy.deepcopy(native);bad['head_sha']=old;reject(lambda:m.resolve_profile(source,entry,bad))
for key,value in [('workflow_id',True),('event','pull_request_target'),('head_branch','foreign')]:
 bad=copy.deepcopy(native);bad[key]=value;reject(lambda:m.resolve_profile(source,entry,bad))
class BadLogs(Source):
 def request(self,path,method='GET',payload=None,raw=False):
  value=super().request(path,method,payload,raw=raw)
  return b'2026-10-16T01:00:05Z {"notifications":999,"reconciled":0}\n' if path.endswith('/logs') else value
reject(lambda:m.observe_runs(BadLogs(),entry,now))
# ZIPs are data only: exact names, bounded bytes, no path/symlink extraction.
def archive(items):
 out=io.BytesIO()
 with zipfile.ZipFile(out,'w') as z:
  for name,data in items:z.writestr(name,data)
 return out.getvalue()
assert m.unpack(archive([('evidence.json',b'{}'),('provenance.sigstore.json',b'bundle')]))==(b'{}',b'bundle')
for items in [[('../evidence.json',b'{}'),('provenance.sigstore.json',b'x')],[('evidence.json',b'{}')],[('evidence.json',b'{}'),('provenance.sigstore.json',b'x'),('run.sh',b'no')],[('evidence.json',b'x'*262145),('provenance.sigstore.json',b'x')]]:reject(lambda:m.unpack(archive(items)))
outzip=io.BytesIO()
with zipfile.ZipFile(outzip,'w') as z:
 link=zipfile.ZipInfo('evidence.json');link.external_attr=(stat.S_IFLNK|0o777)<<16;z.writestr(link,b'elsewhere');z.writestr('provenance.sigstore.json',b'x')
reject(lambda:m.unpack(outzip.getvalue()))
with tempfile.TemporaryDirectory() as folder:
 root=Path(folder);gitroot=root/'git';gitroot.mkdir()
 def git(*args,input=None,env=None,check=True):return subprocess.run(['git','-C',str(gitroot),*args],input=input,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=check)
 def out(*args):return git(*args).stdout.decode().strip()
 git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid')
 (gitroot/'README.md').write_text('data only');(gitroot/'reports').mkdir();opaque='reports/'+'f'*64+'.json';(gitroot/opaque).write_bytes(b'opaque encrypted feedback')
 git('add','.');git('commit','-qm','reviewed bootstrap');bootstrap=out('rev-parse','HEAD');ref='refs/heads/state';git('update-ref',ref,bootstrap)
 def blob(data):return git('hash-object','-w','--stdin',input=data).stdout.decode().strip()
 class API(Source):
  lost=False;before=None;patches=0
  def request(self,path,method='GET',payload=None,raw=False):
   tail=path.removeprefix('repos/org/repo/');p=tail
   if method=='GET':
    if p.startswith('rules/branches/'):return [{'type':'non_fast_forward','ruleset_id':1},{'type':'deletion','ruleset_id':1}]
    if p=='rulesets/1':return {'enforcement':'active','bypass_actors':[]}
    if p=='git/ref/heads/state':return {'ref':ref,'object':{'type':'commit','sha':out('rev-parse',ref)}}
    if p.startswith('compare/'):
     base,head=p[len('compare/'):].split('?')[0].split('...');ancestor=git('merge-base','--is-ancestor',base,head,check=False).returncode==0;merged=git('merge-base',base,head,check=False).stdout.decode().strip()
     return {'base_commit':{'sha':base},'merge_base_commit':{'sha':merged},'status':('identical' if base==head else 'ahead') if ancestor else 'diverged','behind_by':0 if ancestor else 1,'ahead_by':0 if base==head else 1,'total_commits':0 if base==head else 1}
    if p.startswith('git/commits/'):
     sha=p.rsplit('/',1)[1];parts=out('show','-s','--format=%T %P',sha).split();return {'sha':sha,'tree':{'sha':parts[0]},'parents':[{'sha':v} for v in parts[1:]],'committer':{'date':out('show','-s','--format=%cI',sha)}}
    if p.startswith('git/trees/'):
     sha=p.rsplit('/',1)[1].split('?')[0];rows=[];args=['ls-tree']+(['-r'] if '?' in p else [])+[sha]
     for line in out(*args).splitlines():
      mode,kind,tail=line.split(' ',2);identity,name=tail.split('\t');rows.append({'path':name,'mode':mode,'type':kind,'sha':identity,'size':int(out('cat-file','-s',identity))})
     return {'sha':sha,'truncated':False,'tree':rows}
    if p.startswith('git/blobs/'):
     sha=p.rsplit('/',1)[1];data=git('cat-file','blob',sha).stdout;return {'sha':sha,'size':len(data),'encoding':'base64','content':base64.b64encode(data).decode()}
    return super().request(path,method,payload,raw=raw)
   if method=='POST' and p=='git/blobs':return {'sha':blob(base64.b64decode(payload['content']))}
   if method=='POST' and p=='git/trees':
    index=root/'index';index.unlink(missing_ok=True);env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',payload['base_tree'],env=env)
    for item in payload['tree']:git('update-index','--add','--cacheinfo',item['mode']+','+item['sha']+','+item['path'],env=env)
    sha=git('write-tree',env=env).stdout.decode().strip();index.unlink();return {'sha':sha}
   if method=='POST' and p=='git/commits':
    sha=git('commit-tree',payload['tree'],'-p',payload['parents'][0],input=payload['message'].encode()).stdout.decode().strip();return {'sha':sha,'tree':{'sha':payload['tree']},'parents':[{'sha':v} for v in payload['parents']]}
   if method=='PATCH':
    assert p=='git/refs/heads/state' and payload['force'] is False;self.patches+=1
    if self.before:callback=self.before;self.before=None;callback()
    current=out('rev-parse',ref)
    if git('merge-base','--is-ancestor',current,payload['sha'],check=False).returncode:raise ValueError('real CAS conflict')
    git('update-ref',ref,payload['sha'],current)
    if self.lost:self.lost=False;raise RuntimeError('lost acknowledgement')
    return {'ref':ref,'object':{'sha':payload['sha']}}
   raise AssertionError((path,method))
 api=API()
 def publish(path,data,when):
  oldhead=out('rev-parse',ref);tree=api.request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':path,'mode':'100644','type':'blob','sha':blob(data)}]})['sha'];env=dict(os.environ,GIT_COMMITTER_DATE=when,GIT_AUTHOR_DATE=when);sha=git('commit-tree',tree,'-p',oldhead,input=b'fixture publication',env=env).stdout.decode().strip();git('update-ref',ref,sha,oldhead)
 q=m.queue;identity=q.stream(queue);path='reports/'+identity+'.json';journal={'schema_version':1,'repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','stream':identity,'events':[]}
 publish(path,q.canonical(journal),'2026-10-16T01:00:01Z')
 row={'kind':'drill','run_id':20,'run_attempt':1,'cutoff':'2026-10-16T01:00:02.000000Z','status':'pending','message_id':None,'incident':None};row['key']=q.event_key(identity,row);row['incident']=row['key'];journal['events'].append(row);publish(path,q.canonical(journal),'2026-10-16T01:00:02Z');row.update(status='confirmed',message_id='1.000001');publish(path,q.canonical(journal),'2026-10-16T01:00:03Z')
 row={'kind':'recovery','run_id':None,'run_attempt':None,'cutoff':'2026-10-16T01:01:01.000000Z','status':'pending','message_id':None,'incident':journal['events'][0]['key']};row['key']=q.event_key(identity,row);journal['events'].append(row);publish(path,q.canonical(journal),'2026-10-16T01:01:01Z');row.update(status='confirmed',message_id='2.000001');publish(path,q.canonical(journal),'2026-10-16T01:01:02Z')
 entry['original_state'].update(bootstrap_sha=bootstrap,frozen_sha=out('rev-parse',ref));entry['retention']['bootstrap_sha']=out('rev-parse',ref)
 summary=m.observe_state(api,entry,observed)
 assert summary['publication_count']==5 and summary['head_sha']==out('rev-parse',ref)
 frozen=entry['original_state']['frozen_sha'];git('update-ref',ref,bootstrap,frozen)
 reject(lambda:m.observe_state(api,entry,observed));git('update-ref',ref,frozen,bootstrap)
 # Later opaque state advances remain valid ancestors of the immutable original.
 publish('reports/'+'c'*64+'.json',b'later opaque state','2026-10-17T01:00:00Z')
 assert m.observe_state(api,entry,observed)==summary
 entry['retention']['bootstrap_sha']=out('rev-parse',ref)
 record=m.produce(api,entry,native,now=now);assert record['original']['runs']==observed and record['original']['state']==summary
 raw=m.proof.canonical(record);bundle=b'fixture-only-bundle'
 def still_trusted():return True
 # Actual composition: completed native fixture + bounded ZIP + real336 verifier seam before CAS.
 completed=copy.deepcopy(native);completed.update(status='completed',conclusion='success',updated_at='2026-10-17T02:00:02Z')
 class ArtifactSource(Source):
  bad_artifact=False;duplicate=False
  def request(self,path,method='GET',payload=None,raw=False):
   tail=path.removeprefix('repos/org/repo')
   if tail=='/actions/runs/40/attempts/2/jobs?per_page=100&page=1':return {'total_count':1,'jobs':[{'id':500,'run_id':40,'run_attempt':2,'head_sha':new,'name':'sign','status':'completed','conclusion':'success'}]}
   if tail=='/actions/runs/40/artifacts?per_page=100&page=1':
    item={'id':501,'name':'factory-operational-proof-test-40-2','expired':self.bad_artifact,'size_in_bytes':1000,'workflow_run':{'id':40,'head_sha':new}}
    other=dict(item,id=502,name=item['name'] if self.duplicate else 'factory-operational-proof-test-40-3')
    return {'total_count':2,'artifacts':[item,other]}
   if tail=='/actions/artifacts/501/zip':return archive([('evidence.json',record_raw),('provenance.sigstore.json',bundle)])
   return super().request(path,method,payload,raw=raw)
 record_raw=raw;artifact_source=ArtifactSource();uri='https://github.com/org/repo/'+entry['producer']['workflow_path']+'@refs/heads/main'
 # AC-9: completed_artifact must compose with the actual bounded evidence client,
 # not only the in-process API fixture that bypasses raw endpoint selection.
 with tempfile.TemporaryDirectory() as transport_directory:
  transport_root=Path(transport_directory);tools=transport_root/'tools';tools.mkdir();responses={}
  for endpoint in ('repos/org/repo/actions/runs/40/attempts/2/jobs?per_page=100&page=1','repos/org/repo/actions/runs/40/artifacts?per_page=100&page=1','repos/org/repo/actions/artifacts/501/zip'):
   value=artifact_source.request(endpoint,raw=endpoint.endswith('/zip'))
   responses[endpoint]={'raw':base64.b64encode(value).decode()} if type(value) is bytes else {'json':value}
  data=transport_root/'responses.json';data.write_text(json.dumps(responses))
  stub=tools/'gh';stub.write_text('#!'+__import__('sys').executable+'\n'+f'DATA={str(data)!r}\n'+'''import base64,json,sys
from pathlib import Path
arguments=sys.argv[1:];prefix=['api','--hostname','github.com','--method','GET']
assert arguments[:5]==prefix and len(arguments) in (6,7)
endpoint=arguments[-1];item=json.loads(Path(DATA).read_text())[endpoint]
assert arguments==prefix+(['--allow-escape-sequences'] if 'raw' in item else [])+[endpoint]
sys.stdout.buffer.write(base64.b64decode(item['raw']) if 'raw' in item else json.dumps(item['json']).encode())
''');stub.chmod(0o755)
  prior_environment=dict(os.environ)
  try:
   os.environ['PATH']=str(tools)+os.pathsep+os.environ['PATH']
   observed_artifact=m.completed_artifact(m.evidence.GitHub('org/repo'),completed,'test')
   captured_zip=base64.b64decode(responses['repos/org/repo/actions/artifacts/501/zip']['raw'])
   assert observed_artifact==(raw,bundle,{'job_id':500,'artifact_id':501,'artifact_sha256':hashlib.sha256(captured_zip).hexdigest()})
  finally:os.environ.clear();os.environ.update(prior_environment)
 observer=copy.deepcopy(native);observer.update(id=50,run_attempt=1,workflow_id=12,path=m.RETAINER,event='workflow_run',run_started_at='2026-10-17T02:30:00Z',updated_at='2026-10-17T02:30:00Z')
 cert={'issuer':'https://token.actions.githubusercontent.com','subjectAlternativeName':uri,'buildSignerURI':uri,'buildSignerDigest':new,'sourceRepositoryURI':'https://github.com/org/repo','sourceRepositoryIdentifier':'101','sourceRepositoryDigest':new,'sourceRepositoryRef':'refs/heads/main','buildTrigger':'workflow_dispatch','runnerEnvironment':'github-hosted','runInvocationURI':'https://github.com/org/repo/actions/runs/40/attempts/2'}
 completion_cert_bad=False
 def verified_runner(command,**kwargs):
  assert command[:3]==['gh','attestation','verify'] and kwargs['timeout']==60
  assert 'FACTORY_REPORTING_APP_TOKEN' not in kwargs['env']
  subject=Path(command[3]).read_bytes();body=json.loads(subject);signing=copy.deepcopy(cert);signing['runInvocationURI']='https://github.com/org/repo/actions/runs/'+str(body['verification']['run_id'])+'/attempts/'+str(body['verification']['attempt']);when='2026-10-17T02:00:01.9Z'
  if body['type']=='historical-queue-completion-observation':
   observer_uri='https://github.com/org/repo/'+m.RETAINER+'@refs/heads/main'
   signing.update(subjectAlternativeName=observer_uri,buildSignerURI=observer_uri,buildTrigger='workflow_run',runInvocationURI='https://github.com/org/repo/actions/runs/'+str(body['verification']['run_id'])+'/attempts/'+str(body['verification']['attempt']))
   if completion_cert_bad:signing['buildTrigger']='workflow_dispatch'
   when='2026-10-17T02:30:01.9Z'
  value=[{'verificationResult':{'signature':{'certificate':signing},'verifiedTimestamps':[{'type':'Tlog','uri':'https://rekor.example.test','timestamp':when}],'statement':{'_type':'https://in-toto.io/Statement/v1','predicateType':'https://slsa.dev/provenance/v1','subject':[{'name':'evidence.json','digest':{'sha256':hashlib.sha256(subject).hexdigest()}}]}}}]
  return subprocess.CompletedProcess(command,0,json.dumps(value).encode(),b'')
 late=datetime(2026,10,17,3,tzinfo=timezone.utc);observation_time=datetime(2026,10,17,2,30,0,500000,tzinfo=timezone.utc)
 artifact_source.bad_artifact=True;before=out('rev-parse',ref)
 reject(lambda:m.prepare_completion(artifact_source,entry,completed,observer,runner=verified_runner,now=observation_time))
 assert out('rev-parse',ref)==before and api.patches==0;artifact_source.bad_artifact=False
 saved=cert['buildTrigger'];cert['buildTrigger']='pull_request_target'
 reject(lambda:m.prepare_completion(artifact_source,entry,completed,observer,runner=verified_runner,now=observation_time))
 assert out('rev-parse',ref)==before and api.patches==0;cert['buildTrigger']=saved
 artifact_source.duplicate=True;reject(lambda:m.prepare_completion(artifact_source,entry,completed,observer,runner=verified_runner,now=observation_time));artifact_source.duplicate=False
 first,bundle_copy,completion_raw=m.prepare_completion(artifact_source,entry,completed,observer,runner=verified_runner,now=observation_time)
 assert (first,bundle_copy)==(raw,bundle)
 completion_bundle=b'synthetic-completion-bundle';materials=(raw,bundle,completion_raw,completion_bundle)
 producer_profile=m.resolve_profile(artifact_source,entry,completed)
 observer_profile=m.completion_profile(artifact_source,entry,completed,observer)
 # Durable replay needs no native run API: both verified certificates and current trusted profiles.
 assert m.proof.verify_durable(*materials,producer_profile,observer_profile,runner=verified_runner,now=late)==record
 reject(lambda:m.proof.validate_record(completion_raw,producer_profile,now=late))
 reject(lambda:m.proof.validate_completion(raw,observer_profile,now=late))
 for area,key,value in [('selections','repeat',{'run_id':22,'attempt':2}),('original_state','frozen_sha','9'*40),('queue_config','destination','C2'),('retention','bootstrap_sha','8'*40)]:
  altered=copy.deepcopy(entry);altered[area][key]=value
  reject(lambda:m.retain_completed(artifact_source,api,altered,completed,observer,materials,guard=still_trusted,runner=verified_runner,now=late))
  assert out('rev-parse',ref)==before and api.patches==0
 for key,value in [('record_sha256','0'*64),('bundle_sha256','0'*64),('run_id',41),('attempt',3),('status','in_progress'),('completed_at','2026-10-17T03:30:00Z')]:
  altered=json.loads(completion_raw);altered['upstream'][key]=value
  reject(lambda:m.proof.verify_durable(raw,bundle,m.proof.canonical(altered),completion_bundle,producer_profile,observer_profile,runner=verified_runner,now=late))
 for key,value in [('purpose','current-readiness'),('type','delivery'),('profile_sha256','0'*64),('schema_version',True)]:
  altered=json.loads(completion_raw);altered[key]=value
  reject(lambda:m.proof.verify_completion(m.proof.canonical(altered),completion_bundle,observer_profile,runner=verified_runner,now=late))
 completion_cert_bad=True
 reject(lambda:m.retain_completed(artifact_source,api,entry,completed,observer,materials,guard=still_trusted,runner=verified_runner,now=late));completion_cert_bad=False
 assert api.patches==0
 result=m.retain_completed(artifact_source,api,entry,completed,observer,materials,guard=still_trusted,runner=verified_runner,now=late)
 assert observer['status']=='in_progress'  # Assertion observes completed UPSTREAM, no self-completion cycle.
 assert result['status']=='applied' and git('show',ref+':'+opaque).stdout==b'opaque encrypted feedback'
 patches=api.patches;assert m.retain(api,entry,*materials,guard=still_trusted)['status']=='already-applied' and api.patches==patches
 retained_before=git('show',ref+':'+result['path']).stdout
 observer2=copy.deepcopy(observer);observer2['run_attempt']=2
 first2,bundle2,completion2=m.prepare_completion(artifact_source,entry,completed,observer2,runner=verified_runner,now=observation_time)
 second_materials=(first2,bundle2,completion2,b'second-completion-fixture-bundle')
 assert second_materials!=materials
 assert m.retain_completed(artifact_source,api,entry,completed,observer2,second_materials,guard=still_trusted,runner=verified_runner,now=late)['status']=='already-applied'
 assert api.patches==patches and git('show',ref+':'+result['path']).stdout==retained_before
 replacement=copy.deepcopy(record);replacement['verification']['run_id']=41;replacement_raw=m.proof.canonical(replacement)
 replacement_completion=json.loads(completion2);replacement_completion['upstream'].update(run_id=41,record_sha256=hashlib.sha256(replacement_raw).hexdigest())
 replacement_run=dict(completed,id=41)
 reject(lambda:m.retain_completed(artifact_source,api,entry,replacement_run,observer2,(replacement_raw,bundle,m.proof.canonical(replacement_completion),completion_bundle),guard=still_trusted,runner=verified_runner,now=late))
 assert api.patches==patches and git('show',ref+':'+result['path']).stdout==retained_before

 # Corrupted existing envelope cannot be accepted just because upstream identity matches.
 corrupted=json.loads(retained_before);corrupted['completion']['upstream']['record_sha256']='0'*64
 publish(result['path'],m.proof.canonical(corrupted),'2026-10-17T03:00:00Z')
 reject(lambda:m.retain_completed(artifact_source,api,entry,completed,observer2,second_materials,guard=still_trusted,runner=verified_runner,now=late))
 publish(result['path'],retained_before,'2026-10-17T03:00:01Z')

 bad=copy.deepcopy(record);bad['verification']['attempt']=3;reject(lambda:m.retain(api,entry,m.proof.canonical(bad),bundle,completion_raw,completion_bundle,guard=still_trusted))
 reject(lambda:m.retain(api,dict(entry,profile_id='different'),*materials,guard=still_trusted))
 # Mechanical CAS tests below use locally adjusted synthetic completion material, NOT native proof.
 def mechanical_materials(target,document,upstream_bundle=bundle):
  encoded=m.proof.canonical(document);observed=json.loads(completion_raw)
  observed.update(profile_id=target['profile_id'],profile_sha256=document['profile_sha256'])
  observed['upstream'].update(record_sha256=hashlib.sha256(encoded).hexdigest(),bundle_sha256=hashlib.sha256(upstream_bundle).hexdigest())
  return encoded,upstream_bundle,m.proof.canonical(observed),completion_bundle
 entry2=copy.deepcopy(entry);entry2['profile_id']='lost';entry2['retention']['bootstrap_sha']=out('rev-parse',ref)
 record2=copy.deepcopy(record);record2['profile_id']='lost';record2['profile_sha256']=hashlib.sha256(m.proof.canonical(entry2)).hexdigest();api.lost=True
 assert m.retain(api,entry2,*mechanical_materials(entry2,record2),guard=still_trusted)['status']=='already-applied'
 assert git('show',ref+':'+opaque).stdout==b'opaque encrypted feedback' and api.patches==patches+1
 before=out('rev-parse',ref);reject(lambda:m.retain(api,entry,*mechanical_materials(entry,record,b'x'*800000),guard=still_trusted));assert out('rev-parse',ref)==before
 reject(lambda:m.retain(api,entry,*materials,guard=lambda:False));assert out('rev-parse',ref)==before
 racing=copy.deepcopy(entry);racing['profile_id']='racing';racing['retention']['bootstrap_sha']=before
 racing_record=copy.deepcopy(record);racing_record['profile_id']='racing';racing_record['profile_sha256']=hashlib.sha256(m.proof.canonical(racing)).hexdigest();other='reports/'+'b'*64+'.json'
 api.before=lambda:publish(other,b'concurrent encrypted bytes','2026-10-17T02:10:00Z')
 reject(lambda:m.retain(api,racing,*mechanical_materials(racing,racing_record),guard=still_trusted))
 assert git('show',ref+':'+other).stdout==b'concurrent encrypted bytes' and git('show',ref+':'+opaque).stdout==b'opaque encrypted feedback'
 assert git('cat-file','-e',ref+':reports/'+m.role('org/repo','racing',old)+'.json',check=False).returncode!=0

print('focused historical producer contracts: negative assertions='+str(count)+'; real Git CAS/opaque preservation; native API and verifier fixtures only')

# Protected execution reads actual Git objects and current files; non-main branch supported.
with tempfile.TemporaryDirectory() as folder:
 context=Path(folder).resolve();(context/'.claude/scripts').mkdir(parents=True);(context/'.github/workflows').mkdir(parents=True);(context/'factory').mkdir()
 (context/'.claude/scripts/probe.py').write_text('protected Python fixture\n')
 (context/m.SIGNER).write_text('protected workflow fixture\n');(context/m.REGISTRY).write_text('{"schema_version":1,"profiles":[]}')
 def context_git(*args):return subprocess.run(['git','-C',str(context),*args],capture_output=True,check=True).stdout.decode().strip()
 context_git('init','-q');context_git('config','user.name','Fixture');context_git('config','user.email','fixture@example.invalid');context_git('add','.');context_git('commit','-qm','protected fixture')
 context_sha=context_git('rev-parse','HEAD')
 class ContextAPI(Source):
  refsha=context_sha
  def request(self,path,method='GET',payload=None,raw=False):
   if path=='repos/org/repo':return dict(super().request(path),default_branch='release')
   if path=='repos/org/repo/git/ref/heads/release':return {'ref':'refs/heads/release','object':{'type':'commit','sha':self.refsha}}
   return super().request(path,method,payload,raw=raw)
 context_api=ContextAPI();environment={'GITHUB_ACTIONS':'true','GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_REPOSITORY':'org/repo','GITHUB_SHA':context_sha,'GITHUB_WORKFLOW_SHA':context_sha,'GITHUB_REF':'refs/heads/release','GITHUB_WORKFLOW_REF':'org/repo/'+m.SIGNER+'@refs/heads/release','RUNNER_ENVIRONMENT':'github-hosted','GITHUB_SERVER_URL':'https://github.com','GITHUB_API_URL':'https://api.github.com'}
 assert m.protected_execution(context_api,context,environment,m.SIGNER,'workflow_dispatch')==context_sha
 for key,value in [('RUNNER_ENVIRONMENT','self-hosted'),('GITHUB_SERVER_URL','https://foreign.example'),('GITHUB_API_URL','https://foreign.example'),('GITHUB_REF','refs/heads/main'),('GITHUB_EVENT_NAME','pull_request')]:
  reject(lambda:m.protected_execution(context_api,context,dict(environment,**{key:value}),m.SIGNER,'workflow_dispatch'))
 for name in ('.claude/scripts/probe.py',m.REGISTRY,m.SIGNER):
  file=context/name;saved=file.read_bytes();file.write_bytes(saved+b'changed')
  reject(lambda:m.protected_execution(context_api,context,environment,m.SIGNER,'workflow_dispatch'));file.write_bytes(saved)
 shadow=context/'.claude/scripts/untracked.py';shadow.write_text('shadow')
 reject(lambda:m.protected_execution(context_api,context,environment,m.SIGNER,'workflow_dispatch'));shadow.unlink()
 file=context/'.claude/scripts/probe.py';saved=file.read_bytes();file.unlink();file.symlink_to(context/m.REGISTRY)
 reject(lambda:m.protected_execution(context_api,context,environment,m.SIGNER,'workflow_dispatch'));file.unlink();file.write_bytes(saved)
 context_api.refsha='0'*40;reject(lambda:m.protected_execution(context_api,context,environment,m.SIGNER,'workflow_dispatch'))
# @AC-9: real Git quoted names must not silently escape the closed runtime family.
with tempfile.TemporaryDirectory() as folder:
 inventory_root=Path(folder).resolve();(inventory_root/'.claude/scripts').mkdir(parents=True)
 def inventory_git(*args):return subprocess.run(['git','-C',str(inventory_root),*args],capture_output=True,check=True).stdout.decode().strip()
 inventory_git('init','-q');inventory_git('config','user.name','Fixture');inventory_git('config','user.email','fixture@example.invalid')
 (inventory_root/'.claude/scripts/ordinary.py').write_text('ordinary fixture')
 for unusual in ('é.py','quote".py','line\nname.py'):
  unusual_path=inventory_root/'.claude/scripts'/unusual;unusual_path.write_text('unsupported filename fixture')
  inventory_git('add','.');inventory_git('commit','-qm','quoted inventory fixture');inventory_sha=inventory_git('rev-parse','HEAD')
  reject(lambda:m.runtime_inventory(None,inventory_sha,inventory_root))
  unusual_path.unlink()
# Actual CLI path must reject the vulnerable toolchain before signature verification.
assert hasattr(m.proof,'require_cli_version'), 'patched gh prerequisite missing'
def version_runner(version):
 def invoke(command,**kwargs):
  assert command==['gh','--version'] and kwargs['timeout']==10 and kwargs['limit']==4096
  return subprocess.CompletedProcess(command,0,('gh version '+version+' (fixture)\n').encode(),b'')
 return invoke
reject(lambda:m.proof.require_cli_version(version_runner('2.89.0'),{},Path.cwd()))
reject(lambda:m.proof.require_cli_version(version_runner('2.93.0-rc1'),{},Path.cwd()))
m.proof.require_cli_version(version_runner('2.93.0'),{},Path.cwd())
# Static workflow data contract: no activation, signer/writer credentials separated.
import yaml
sign=yaml.safe_load(Path('.github/workflows/factory-operational-proof.yml').read_text())
keep=yaml.safe_load(Path('.github/workflows/factory-operational-proof-retain.yml').read_text())
assert sign['permissions']=={'contents':'read','actions':'read','id-token':'write','attestations':'write'}
assert keep['permissions']=={'contents':'read','actions':'read','id-token':'write','attestations':'write'}
assert 'workflow_dispatch' in sign.get('on',sign.get(True)) and 'workflow_run' in keep.get('on',keep.get(True))
for doc in (sign,keep):
 for job in doc['jobs'].values():
  assert job['runs-on']=='ubuntu-latest' and 'FACTORY_OPERATIONAL_PROOF_ENABLED' in job['if']
assert 'FACTORY_REPORTING_APP_PRIVATE_KEY' not in Path('.github/workflows/factory-operational-proof.yml').read_text()
assert 'prepare-completion' in Path('.github/workflows/factory-operational-proof-retain.yml').read_text()
for filename in ('factory-operational-proof.yml','factory-operational-proof-retain.yml'):
 assert "'refs/heads/main'" not in (Path('.github/workflows')/filename).read_text()
print('all focused negative assertions='+str(count))
print('operational producer local contracts PASS; native signing/installation/bootstrap remain pending')
PY
