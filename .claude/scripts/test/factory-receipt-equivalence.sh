#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-5: ordinary Git revisions can share exact approved authority content."""
import pathlib,tempfile,json,subprocess,copy
import sys
text=pathlib.Path('.claude/scripts/test/factory-receipt-projection.sh').read_text().split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory()',1)[0]
sys.argv=['test',str(pathlib.Path.cwd())];exec(compile(text,'existing-receipt-fixture','exec'))
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp);repo=root/'source';repo.mkdir()
 def git(*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.PIPE).decode().strip()
 git('init','-q');git('config','user.name','Receipt fixture');git('config','user.email','fixture@example.invalid')
 source_policy=copy.deepcopy(policy);source_policy['receipts']['trusted_revisions']={}
 def write(path,value):
  p=repo/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value)
 for path in r.RUNTIME_PATHS:write(path,b'trusted')
 write('factory/policy.json',json.dumps(source_policy).encode());write('specs/active/001.md',b'approved spec');write('README.md',b'first ordinary content')
 git('add','.');git('commit','-qm','initial reviewed authority');first=git('rev-parse','HEAD')
 write('README.md',b'second ordinary content');git('add','.');git('commit','-qm','ordinary feature');second=git('rev-parse','HEAD');assert first!=second
 pins={path:hashlib.sha256(b'trusted').hexdigest() for path in r.RUNTIME_PATHS}
 trust={'schema_version':1,'repository':policy['repository'],'profiles':[{'id':'reviewed','status':'active','policy_sha256':r.coordinator.policy_hash(source_policy),'runtime':pins}], 'legacy_revisions':{}}
 path=root/'trust.json';path.write_text(json.dumps(trust));before=path.read_bytes()
 class GitAPI(API):
  def source(self,name,sha):
   assert sha==self.run['head_sha'] and sha!=self.receipt['head_sha']
   return subprocess.check_output(['git','-C',str(repo),'show',f'{sha}:{name}'],stderr=subprocess.PIPE)
 candidate=copy.deepcopy(receipt);candidate['policy_sha256']=r.coordinator.policy_hash(source_policy)
 api=GitAPI(source_policy,candidate);api.run['path']=r.RUNTIME_PATHS[0]
 proofs=[]
 for revision in (first,second):
  api.run['head_sha']=revision;proofs.append(r.authenticate(api,source_policy,20,trust_path=path,trust_mode='profile'))
 assert proofs[0]['delivery']==proofs[1]['delivery'];assert json.loads(proofs[0]['provenance'])['source_sha']==first;assert json.loads(proofs[1]['provenance'])['source_sha']==second
 count=2
 for name in (*r.RUNTIME_PATHS,'factory/policy.json'):
  git('checkout','-q',second,'--','.')
  if name=='factory/policy.json':
   changed=copy.deepcopy(source_policy);changed['unapproved']=True;write(name,json.dumps(changed).encode())
  else:write(name,b'changed authority')
  git('add','.');git('commit','-qm','unapproved authority change');api.run['head_sha']=git('rev-parse','HEAD')
  try:r.authenticate(api,source_policy,20,trust_path=path,trust_mode='profile')
  except ValueError as e:assert ('producer source changed' if name!='factory/policy.json' else 'source policy not approved') in str(e);count+=1
  else:raise AssertionError('accepted changed '+name)
 assert path.read_bytes()==before and trust['legacy_revisions']=={}
 print(f'{count} real-Git source equivalence cases passed; two ordinary SHAs, seven authority changes')
PY
