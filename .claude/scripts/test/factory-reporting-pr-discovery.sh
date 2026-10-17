#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: actual Digest + role transport restartable general PR discovery."""
import importlib.util,inspect,json,tempfile,sqlite3
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import parse_qs,urlsplit
scripts=Path('.claude/scripts').resolve()
spec=importlib.util.spec_from_file_location('transport',scripts/'factory-reporting-transport.py');t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
assert 'pr_discovery_mode' in inspect.signature(t.state.digest.Digest).parameters,'Digest has no bounded resumable PR discovery mode'
def pr(n):
 return {'number':n,'title':'manual '+str(n),'html_url':'https://github.com/org/repo/pull/'+str(n),'merged_at':'2026-01-02T01:00:00Z' if n%2 else '2026-01-03T12:00:00Z','merge_commit_sha':format(n,'040x'),'head':{'sha':'a'*40},'base':{'ref':'main','repo':{'full_name':'org/repo'}}}
# Fresh source page must bind selected payload, not merely its saved hash/count.
with tempfile.TemporaryDirectory() as tmp:
 path=Path(tmp)/'scratch.sqlite';d=t.state.digest.Digest(path,'org/repo','fixture','2026-01-01T00:00:00Z',pr_discovery_mode='resumable')
 hs=importlib.util.spec_from_file_location('discovery',scripts/'factory-reporting-pr-discovery.py');h=importlib.util.module_from_spec(hs);hs.loader.exec_module(h)
 class Unmerged:
  repo='org/repo'
  def request(self,*args,**kwargs):return [dict(pr(1),merged_at=None)]
 with d.transaction() as db:
  result=h.scan(db,Unmerged(),d.stream,'org/repo','main','2026-01-01T00:00:00+00:00','2026-01-04T00:00:00+00:00');assert result['rows']==[]
  db.execute('UPDATE reporting_pr_pages SET payload=?',(h.canonical([pr(99)]),))
 with d.transaction() as db:
  result=h.scan(db,Unmerged(),d.stream,'org/repo','main','2026-01-01T00:00:00+00:00','2026-01-04T00:00:00+00:00')
  assert result['status']=='incomplete','fresh unmerged source accepted tampered selected candidate payload'
assert hasattr(t.state.digest.Digest,'discover'),'missing same-instance discover prepass'
for total in (1000,1001):
 with tempfile.TemporaryDirectory() as tmp:
  path=Path(tmp)/'report.sqlite';rows=[pr(n) for n in range(1,total+1)];calls=[];api=t.RoutedAPI('org/repo','source-fixture','writer-fixture');original=t.process.run
  def run(command,*,env,**kwargs):
   assert env['GH_TOKEN']=='source-fixture' and command[5]=='GET'
   endpoint=command[6];query=parse_qs(urlsplit(endpoint).query);assert query['state']==['closed'] and query['sort']==['created'] and query['direction']==['asc']
   page=int(query['page'][0]);size=int(query['per_page'][0]);assert size==25;calls.append(page)
   return SimpleNamespace(returncode=0,stdout=json.dumps(rows[(page-1)*size:page*size]).encode(),stderr=b'')
  t.process.run=run
  try:
   for attempt in range(40):
    d=t.state.digest.Digest(path,'org/repo','fixture','2026-01-01T00:00:00Z',pr_discovery_mode='resumable')
    with d.transaction() as db:db.execute('UPDATE digest_cursors SET cutoff=?',('2026-01-03T00:00:00+00:00',))
    before=len(calls)
    if total==1000:
     batch=d.discover(api,'2026-01-04T00:00:00Z')
     if batch['status']=='complete':
      fetched=len(calls);batch=d.prepare(api,'2026-01-04T00:00:00Z');assert len(calls)==fetched
    else:batch=d.prepare(api,'2026-01-04T00:00:00Z')
    assert len(calls)-before<=8
    if batch.get('status')!='incomplete':break
    with sqlite3.connect(path) as db:assert db.execute('SELECT count(*) FROM digest_batches').fetchone()[0]==0
    assert d.cursor()=='2026-01-03T00:00:00+00:00'
    # Shift membership during persisted baseline. New manual old merge must survive.
    if total==1001 and attempt==0:rows.insert(0,pr(2001))
   else:raise AssertionError('stable source never completes')
   payload=json.loads(batch['payload']);assert {r['pr'] for r in payload['merges']}=={r['number'] for r in rows}
   assert all(r['evidence_status']=='missing' for r in payload['merges']);assert any(r['late_discovered'] for r in payload['merges'])
   assert api.budget.calls==len(calls)<2048 and api.budget.bytes<33554432
   # A pending/confirmed immutable delivery is never rewritten by a new source pass.
   before=len(calls);assert d.prepare(api,'2026-01-04T00:00:00Z')['payload']==batch['payload'];assert len(calls)==before
   with d.transaction() as db:db.execute("UPDATE digest_batches SET status='uncertain' WHERE key=?",(batch['key'],))
   receipt={'key':batch['key'],'destination':'fixture','payload_sha256':t.state.hashlib.sha256(batch['payload'].encode()).hexdigest(),'message_id':'1.1'};d.confirm(batch,receipt)
   assert d.batch(batch['key'])['payload']==batch['payload']
   print('stable/restarted manual+late PRs',total,'observed',len(rows),'calls',len(calls))
  finally:t.process.run=original
