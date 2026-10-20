import pathlib,subprocess,json,importlib.util,hashlib
root=pathlib.Path('/private/tmp/factory-additive-receipt-profile-20261021')
s=importlib.util.spec_from_file_location('r',root/'.claude/scripts/factory-receipts.py');r=importlib.util.module_from_spec(s);s.loader.exec_module(r)
trust=root/'factory/receipt-trust.json';profiles=json.loads(trust.read_bytes())['profiles'];current=json.loads((root/'factory/policy.json').read_bytes())
def raw(sha,path):return subprocess.check_output(['git','-C',str(root),'show',sha+':'+path],stderr=subprocess.DEVNULL)
commits=subprocess.check_output(['git','-C',str(root),'log','--all','--format=%H','--','factory/policy.json']).decode().splitlines()
results=[]
for profile in profiles[:2]:
 for sha in commits:
  p=json.loads(raw(sha,'factory/policy.json'))
  if r.coordinator.policy_hash(p)!=profile['policy_sha256']:continue
  pins={path:hashlib.sha256(raw(sha,path)).hexdigest() for path in r.RUNTIME_PATHS}
  if pins!=profile['runtime']:continue
  class API:
   repo=current['repository']
   def source(self,path,revision):
    assert revision==sha
    return raw(sha,path)
  run={'id':1,'run_attempt':1,'workflow_id':current['receipts']['workflow_id'],'repository':{'full_name':API.repo},'event':'workflow_dispatch','head_branch':'main','path':r.RUNTIME_PATHS[0],'head_sha':sha}
  selected=r.authenticate_source(API(),current,run,trust_path=trust,trust_mode='profile')[3]
  assert selected==profile
  results.append({'profile':profile['id'],'actual_source_sha':sha,'policy_sha256':r.coordinator.policy_hash(p),'runtime':pins,'result':'PASS actual local Git bytes; no hosted signature'})
  break
 else:results.append({'profile':profile['id'],'result':'PENDING actual historical source not present in local Git; preservation and annotation only'})
print(json.dumps(results,indent=2))
