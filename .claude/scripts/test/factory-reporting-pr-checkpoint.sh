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
  self.calls+=1;query=parse_qs(urlsplit(path).query);page=int(query['page'][0]);size=int(query['per_page'][0]);assert size==25
  return [{'number':n,'title':'manual '+str(n),'html_url':'https://github.com/org/repo/pull/'+str(n),'merged_at':'2026-01-02T00:00:00Z','merge_commit_sha':format(n,'040x'),'head':{'sha':'a'*40},'base':{'ref':'main','repo':{'full_name':self.repo}}} for n in range(1,202)][(page-1)*size:page*size]
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
 # Retain an actual confirmed delivery and its receipt during scratch migration.
 with store.transaction() as db:db.execute("UPDATE digest_batches SET status='uncertain' WHERE key=?",(batch['key'],))
 store.confirm(batch,{'key':batch['key'],'destination':'fixture','payload_sha256':__import__('hashlib').sha256(batch['payload'].encode()).hexdigest(),'message_id':'1.1'})
 confirmed=json.loads(h.snapshot(store.path,'org/repo',store.stream,'fixture','main'))['tables']
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
 # Historical authenticated 100-row layouts restore, then rebuild only scratch.
 helper_spec=__import__('importlib').util.spec_from_file_location('pr_helper',Path('.claude/scripts/factory-reporting-pr-discovery.py'))
 helper=__import__('importlib').util.module_from_spec(helper_spec);helper_spec.loader.exec_module(helper)
 import hashlib
 source=Source();all_rows=[]
 for page in range(1,10):all_rows.extend(source.request('repos/org/repo/pulls?per_page=25&page='+str(page)))
 for phase,cursor,counts in [('baseline',2,[100]),('compare',2,[100,100,1]),('ready',4,[100,100,1])]:
  old=copy.deepcopy(good);old['tables'].update({k:copy.deepcopy(confirmed[k]) for k in h.TABLES});scan=old['tables']['reporting_pr_scans'][0];scan.update(phase=phase,next_page=cursor)
  old_pages=[];offset=0
  for index,count in enumerate(counts,1):
   selected=all_rows[offset:offset+count];offset+=count
   old_pages.append({'stream':store.stream,'page':index,'count':count,'fingerprint':hashlib.sha256(helper.canonical(selected).encode()).hexdigest(),'payload':helper.canonical(selected)})
  old['tables']['reporting_pr_pages']=old_pages
  h.validate(old,'org/repo',store.stream)
  state.bytes=h.canonical(old).encode();migrated=h.HostedDigest(Path(tmp)/(phase+'.sqlite'),config,state)
  before_tables=copy.deepcopy(old['tables']);fresh=Source()
  result=migrated.discover(fresh,'2026-01-03T00:00:00Z')
  assert result['status']=='incomplete' and fresh.calls==8
  after=json.loads(state.bytes)['tables']
  assert all(p['count']==25 for p in after['reporting_pr_pages'])
  assert all(after[k]==before_tables[k] for k in h.TABLES),'migration changed authoritative delivery tables'
  for attempt in range(4):
   migrated=h.HostedDigest(Path(tmp)/(phase+str(attempt)+'.sqlite'),config,state)
   result=migrated.discover(fresh,'2026-01-03T00:00:00Z')
   if result['status']=='complete':break
  else:raise AssertionError('legacy scratch migration did not complete fresh observations')
  assert json.loads(state.bytes)['tables']['digest_batches']==confirmed['digest_batches']
 # Neither arbitrary page sizes nor mixed historical/current layouts are accepted.
 for counts in ([50,1],[100,25,1]):
  value=copy.deepcopy(old);value['tables']['reporting_pr_scans'][0].update(phase='compare',next_page=1)
  value['tables']['reporting_pr_pages']=[]
  for index,count in enumerate(counts,1):
   item=copy.deepcopy(old_pages[0]);item.update(page=index,count=count,payload='[]');value['tables']['reporting_pr_pages'].append(item)
  reject(value)
 print('legacy baseline/compare/ready migration and malformed layout rejection PASS')
 print('typed PR scratch fresh SQLite restoration, same-instance prepare, malformed checkpoint rejection PASS')
PY
