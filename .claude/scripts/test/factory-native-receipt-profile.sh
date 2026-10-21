#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PYTEST'
"""AC-1/AC-5: approved additive profile contract; isolated source fixtures are not signed proof."""
import copy, hashlib, importlib.util, json, pathlib, tempfile
root=pathlib.Path.cwd()
s=importlib.util.spec_from_file_location('receipts',root/'.claude/scripts/factory-receipts.py')
r=importlib.util.module_from_spec(s);s.loader.exec_module(r)
original=json.loads('{\n  "schema_version": 1,\n  "repository": "qyndex/claude-init",\n  "profiles": [\n    {\n      "id": "reporting-main-e095a23",\n      "status": "active",\n      "policy_sha256": "bc4d9155d093cb245dcba78d57291f4c946043b120361769d7101528ee1aedb9",\n      "runtime": {\n        ".github/workflows/factory-merge.yml": "850c637ad6c2820eb64a7c432348d93fe85f90b134d2ea4601c4cca3e1c19f2d",\n        ".claude/scripts/factory-coordinator.py": "2598e434b9058ff56ae8781b8337653655c8e99de43a71b346fff86cea36fa00",\n        ".claude/scripts/factory-preflight.py": "c3997120ee8d7064738b26fa1c30e318db02ebf411c46baa3aa67d521d1dad56",\n        ".claude/scripts/validate-candidate-evidence.py": "ad0be5042d8dce5e0372159bbcbdbb84bc39b96e57435865eb62e7e5d4d0b52c",\n        ".claude/scripts/factory-provenance.py": "0b169e5fefa78ee683ecf3aaf13bfce975929b113ff3d1052a59a95cc3077b01",\n        ".claude/scripts/factory-bounded-process.py": "91d077e6badb7c606a31cf85d8fbb8315b91d9d211b4fe1ab8fb970693207f47",\n        ".claude/scripts/factory-policy-observation.py": "2fce0d7b6fda425dce97ee77cdccede155a16d93a2c2d4e588c7816e976a8dee"\n      }\n    },\n    {\n      "id": "merge-main-20261018",\n      "status": "active",\n      "policy_sha256": "e931871e11121f140024eed2b6378e3d632354e8d6d25db1a184e42bdbcfd804",\n      "runtime": {\n        ".github/workflows/factory-merge.yml": "850c637ad6c2820eb64a7c432348d93fe85f90b134d2ea4601c4cca3e1c19f2d",\n        ".claude/scripts/factory-coordinator.py": "2598e434b9058ff56ae8781b8337653655c8e99de43a71b346fff86cea36fa00",\n        ".claude/scripts/factory-preflight.py": "c3997120ee8d7064738b26fa1c30e318db02ebf411c46baa3aa67d521d1dad56",\n        ".claude/scripts/validate-candidate-evidence.py": "ad0be5042d8dce5e0372159bbcbdbb84bc39b96e57435865eb62e7e5d4d0b52c",\n        ".claude/scripts/factory-provenance.py": "0b169e5fefa78ee683ecf3aaf13bfce975929b113ff3d1052a59a95cc3077b01",\n        ".claude/scripts/factory-bounded-process.py": "91d077e6badb7c606a31cf85d8fbb8315b91d9d211b4fe1ab8fb970693207f47",\n        ".claude/scripts/factory-policy-observation.py": "2fce0d7b6fda425dce97ee77cdccede155a16d93a2c2d4e588c7816e976a8dee"\n      }\n    }\n  ],\n  "legacy_revisions": {}\n}\n')
trust=r.load_receipt_trust(root/'factory/receipt-trust.json','qyndex/claude-init',mode='profile')
assert trust['profiles'][:2]==original['profiles'] and trust['legacy_revisions']==original['legacy_revisions']
# The already approved native source profile remains immutable history.
expected_native=copy.deepcopy(original['profiles'][1])
expected_native.update(id='merge-native-source-20261020', policy_sha256='dbf0609bde476f00384b4ada98a7e08c71b33bb1d27f17c2e52262b0cf6b7ba0')
expected_native['runtime']['.claude/scripts/factory-preflight.py']='7cda232eb703ab6b23588396b9db8a3bae9aded440513fb9ace394d01acd0780'
assert trust['profiles'][2]==expected_native, 'historical native profile rewritten'
assert len(trust['profiles'])==4, 'local additive font profile missing'
profile=trust['profiles'][3]
policy=json.loads((root/'factory/policy.json').read_bytes())
assert profile['id']=='merge-font-source-20261021' and profile['status']=='active'
assert profile['policy_sha256']==r.coordinator.policy_hash(policy)
pins={p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in r.RUNTIME_PATHS}
assert profile['runtime']==pins
assert all('sandbox_profile' not in spec for spec in policy['specs'].values())
class API:
 repo=policy['repository']
 def source(self,path,sha):
  assert sha=='a'*40
  return (root/path).read_bytes()
run={'id':1,'run_attempt':1,'workflow_id':policy['receipts']['workflow_id'],
 'repository':{'full_name':policy['repository']},'event':'workflow_dispatch',
 'head_branch':policy['base_branch'],'path':r.RUNTIME_PATHS[0],'head_sha':'a'*40}
count=0
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp)/'trust.json'
 def auth(value=trust,api=None,observed_run=None):
  path.write_text(json.dumps(value))
  return r.authenticate_source(api or API(),policy,observed_run or run,trust_path=path,trust_mode='profile')
 def reject(value,reason,**kw):
  global count
  try:auth(value,**kw)
  except ValueError as e:assert reason in str(e),(reason,str(e));count+=1
  else:raise AssertionError('accepted '+reason)
 assert auth()[3]==profile;count+=1
 for mutate,reason in [
  (lambda v:v['profiles'].pop(),'not approved'),
  (lambda v:v['profiles'][3]['runtime'].__setitem__('.claude/scripts/factory-preflight.py','0'*64),'source changed'),
  (lambda v:v['profiles'][3].__setitem__('policy_sha256','0'*64),'not approved'),
  (lambda v:v['profiles'].append(dict(profile,id='duplicate-native')),'ambiguous'),
  (lambda v:v['profiles'][3].__setitem__('status','revoked'),'revoked'),
  (lambda v:v.__setitem__('repository','foreign/repo'),'repository'),
  (lambda v:v['profiles'][3].__setitem__('status','historical'),'status')]:
  bad=copy.deepcopy(trust);mutate(bad);reject(bad,reason)
 bad=copy.deepcopy(trust);bad['profiles'].append(dict(profile,id='revoked-native',status='revoked'))
 reject(bad,'revoked')
 badrun=dict(run,event='pull_request');reject(trust,'unprotected',observed_run=badrun)
 for old in trust['profiles']:
  fact={'source_sha':'b'*40,'trust':{'mode':'profile','profile_id':old['id'],
   'policy_sha256':old['policy_sha256'],'runtime':old['runtime']}}
  proof={'provenance':json.dumps(fact),'tasks':['T-1'],'revision':'c'*64}
  before=copy.deepcopy(proof);path.write_text(json.dumps(trust))
  assert r.annotate_reported_trust(proof,path,API.repo)['trust_status']=='active'
  assert proof==before;count+=1
  withdrawn=copy.deepcopy(trust);next(p for p in withdrawn['profiles'] if p['id']==old['id'])['status']='revoked'
  path.write_text(json.dumps(withdrawn))
  assert r.annotate_reported_trust(proof,path,API.repo)['trust_status']=='withdrawn'
  assert proof==before;count+=1
print(f'{count} native history plus local font profile source/history controls passed; no hosted proof')
PYTEST
