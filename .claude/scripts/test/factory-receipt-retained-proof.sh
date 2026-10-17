#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-1/AC-2/AC-6: actual Git retained proof, fresh SQLite and expired source artifacts."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo')
 assert a.append_delivery(source,state,policy,20,trust,store,approval,stream)['status']=='appended'
 source.expired=True
 try:r.authenticate(source,policy,20,historical=True,trust_path=trust,trust_mode='profile')
 except ValueError as error:assert 'artifact missing' in str(error)
 else:raise AssertionError('expired live artifact unexpectedly accepted')
 db=root/'retained.sqlite'
 assert a.project_retained(State(),policy,db,trust,store,approval,stream)==1
 import sqlite3
 def rows():
  with sqlite3.connect(db) as sql:return {name:sql.execute('SELECT * FROM '+name).fetchall() for name in ('delivery_receipts','delivery_provenance','delivery_trust')}
 first=rows();assert first['delivery_receipts'][0][0]=='T-1' and first['delivery_trust']==[('T-1','active')]
 assert json.loads(first['delivery_provenance'][0][1])['run_id']==20
 assert b'opaque existing encrypted feedback envelope' not in db.read_bytes()
 assert a.project_retained(State(),policy,db,trust,store,approval,stream)==1 and rows()==first
 assert a.project_retained(State(),policy,root/'restart.sqlite',trust,store,approval,stream)==1
 # Archive projection never reads source API, updates runtime tasks or completes revised/cancelled work.
 runtime=r.ledger.runtime.Store(db);runtime.enqueue('T-1','f'*64,[])
 with runtime.transaction() as sql:sql.execute("UPDATE tasks SET state='cancelled' WHERE id='T-1'")
 assert a.project_retained(State(),policy,db,trust,store,approval,stream)==1
 assert runtime.get('T-1')['state']=='cancelled' and runtime.get('T-1')['revision']=='f'*64
 original_trust=trust.read_bytes();current=json.loads(original_trust);current['profiles'][0]['status']='revoked';trust.write_text(json.dumps(current))
 a.project_retained(State(),policy,db,trust,store,approval,stream)
 assert rows()['delivery_trust']==[('T-1','withdrawn')] and rows()['delivery_provenance']==first['delivery_provenance'] and rows()['delivery_receipts']==first['delivery_receipts']
 current['profiles']=[];trust.write_text(json.dumps(current));a.project_retained(State(),policy,db,trust,store,approval,stream);assert rows()['delivery_trust']==[('T-1','withdrawn')]
 trust.write_bytes(original_trust);a.project_retained(State(),policy,db,trust,store,approval,stream)
 before=rows();head=out('rev-parse',ref)
 def reject(call,reason):
  try:call()
  except ValueError as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('accepted '+reason)
  assert rows()==before and runtime.get('T-1')['state']=='cancelled'
 class Missing(State):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/git/trees/' in path:value['tree']=[x for x in value['tree'] if x['path']!='receipt-archive']
   return value
 reject(lambda:a.project_retained(Missing(),policy,db,trust,store,approval,stream),'discovery missing')
 class Tampered(State):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/git/blobs/' in path:value['content']=base64.b64encode(b'copied forged proof').decode()
   return value
 reject(lambda:a.project_retained(Tampered(),policy,db,trust,store,approval,stream),'blob bytes differ')
 class NoOrigin(State):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/rulesets/1' in path:value=copy.deepcopy(value);value['bypass_actors']=[]
   return value
 reject(lambda:a.project_retained(NoOrigin(),policy,db,trust,store,approval,stream),'protection policy changed')
 class Private(State):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if path=='repos/org/repo':value=dict(value,private=True)
   return value
 reject(lambda:a.project_retained(Private(),policy,db,trust,store,approval,stream),'repository differs')
 # Real Git mutations retain authenticated chain origin but must fail content reconstruction.
 material=next(name for name in out('ls-tree','-r','--name-only',ref).splitlines() if name.startswith('receipt-archive/materials/'))
 index=root/'remove-index';env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',head,env=env);git('update-index','--force-remove',material,env=env);bad_tree=git('write-tree',env=env).stdout.decode().strip();index.unlink()
 missing_commit=git('commit-tree',bad_tree,'-p',head,input=b'fixture missing material').stdout.decode().strip();git('update-ref',ref,missing_commit,head)
 reject(lambda:a.project_retained(State(),policy,db,trust,store,approval,stream),'retained material missing');git('update-ref',ref,head,missing_commit)
 # A consistent data-only append can still conflict semantically; reject the entire projection.
 other=Source(policy,receipt);other.run['id']=21
 assert a.append_delivery(other,State(),policy,21,trust,store,approval,stream)['status']=='appended'
 reject(lambda:a.project_retained(State(),policy,db,trust,store,approval,stream),'conflicting reporting delivery proof')
 assert out('rev-parse',ref)!=head
 # Explicit reviewed legacy mode has a durable import route; never fall back from profile.
 git('update-ref',ref,initial,out('rev-parse',ref))
 legacy=Source(policy,receipt);legacy.run['id']=30
 legacy_trust={'schema_version':1,'repository':'org/repo','profiles':[],'legacy_revisions':policy['receipts']['trusted_revisions']};trust.write_text(json.dumps(legacy_trust))
 assert a.append_delivery(legacy,State(),policy,30,trust,store,approval,stream,trust_mode='legacy')['status']=='appended'
 legacy.expired=True;legacy_db=root/'legacy-retained.sqlite'
 assert a.project_retained(State(),policy,legacy_db,trust,store,approval,stream)==1
 with sqlite3.connect(legacy_db) as sql:assert sql.execute('SELECT * FROM delivery_trust').fetchall()==[('T-1','active')]
 legacy_trust['profiles']=[{'id':'revoked','status':'revoked','policy_sha256':r.coordinator.policy_hash(policy),'runtime':policy['receipts']['trusted_revisions']['a'*40]}];trust.write_text(json.dumps(legacy_trust))
 a.project_retained(State(),policy,legacy_db,trust,store,approval,stream)
 with sqlite3.connect(legacy_db) as sql:assert sql.execute('SELECT * FROM delivery_trust').fetchall()==[('T-1','withdrawn')]
 legacy.expired=False
 for mode,reason in [('legacy','revoked'),('profile','revoked')]:
  try:a.append_delivery(legacy,State(),policy,30,trust,store,approval,stream,trust_mode=mode)
  except ValueError as error:assert reason in str(error)
  else:raise AssertionError('revoked legacy import accepted')
 legacy_trust['profiles']=[];legacy_trust['legacy_revisions']={};trust.write_text(json.dumps(legacy_trust))
 try:a.append_delivery(legacy,State(),policy,30,trust,store,approval,stream,trust_mode='legacy')
 except ValueError as error:assert 'revision not approved' in str(error)
 else:raise AssertionError('missing legacy revision accepted')
 legacy_trust['legacy_revisions']=policy['receipts']['trusted_revisions'];trust.write_text(json.dumps(legacy_trust))
 try:a.append_delivery(legacy,State(),policy,30,trust,store,approval,stream)
 except ValueError as error:assert 'not approved' in str(error)
 else:raise AssertionError('profile mismatch fell back to legacy')
 print('20 retained proof expiry/restart/revocation/privacy/origin/atomic-conflict scenarios passed')
'''
exec(compile(fixture+cases,'real-git-retained-proof-fixture','exec'))
PY
