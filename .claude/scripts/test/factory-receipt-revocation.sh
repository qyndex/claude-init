#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-2: revocation never grants runtime credit; history remains immutable."""
import pathlib,copy,json,tempfile,sys
text=pathlib.Path('.claude/scripts/test/factory-receipt-projection.sh').read_text().split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory()',1)[0]
sys.argv=['test',str(pathlib.Path.cwd())];exec(compile(text,'existing-receipt-fixture','exec'))
api=API(policy,receipt);api.run['path']=r.RUNTIME_PATHS[0];count=0
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp)/'trust.json';pins=policy['receipts']['trusted_revisions']['a'*40]
 trust={'schema_version':1,'repository':api.repo,'profiles':[{'id':'reviewed','status':'active','policy_sha256':r.coordinator.policy_hash(policy),'runtime':pins}],'legacy_revisions':policy['receipts']['trusted_revisions']}
 def save():path.write_text(json.dumps(trust))
 def auth(mode='profile',historical=False,current=policy):return r.authenticate(api,current,20,trust_path=path,trust_mode=mode,historical=historical)
 def reject(fn,reason):
  global count
  try:fn()
  except ValueError as e:assert reason in str(e),(reason,str(e));count+=1
  else:raise AssertionError('accepted '+reason)
 save();proof=auth();legacy=auth('legacy');original=copy.deepcopy(proof)
 # Most important regression: valid exact legacy pins cannot override a revoked profile.
 trust['profiles'][0]['status']='revoked';save()
 for mode in ('legacy','profile'):
  for historical in (False,True):reject(lambda:auth(mode,historical),'revoked')
 annotated=r.annotate_reported_trust(proof,path,api.repo);assert annotated['trust_status']=='withdrawn';assert proof==original;assert {k:v for k,v in annotated.items() if k!='trust_status'}==proof;count+=1
 assert r.annotate_reported_trust(legacy,path,api.repo)['trust_status']=='withdrawn';count+=1
 trust['profiles'][0]['status']='active';save();assert r.annotate_reported_trust(proof,path,api.repo)['trust_status']=='active';count+=1
 # Current runtime and historical reporting remain separate in both modes.
 revised=copy.deepcopy(policy);revised['specs']['001']['sha256']='f'*64
 for mode in ('legacy','profile'):
  reject(lambda:auth(mode,current=revised),'superseded spec')
  assert auth(mode,historical=True,current=revised)['revision']==receipt['spec_sha256'];count+=1
  db=pathlib.Path(tmp)/(mode+'.sqlite');store=r.ledger.runtime.Store(db);store.enqueue('T-1','f'*64,[])
  reject(lambda:r.ingest(api,revised,db,20,trust_path=path,trust_mode=mode),'superseded spec')
  assert store.get('T-1')['state']=='queued';count+=1
 changed=copy.deepcopy(policy);changed['specs']['001']['task_ids']=['T-2']
 reject(lambda:auth(current=changed),'task delivery mapping')
 # Returned source facts are derived from actual checked bytes, never input claims.
 facts=json.loads(proof['provenance'])['trust'];assert facts['profile_id']=='reviewed' and facts['policy_sha256']==r.coordinator.policy_hash(policy) and facts['runtime']==pins;assert len(facts['document_sha256'])==64;count+=1
 assert json.loads(legacy['provenance'])['trust']['profile_id'] is None;count+=1
print(f'{count} revocation and current-task/history cases passed')
PY
