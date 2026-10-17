#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-1: bind actual immutable coordinator execution source, not claimed metadata."""
import pathlib,copy,json,tempfile,hashlib
text=pathlib.Path('.claude/scripts/test/factory-receipt-projection.sh').read_text().split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory()',1)[0]
import sys
sys.argv=['test',str(pathlib.Path.cwd())];exec(compile(text,'existing-receipt-fixture','exec'))
api=API(policy,receipt);api.run['path']='.github/workflows/factory-merge.yml'
count=0
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp)/'trust.json'
 profile={'id':'reviewed','status':'active','policy_sha256':r.coordinator.policy_hash(policy),'runtime':policy['receipts']['trusted_revisions']['a'*40]}
 trust={'schema_version':1,'repository':api.repo,'profiles':[profile],'legacy_revisions':{}}
 path.write_text(json.dumps(trust))
 def auth(a=api,mode='profile',external=path):return r.authenticate(a,policy,20,trust_path=external,trust_mode=mode)
 assert auth()['merge_sha']=='b'*40;count+=1
 def reject(a,reason):
  global count
  try:auth(a)
  except ValueError as e:assert reason in str(e),(reason,str(e));count+=1
  else:raise AssertionError('accepted '+reason)
 for field,value,reason in [('path','.github/workflows/other.yml','workflow path'),('path',None,'workflow path'),('head_sha','not-sha','source SHA'),('run_attempt',True,'run identity'),('id',21,'run identity'),('workflow_id',True,'foreign receipt producer'),('event','pull_request','event/branch'),('head_branch','feature','event/branch'),('conclusion','failure','succeed')]:
  bad=copy.deepcopy(api);bad.run[field]=value;reject(bad,reason)
 bad=copy.deepcopy(api);del bad.run['path'];reject(bad,'workflow path')
 bad=copy.deepcopy(api);bad.run['repository']['full_name']='other/repo';reject(bad,'foreign receipt producer')
 for name in r.RUNTIME_PATHS:
  bad=copy.deepcopy(api);bad.sources[name]=b'changed';reject(bad,'producer source changed')
 bad=copy.deepcopy(api);source=copy.deepcopy(policy);source['unapproved']=True;bad.sources['factory/policy.json']=json.dumps(source).encode();reject(bad,'source policy not approved')
 bad=copy.deepcopy(api);bad.sources[r.RUNTIME_PATHS[0]]=b'x'*1048577;reject(bad,'source size')
 bad=copy.deepcopy(api);bad.run['source_policy_sha256']=profile['policy_sha256'];bad.sources['factory/policy.json']=b'{"enabled":true}';reject(bad,'source policy not approved')
 # Explicit legacy mode still uses exact imported revision, never a profile fallback.
 trust['legacy_revisions']=policy['receipts']['trusted_revisions'];path.write_text(json.dumps(trust));assert auth(mode='legacy')['run_id']==20;count+=1
 trust['profiles'][0]['policy_sha256']='0'*64;path.write_text(json.dumps(trust));reject(api,'source policy not approved')
 try:auth(mode='profile',external=None)
 except ValueError as e:assert 'external' in str(e);count+=1
 else:raise AssertionError('implicit profile authorization')
print(f'{count} immutable receipt source cases passed')
PY
