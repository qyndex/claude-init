#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: typed protected report scratch resumes without local SQLite authority."""
import importlib.util,json,tempfile,copy
from pathlib import Path
from urllib.parse import parse_qs,urlsplit
s=importlib.util.spec_from_file_location('h',Path('.claude/scripts/factory-git-state.py'));h=importlib.util.module_from_spec(s);s.loader.exec_module(h)
class State:
 bytes=None
 def checkpoint(self,value):self.bytes=value
class Source:
 repo='org/repo';calls=0
 def request(self,path):
  self.calls+=1;page=int(parse_qs(urlsplit(path).query)['page'][0])
  return [{'number':n,'title':'manual '+str(n),'html_url':'https://github.com/org/repo/pull/'+str(n),'merged_at':'2026-01-02T00:00:00Z','merge_commit_sha':format(n,'040x'),'head':{'sha':'a'*40},'base':{'ref':'main','repo':{'full_name':self.repo}}} for n in range(1,202)][(page-1)*100:page*100]
config={'repository':'org/repo','destination':'fixture','start':'2026-01-01T00:00:00Z','branch':'main','pr_discovery_mode':'resumable'}
with tempfile.TemporaryDirectory() as tmp:
 state=State();api=Source()
 for invocation in range(5):
  store=h.HostedDigest(Path(tmp)/(str(invocation)+'.sqlite'),config,state)
  result=store.discover(api,'2026-01-03T00:00:00Z')
  assert state.bytes is not None
  saved=json.loads(state.bytes)
  assert set(saved['tables'])==set(h.TABLES)|{'reporting_pr_scans','reporting_pr_pages'},'PR scratch lost from protected checkpoint'
  assert saved['tables']['digest_batches']==[]
  if result['status']=='complete':break
 else:raise AssertionError('protected scratch restart never completes')
 before=api.calls;batch=store.prepare(api,'2026-01-03T00:00:00Z');assert api.calls==before
 assert len(json.loads(batch['payload'])['merges'])==201
 good=copy.deepcopy(saved)
 # Reused local scratch cannot outlive an authoritative old three-table snapshot.
 legacy=copy.deepcopy(saved);legacy['tables']={k:v for k,v in legacy['tables'].items() if k in h.TABLES}
 state.bytes=h.canonical(legacy).encode()
 restored=h.HostedDigest(store.path,config,state)
 with restored.transaction() as db:pass
 assert not json.loads(state.bytes)['tables'].get('reporting_pr_pages'), 'local scratch survived authoritative legacy restore'

 def reject(value):
  try:h.validate(value,'org/repo',store.stream)
  except ValueError:return
  raise AssertionError('malformed PR checkpoint accepted')
 value=copy.deepcopy(good);value['tables']['reporting_pr_pages'][0]['page']=True;reject(value)
 value=copy.deepcopy(good);value['tables']['reporting_pr_pages'].append(copy.deepcopy(value['tables']['reporting_pr_pages'][0]));reject(value)
 value=copy.deepcopy(good);value['tables']['reporting_pr_scans'][0]['repository']='foreign/repo';reject(value)
 value=copy.deepcopy(good);value['tables'].pop('reporting_pr_pages');reject(value)
 print('typed PR scratch fresh SQLite restoration, same-instance prepare, malformed checkpoint rejection PASS')
PY
