#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-1/AC-5: strict external content trust; explicit modes never fall back."""
import importlib.util,copy,json,tempfile,pathlib
s=importlib.util.spec_from_file_location('receipts','.claude/scripts/factory-receipts.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
repo='example/project';pins={p:'a'*64 for p in m.RUNTIME_PATHS}
good={'schema_version':1,'repository':repo,'profiles':[{'id':'initial','status':'active','policy_sha256':'b'*64,'runtime':pins}], 'legacy_revisions':{'c'*40:pins}}
count=0
with tempfile.TemporaryDirectory() as d:
 path=pathlib.Path(d)/'trust.json'
 def parse(value,mode='profile'):
  path.write_text(json.dumps(value));return m.load_receipt_trust(path,repo,mode=mode)
 def reject(value,reason,mode='profile'):
  global count
  try:parse(value,mode)
  except ValueError as e:assert reason in str(e),(reason,str(e));count+=1
  else:raise AssertionError('accepted '+reason)
 assert parse(good)==good;count+=1
 assert parse(good,'legacy')==good;count+=1
 bad=copy.deepcopy(good);bad['repository']='other/project';reject(bad,'repository')
 for key in ['self_sha256','mode','unknown']:
  bad=copy.deepcopy(good);bad[key]='a'*64;reject(bad,'schema')
 for key in good:
  bad=copy.deepcopy(good);del bad[key];reject(bad,'schema')
 bad=copy.deepcopy(good);bad['schema_version']=True;reject(bad,'schema')
 bad=copy.deepcopy(good);bad['profiles'][0]['id']='../unsafe';reject(bad,'identity')
 bad=copy.deepcopy(good);bad['profiles']*=2;reject(bad,'duplicate')
 bad=copy.deepcopy(good);bad['profiles'][0]['status']='enabled';reject(bad,'status')
 bad=copy.deepcopy(good);bad['profiles'][0]['policy_sha256']='B'*64;reject(bad,'policy digest')
 bad=copy.deepcopy(good);bad['profiles'][0]['extra']=True;reject(bad,'profile schema')
 for pathkey in list(pins)+['factory/receipt-trust.json']:
  bad=copy.deepcopy(good)
  if pathkey == '.claude/scripts/factory-policy-observation.py':continue  # reviewed historical six-file parser family
  if pathkey in pins:del bad['profiles'][0]['runtime'][pathkey]
  else:bad['profiles'][0]['runtime'][pathkey]='a'*64
  reject(bad,'runtime closure')
 bad=copy.deepcopy(good);bad['profiles'][0]['runtime'][next(iter(pins))]='not-a-digest';reject(bad,'runtime digest')
 bad=copy.deepcopy(good);bad['legacy_revisions']={'not-a-sha':pins};reject(bad,'legacy revision')
 bad=copy.deepcopy(good);bad['legacy_revisions']['c'*40]={};reject(bad,'runtime closure',mode='legacy')
 bad=copy.deepcopy(good);bad['profiles'][0]['status']='revoked';reject(bad,'active profile')
 bad=copy.deepcopy(good);bad['profiles']=[];reject(bad,'active profile')
 bad=copy.deepcopy(good);bad['legacy_revisions']={};reject(bad,'legacy revisions',mode='legacy')
 reject(good,'explicit receipt trust mode',mode=None)
 reject(good,'explicit receipt trust mode',mode=[])
 path.write_text('{"schema_version":1,"schema_version":1}')
 try:m.load_receipt_trust(path,repo,mode='profile')
 except ValueError as e:assert 'duplicate' in str(e).lower();count+=1
 else:raise AssertionError('duplicate JSON key accepted')
 path.write_text(' '*262145)
 try:m.load_receipt_trust(path,repo,mode='profile')
 except ValueError as e:assert 'size' in str(e);count+=1
 else:raise AssertionError('oversized profile accepted')
print(f'{count} strict receipt profile cases passed; no runtime integration or activation')
PY
