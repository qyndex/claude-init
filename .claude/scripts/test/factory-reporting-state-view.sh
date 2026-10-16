#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: actual public protected report loader, Git CAS and opaque privacy."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 gs=importlib.util.spec_from_file_location('reporting_state',scripts/'factory-git-state.py');g=importlib.util.module_from_spec(gs);gs.loader.exec_module(g)
 assert a.verify_bootstrap(State(),approval)['head']==initial
 selected='2'*64;path='reports/'+selected+'.json'
 def publish(changes):
  api=State();head=out('rev-parse',ref);entries=[]
  for name,data in changes.items():
   blob=api.request('repos/org/repo/git/blobs','POST',{'encoding':'base64','content':base64.b64encode(data).decode()})
   entries.append({'path':name,'mode':'100644','type':'blob','sha':blob['sha']})
  tree=api.request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',head+'^{tree}'),'tree':entries})
  commit=api.request('repos/org/repo/git/commits','POST',{'tree':tree['sha'],'parents':[head],'message':'fixture report'})
  api.request('repos/org/repo/git/refs/heads/'+branch,'PATCH',{'sha':commit['sha'],'force':False})
  return commit['sha']
 raw=b'{"checkpoint":"safe fixture"}'
 head=publish({path:raw,'receipt-archive/materials/aa/'+'a'*64+'.json':b'{}'})
 private_sha=out('rev-parse',ref+':'+oldpath)
 class Bounded(State):
  def __init__(self):self.paths=[]
  def request(self,target,method='GET',payload=None):
   self.paths.append((target,method))
   assert '?recursive=' not in target,'bounded report loader must not fetch entire archive recursively'
   assert not target.endswith('/git/blobs/'+private_sha),'must not deserialize private feedback bytes'
   return copy.deepcopy(super().request(target,method,payload))
 view={'mode':'archive','approval_path':str(approval.resolve())};api=Bounded()
 current=g.GitState(api,branch,selected,state_view=view)
 assert current.bytes==raw and current.head==head and current.tree==out('rev-parse',ref+'^{tree}')
 count=1
 def reject(fn,reason):
  global count
  try:fn()
  except ValueError as error:assert reason in str(error),(reason,str(error));count+=1
  else:raise AssertionError('accepted '+reason)
 # A caller flag/hash/foreign branch is never a protected origin.
 for bad in ({'mode':'archive','approval_path':str(approval),'complete':True},{'mode':'archive','approval_path':str(approval),'tree':current.tree},{'mode':'other','approval_path':str(approval)},{'mode':'archive','approval_path':True}):
  reject(lambda:g.GitState(Bounded(),branch,selected,state_view=bad),'view')
 reject(lambda:g.GitState(Bounded(),'other-state',selected,state_view=view),'branch')
 missing='3'*64;reject(lambda:g.GitState(Bounded(),branch,missing,state_view=view),'bootstrap')
 class Drift(Bounded):
  changed=False
  def request(self,target,method='GET',payload=None):
   value=super().request(target,method,payload)
   if target.endswith('/git/blobs/'+g.git_hash(raw)):self.changed=True
   if self.changed and target.endswith('/rulesets/1'):value['updated_at']='2026-10-16T00:00:00Z'
   return value
 before=out('rev-parse',ref);reject(lambda:g.GitState(Drift(),branch,selected,state_view=view),'policy changed');assert out('rev-parse',ref)==before
 # Protected origin configuration cannot change beneath a loaded writer snapshot.
 approved_raw=approval.read_bytes();changed=json.loads(approved_raw);changed['observed_at']='2026-10-15T00:00:01Z';approval.write_text(json.dumps(changed))
 reject(lambda:current.checkpoint(b'{"checkpoint":"changed approval must block"}'),'changed');approval.write_bytes(approved_raw)
 # Actual nonforce checkpoint keeps every unrelated opaque and archive byte.
 current.checkpoint(b'{"checkpoint":"updated"}');assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 assert git('show',ref+':receipt-archive/materials/aa/'+'a'*64+'.json').stdout==b'{}';count+=1
 restarted=g.GitState(Bounded(),branch,selected,state_view=view);assert restarted.bytes==b'{"checkpoint":"updated"}';count+=1
 stale=g.GitState(Bounded(),branch,selected,state_view=view);publish({'reports/'+'4'*64+'.json':b'opaque concurrent writer'})
 before=out('rev-parse',ref);reject(lambda:stale.checkpoint(b'{"checkpoint":"must not overwrite"}'),'changed');assert out('rev-parse',ref)==before
 # Shared queue loader must select the same public protected view, not legacy actors.
 qs=importlib.util.spec_from_file_location('queue',scripts/'factory-reporting-queue.py');q=importlib.util.module_from_spec(qs);qs.loader.exec_module(q)
 config={'enabled':True,'queue_monitor_enabled':True,'repository':'org/repo','state_repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','grace_minutes':60}
 storage={'state_branch':branch,'bootstrap_sha':out('rev-parse',ref),'initialize':True,'policy_approvals':{},'state_view':view}
 queue=q.QueueStore(Bounded(),config,storage)
 assert queue.read()['journal'] is None;count+=1
 empty={'schema_version':1,'repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','stream':q.stream(config),'events':[]}
 assert queue.checkpoint(None,empty)['status']=='applied';assert q.QueueStore(Bounded(),config,storage).read()['journal']==empty;count+=1
 worker=g.hashlib.sha256(g.canonical(['org/repo','C1','main']).encode()).hexdigest()
 document={'schema_version':1,'repository':'org/repo','stream':worker,'destination':'C1','branch':'main','tables':{'digest_cursors':[{'stream':worker,'cutoff':'2026-10-15T00:00:00Z'}],'digest_origins':[{'stream':worker,'origin':'2026-10-15T00:00:00Z'}],'digest_batches':[]}}
 publish({'reports/'+worker+'.json':g.canonical(document).encode()})
 ws=importlib.util.spec_from_file_location('watchdog',scripts/'factory-reporting-watchdog.py');w=importlib.util.module_from_spec(ws);ws.loader.exec_module(w)
 health_config=dict(config,state_branch=branch,state_view=view)
 health=w.inspect(health_config,Bounded(),None,datetime.datetime(2026,10,16,tzinfo=datetime.timezone.utc))
 assert health['latest_receipt_verified'] is False and health['pending_batches']==0;count+=1
 fs=importlib.util.spec_from_file_location('feedback',scripts/'factory-hosted-feedback.py');feedback=importlib.util.module_from_spec(fs);fs.loader.exec_module(feedback)
 feedback_config=dict(health_config,feedback_enabled=True,feedback_key_id='key1')
 reject(lambda:feedback.run(feedback_config,Bounded(),None,None,datetime.datetime(2026,10,16,tzinfo=datetime.timezone.utc)),'confirmed digest required')
 # Unsafe transient state must still fail actual origin, even for a safe selected blob.
 saved=out('rev-parse',ref);index=root/'unsafe-index';env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',saved,env=env)
 git('update-index','--add','--cacheinfo','100755,'+g.git_hash(raw)+',reports/'+'5'*64+'.json',env=env)
 badtree=git('write-tree',env=env).stdout.decode().strip();index.unlink();bad=git('commit-tree',badtree,'-p',saved,input=b'unsafe transient').stdout.decode().strip()
 restored=git('commit-tree',out('rev-parse',saved+'^{tree}'),'-p',bad,input=b'removed unsafe path').stdout.decode().strip();git('update-ref',ref,restored,saved)
 reject(lambda:g.GitState(Bounded(),branch,selected,state_view=view),'mode');git('update-ref',ref,saved,restored)
 # Missing approval or a same-schema foreign binding never falls back to legacy.
 old=approval.read_bytes();approval.unlink();reject(lambda:g.GitState(Bounded(),branch,selected,state_view=view),'approval');approval.write_bytes(old)
 bad=json.loads(old);bad['repository']='foreign/repo';approval.write_text(json.dumps(bad));reject(lambda:g.GitState(Bounded(),branch,selected,state_view=view),'repository');approval.write_bytes(old)
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 # The same public view works with explicit schema2 hidden App actor metadata.
 now=datetime.datetime.now(datetime.timezone.utc)
 for identity,value in policies.items():value.update(name='reviewed-'+str(identity),node_id='R_'+str(identity),created_at='2026-10-13T00:00:00Z')
 repository={'id':101,'full_name':'org/repo'}
 records={str(i):a.reporting_policy.capture(repository,value,branch,7,now=now) for i,value in policies.items()}
 sidecar=approval.with_name('receipt-policy-observations.json');sidecar.write_text(json.dumps({'schema_version':1,'repository':'org/repo','repository_id':101,'branch':branch,'writer_app_id':7,'policies':records}))
 approved=json.loads(approval.read_bytes());approved.update(schema_version=2,observed_at=now.isoformat(),policies={key:value['metadata_sha256'] for key,value in records.items()});approval.write_text(json.dumps(approved))
 class Hidden(Bounded):
  def request(self,target,method='GET',payload=None):
   value=super().request(target,method,payload)
   if '/rulesets/' in target:value.pop('bypass_actors')
   return value
 modern=g.GitState(Hidden(),branch,selected,state_view=view);modern.checkpoint(b'{"checkpoint":"hidden metadata verified"}')
 assert g.GitState(Hidden(),branch,selected,state_view=view).bytes==b'{"checkpoint":"hidden metadata verified"}';count+=1
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print(str(count)+' bounded authenticated real-Git report-view cases passed; no live/bootstrap capability claim')
'''
exec(compile(fixture+cases,'bounded-report-state-fixture','exec'))
PY
