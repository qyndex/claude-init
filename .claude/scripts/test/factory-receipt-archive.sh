#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: retain actual authenticated compact proof, not a claimed flag."""
import pathlib,sys,tempfile,copy,json,importlib.util
text=pathlib.Path('.claude/scripts/test/factory-receipt-projection.sh').read_text().split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory()',1)[0]
sys.argv=['test',str(pathlib.Path.cwd())];exec(compile(text,'existing-receipt-fixture','exec'))
spec=importlib.util.spec_from_file_location('archive',scripts/'factory-receipt-archive.py');a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
class ArchiveAPI(API):
 def get(self,path):
  if path=='repos/'+self.repo:return {'id':101,'full_name':self.repo,'private':self.private}
  return super().get(path)
api=ArchiveAPI(policy,receipt);api.private=False;api.run['repository']['id']=101
pins=policy['receipts']['trusted_revisions']['a'*40];trust={'schema_version':1,'repository':api.repo,'profiles':[{'id':'approved','status':'active','policy_sha256':r.coordinator.policy_hash(policy),'runtime':pins}],'legacy_revisions':{}}
count=0
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp)/'trust.json';path.write_text(json.dumps(trust));store={'repository':api.repo,'visibility':'public'}
 record,materials=a.build_record(api,policy,20,path,store)
 assert a.validate_record(record,materials,api.repo,'public')==record;count+=1
 assert record['run']['id']==20 and record['run']['attempt']==1 and record['artifact']['id']==30;count+=1
 assert 'authenticated' not in record and not any(k in json.dumps(record) for k in ['provider_output','slack_feedback']);count+=1
 def reject(fn,reason):
  global count
  try:fn()
  except ValueError as e:assert reason in str(e),(reason,str(e));count+=1
  else:raise AssertionError('accepted '+reason)
 bad=copy.deepcopy(record);bad['authenticated']=True;reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'schema')
 for section,key,value in [('run','id',21),('run','source_sha','f'*40),('artifact','digest','sha256:'+'0'*64),('artifact','id',31),('repository',None,'other/repo')]:
  bad=copy.deepcopy(record)
  if key is None:bad[section]=value
  else:bad[section][key]=value
  reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'differs')
 bad=copy.deepcopy(materials);bad[next(iter(bad))]='eA==';reject(lambda:a.validate_record(record,bad,api.repo,'public'),'material digest')
 bad=copy.deepcopy(materials);bad['0'*64]='eA==';reject(lambda:a.validate_record(record,bad,api.repo,'public'),'material set')
 bad=copy.deepcopy(record);bad['receipt_zip']='eA==';reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'archive digest')
 bad=copy.deepcopy(record);bad['source_private']=True;reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'private')
 bad=copy.deepcopy(record);bad['receipt_zip']='A'*1398105;reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'size')
 buf=io.BytesIO()
 with zipfile.ZipFile(buf,'w') as z:z.writestr('receipt.json','{}');z.writestr('provider.log','forbidden')
 bad=copy.deepcopy(record);bad['receipt_zip']=a.base64.b64encode(buf.getvalue()).decode();bad['artifact']['digest']='sha256:'+a.digest(buf.getvalue());provenance=json.loads(bad['proof']['provenance']);provenance['artifact_digest']=bad['artifact']['digest'];bad['proof']['provenance']=json.dumps(provenance)
 reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'members')
 badapi=copy.deepcopy(api);badapi.private=True;reject(lambda:a.build_record(badapi,policy,20,path,store),'private')
 private_record,private_materials=a.build_record(badapi,policy,20,path,dict(store,visibility='private'));assert a.validate_record(private_record,private_materials,api.repo,'private')==private_record;count+=1
 reject(lambda:a.validate_record(private_record,private_materials,api.repo,'public'),'differs')
 for field,value in [('id',21),('repository_id',102),('head_repository_id',102),('head_sha','f'*40)]:
  badapi=copy.deepcopy(api);badapi.origin_override={field:value};reject(lambda:a.build_record(badapi,policy,20,path,store),'artifact origin')
 badapi=copy.deepcopy(api);badapi.origin_override=None;reject(lambda:a.build_record(badapi,policy,20,path,store),'artifact origin')
 badapi=copy.deepcopy(api);badapi.sources[r.RUNTIME_PATHS[0]]=b'untrusted';reject(lambda:a.build_record(badapi,policy,20,path,store),'producer source changed')
 bad=copy.deepcopy(record);prov=json.loads(bad['proof']['provenance']);prov['provider_output']='forbidden';bad['proof']['provenance']=json.dumps(prov);reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'provenance schema')
 bad=copy.deepcopy(record);prov=json.loads(bad['proof']['provenance']);prov['trust']['profile_id']='not-approved';bad['proof']['provenance']=json.dumps(prov);reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'selected trust')
 bad=copy.deepcopy(record);prov=json.loads(bad['proof']['provenance']);prov['receipt']['eligible']=False;buf=io.BytesIO()
 with zipfile.ZipFile(buf,'w') as z:z.writestr('receipt.json',json.dumps(prov['receipt']))
 bad['receipt_zip']=a.base64.b64encode(buf.getvalue()).decode();bad['artifact']['digest']='sha256:'+a.digest(buf.getvalue());prov['artifact_digest']=bad['artifact']['digest'];bad['proof']['provenance']=json.dumps(prov);reject(lambda:a.validate_record(bad,materials,api.repo,'public'),'delivery semantics')
 class ChangedRunAPI(ArchiveAPI):
  reads=0
  def get(self,name):
   result=super().get(name)
   if '/actions/runs/' in name:
    self.reads+=1
    if self.reads>1:return dict(result,head_branch='feature')
   return result
 changedapi=ChangedRunAPI(policy,receipt);changedapi.private=False;reject(lambda:a.build_record(changedapi,policy,20,path,store),'observed run')
 class ChangedEventAPI(ArchiveAPI):
  reads=0
  def get(self,name):
   result=super().get(name)
   if '/actions/runs/' in name:
    self.reads+=1
    if self.reads>1:return dict(result,event='workflow_run')
   return result
 changedapi=ChangedEventAPI(policy,receipt);changedapi.private=False;reject(lambda:a.build_record(changedapi,policy,20,path,store),'observed run')
 assert a.check_record_conflict(record,copy.deepcopy(record))==record;count+=1
 bad=copy.deepcopy(record);bad['proof']['revision']='f'*64;reject(lambda:a.check_record_conflict(record,bad),'conflicting')
print(f'{count} compact receipt archive cases passed; bootstrap/CAS origin not implemented')
PY