# Wrong repository/malformed progress never grants completed observations.
with tempfile.TemporaryDirectory() as tmp:
 d=t.state.digest.Digest(Path(tmp)/'r.sqlite','org/repo','fixture','2026-01-01T00:00:00Z',pr_discovery_mode='resumable')
 class Bad:
  repo='org/repo'
  def request(self,*args,**kwargs):return [dict(pr(1),base={'ref':'main','repo':{'full_name':'foreign/repo'}})]
 try:d.prepare(Bad(),'2026-01-04T00:00:00Z')
 except ValueError:pass
 else:raise AssertionError('foreign PR accepted')
# A source ignoring the selected page bound fails closed; no fallback or batch.
with tempfile.TemporaryDirectory() as tmp:
 d=t.state.digest.Digest(Path(tmp)/'r.sqlite','org/repo','fixture','2026-01-01T00:00:00Z',pr_discovery_mode='resumable')
 class Oversized:
  repo='org/repo'
  def request(self,*args,**kwargs):return [pr(n) for n in range(1,27)]
 try:d.prepare(Oversized(),'2026-01-04T00:00:00Z')
 except ValueError as error:assert str(error)=='PR source page invalid'
 else:raise AssertionError('oversized PR page accepted')
 with sqlite3.connect(d.path) as db:assert db.execute('SELECT count(*) FROM digest_batches').fetchone()[0]==0
# Malformed source/progress and exhausted transport never create a report.
with tempfile.TemporaryDirectory() as tmp:
 path=Path(tmp)/'r.sqlite';d=t.state.digest.Digest(path,'org/repo','fixture','2026-01-01T00:00:00Z',pr_discovery_mode='resumable')
 class Source:
  repo='org/repo'
  def request(self,path,**kwargs):
   query=parse_qs(urlsplit(path).query);page=int(query['page'][0]);size=int(query['per_page'][0])
   return [pr(n) for n in range(1,301)][(page-1)*size:page*size]
 result=d.prepare(Source(),'2026-01-04T00:00:00Z');assert result['status']=='incomplete' and result['phase']=='pull-requests'
 with d.transaction() as db:db.execute("UPDATE reporting_pr_scans SET next_page='invalid'")
 try:d.prepare(Source(),'2026-01-04T00:00:00Z')
 except ValueError:pass
 else:raise AssertionError('malformed persisted cursor accepted')
 with sqlite3.connect(path) as db:assert db.execute('SELECT count(*) FROM digest_batches').fetchone()[0]==0
with tempfile.TemporaryDirectory() as tmp:
 path=Path(tmp)/'r.sqlite';d=t.state.digest.Digest(path,'org/repo','fixture','2026-01-01T00:00:00Z',pr_discovery_mode='resumable')
 api=t.RoutedAPI('org/repo','source-fixture','writer-fixture');api.budget.calls=2048
 try:d.prepare(api,'2026-01-04T00:00:00Z')
 except ValueError as error:assert 'capacity' in str(error)
 else:raise AssertionError('exhausted shared budget accepted')
 with sqlite3.connect(path) as db:assert db.execute('SELECT count(*) FROM digest_batches').fetchone()[0]==0
 assert d.cursor()=='2026-01-01T00:00:00+00:00'
# Internal completed handoff is single-use/config-bound and never crosses instances.
with tempfile.TemporaryDirectory() as tmp:
 path=Path(tmp)/'r.sqlite';calls=[]
 class One:
  repo='org/repo'
  def request(self,*args,**kwargs):calls.append(args[0]);return [pr(1)]
 api=One();d=t.state.digest.Digest(path,'org/repo','fixture','2026-01-01T00:00:00Z',pr_discovery_mode='resumable')
 assert d.discover(api,'2026-01-04T00:00:00Z')['status']=='complete';assert len(calls)==2
 # A fresh instance must perform actual comparison; saved ready is not authority.
 fresh=t.state.digest.Digest(path,'org/repo','fixture','2026-01-01T00:00:00Z',pr_discovery_mode='resumable')
 fresh.prepare(api,'2026-01-04T00:00:00Z');assert len(calls)==3
 # Pending payload path consumes/discards any old cache too.
 d.prepare(api,'2026-01-04T00:00:00Z');assert d._pr_observation is None
 with d.transaction() as db:db.execute('DELETE FROM digest_batches')
 assert d.discover(api,'2026-01-04T00:00:00Z')['status']=='complete';before=len(calls)
 d.prepare(api,'2026-01-05T00:00:00Z');assert len(calls)>before and d._pr_observation is None
print('bounded PR discovery focused regressions passed; offline only')
PY
