#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
if [[ ${T299_HISTORY_ONLY:-0} != 1 ]]; then
python3 - <<'PY'
"""AC-1/AC-6: historical integrity families never authorize current source omissions."""
import pathlib,sys,tempfile,copy,json,importlib.util,hashlib
text=pathlib.Path('.claude/scripts/test/factory-receipt-projection.sh').read_text().split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory()',1)[0]
sys.argv=['test',str(pathlib.Path.cwd())];exec(compile(text,'receipt-fixture','exec'))
spec=importlib.util.spec_from_file_location('archive',scripts/'factory-receipt-archive.py');a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
r=a.receipts
class ArchiveAPI(API):
 def get(self,path):
  if path=='repos/'+self.repo:return {'id':101,'full_name':self.repo,'private':False}
  return super().get(path)
count=0
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp)/'trust.json';store={'repository':'org/repo','visibility':'public'}
 api=ArchiveAPI(policy,receipt)
 # Distinct bytes ensure material-count bounds really see all ten objects.
 for p in r.RUNTIME_PATHS:api.sources[p]=('runtime '+p).encode()
 pins={p:hashlib.sha256(api.sources[p]).hexdigest() for p in r.RUNTIME_PATHS}
 policy['receipts']['trusted_revisions']['a'*40]=pins
 api.sources['factory/policy.json']=json.dumps(policy).encode();receipt['policy_sha256']=r.coordinator.policy_hash(policy)
 current={'id':'current','status':'active','policy_sha256':receipt['policy_sha256'],'runtime':pins}
 trust={'schema_version':1,'repository':api.repo,'profiles':[current],'legacy_revisions':{}}
 path.write_text(json.dumps(trust))
 record,materials=a.build_record(api,policy,20,path,store)
 assert len(materials)==10 and len(record['materials'])==10;count+=1
 assert a.validate_record(record,materials,api.repo,'public')==record;count+=1
 # A schema1 historical capsule: remove exactly the dependency introduced by PR110.
 # This exercises integrity compatibility, NOT protected-writer origin proof.
 old=copy.deepcopy(record);oldmaterials=copy.deepcopy(materials)
 helper='.claude/scripts/factory-policy-observation.py'
 oldmaterials.pop(old['materials'].pop(helper))
 oldtrust=copy.deepcopy(trust);oldtrust['profiles'][0]['runtime'].pop(helper);oldtrust['profiles'][0]['id']='historical'
 oldraw=a.canonical(oldtrust);oldhash=a.digest(oldraw)
 oldmaterials.pop(old['materials']['factory/receipt-trust.json']);oldmaterials[oldhash]=a.base64.b64encode(oldraw).decode();old['materials']['factory/receipt-trust.json']=oldhash
 prov=json.loads(old['proof']['provenance']);prov['trust']['runtime'].pop(helper);prov['trust']['profile_id']='historical';prov['trust']['document_sha256']=oldhash
 old['proof']['provenance']=json.dumps(prov)
 assert a.validate_record(old,oldmaterials,api.repo,'public')==old;count+=1
 mixed=copy.deepcopy(trust);historic=copy.deepcopy(oldtrust['profiles'][0]);historic['status']='revoked';mixed['profiles'].append(historic);path.write_text(json.dumps(mixed))
 assert len(r.load_receipt_trust(path,api.repo,mode='profile')['profiles'])==2;count+=1
 assert a.build_record(api,policy,20,path,store)[0]['run']['id']==20;count+=1
 assert r.annotate_reported_trust(old['proof'],path,api.repo)['trust_status']=='withdrawn';count+=1
 # Old-only profile plus explicit legacy pins must not silently authorize current.
 bad=copy.deepcopy(mixed);bad['profiles']=[dict(historic,status='active')];bad['legacy_revisions']={'a'*40:pins};path.write_text(json.dumps(bad))
 rejects(lambda:r.authenticate_source(api,policy,api.run,trust_path=path,trust_mode='profile'));count+=1
 path.write_text(json.dumps(mixed));missing=copy.deepcopy(api);missing.sources.pop(helper)
 rejects(lambda:a.build_record(missing,policy,20,path,store));count+=1
 for dropped in ['.claude/scripts/factory-provenance.py','.claude/scripts/factory-bounded-process.py']:
  malformed=copy.deepcopy(mixed);malformed['profiles'][0]['runtime'].pop(dropped);path.write_text(json.dumps(malformed));rejects(lambda:r.load_receipt_trust(path,api.repo,mode='report'));count+=1
 bad=copy.deepcopy(old);bad['materials'].pop('.claude/scripts/factory-provenance.py');rejects(lambda:a.validate_record(bad,oldmaterials,api.repo,'public'));count+=1
 print(f'{count} runtime compatibility cases passed; integrity only, writer origin remains mandatory')
PY
fi
python3 - <<'PYORIGIN'
"""AC-6: historical issuance fixture, real Git protected origin, current reader."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 # Model the known pre-PR110 six-file emitter ONLY while issuing the fixture.
 # No current production API gains an option to authenticate old source closures.
 import sqlite3
 oldpaths=r.RUNTIME_PATHS[:-1];currentpaths=a.receipts.RUNTIME_PATHS
 r.RUNTIME_PATHS=oldpaths;a.receipts.RUNTIME_PATHS=oldpaths
 policy['receipts']['trusted_revisions']['a'*40].pop('.claude/scripts/factory-policy-observation.py')
 receipt['policy_sha256']=r.coordinator.policy_hash(policy)
 source=Source(policy,receipt)
 oldtrust={'schema_version':1,'repository':'org/repo','profiles':[{'id':'historical','status':'active','policy_sha256':r.coordinator.policy_hash(policy),'runtime':policy['receipts']['trusted_revisions']['a'*40]}],'legacy_revisions':{}}
 trust.write_text(json.dumps(oldtrust));store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo')
 assert a.append_delivery(source,state,policy,20,trust,store,approval,stream)['status']=='appended'
 r.RUNTIME_PATHS=currentpaths;a.receipts.RUNTIME_PATHS=currentpaths
 source.expired=True
 current=copy.deepcopy(oldtrust);current['profiles'][0]['status']='revoked'
 newpins=dict(current['profiles'][0]['runtime']);newpins['.claude/scripts/factory-policy-observation.py']='f'*64
 current['profiles'].append({'id':'current','status':'active','policy_sha256':'e'*64,'runtime':newpins});trust.write_text(json.dumps(current))
 db=root/'historical-six.sqlite'
 assert a.project_retained(State(),policy,db,trust,store,approval,stream)==1
 with sqlite3.connect(db) as sql:
  assert sql.execute('SELECT * FROM delivery_trust').fetchall()==[('T-1','withdrawn')]
  facts=sql.execute('SELECT * FROM delivery_provenance').fetchall();assert len(json.loads(facts[0][1])['trust']['runtime'])==6
  assert not sql.execute("SELECT name FROM sqlite_master WHERE name='tasks'").fetchall()
 assert a.project_retained(State(),policy,root/'restart-six.sqlite',trust,store,approval,stream)==1
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 class NoOrigin(State):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/rulesets/1' in path:value=copy.deepcopy(value);value['bypass_actors']=[]
   return value
 try:a.project_retained(NoOrigin(),policy,root/'untrusted.sqlite',trust,store,approval,stream)
 except ValueError as error:assert 'protection policy changed' in str(error)
 else:raise AssertionError('historical family bypassed writer origin')
 print('6 historical-six/current-seven real-Git expiry/restart/withdrawal/origin/privacy cases passed')
'''
exec(compile(fixture+cases,'historical-six-protected-origin-fixture','exec'))
PYORIGIN
