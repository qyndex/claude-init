#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - "$@" <<'PY'
"""Actual public discovery checkpoints remain loadable and reviewable after failures."""
from pathlib import Path
import sys
selected_case=sys.argv[1] if len(sys.argv)>1 else 'all'
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 from urllib.parse import parse_qs,urlsplit
 spec=importlib.util.spec_from_file_location('discovery_review',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 stream=a.archive_stream('org/repo');store={'repository':'org/repo','visibility':'public'};start='2026-10-15T00:00:00Z'
 def reset():git('update-ref',ref,initial,out('rev-parse',ref))
 def progress():return json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
 def outcomes():return [json.loads(git('show',ref+':'+p).stdout) for p in out('ls-tree','-r','--name-only',ref).splitlines() if p.startswith('receipt-archive/outcomes/')]
 if selected_case in ('all','backfill'):
  for end in ('2026-10-15T00:00:03Z',start):
   reset()
   class Drift(Source):
    calls=0
    def request(self,path,**kwargs):
     if '/actions/workflows/' not in path:return super().request(path,**kwargs)
     self.calls+=1;q=parse_qs(urlsplit(path).query);page=int(q['page'][0]);row=copy.deepcopy(self.run);row.update(id=page+20,created_at=start)
     if q['created'][0]!=start+'..'+end:return {'total_count':0,'workflow_runs':[]}
     return {'total_count':1000 if self.calls==2 else 2,'workflow_runs':[row]}
   source=Drift(policy,receipt)
   for i in range(9):
    # A fresh API/module load resumes actual persisted Git bytes each invocation.
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.backfill(source,State(),policy,approval,stream,interval_end=end,page_size=1,tree_pages=10)
    if i==1:
     nodes=[json.loads(git('show',ref+':'+p).stdout) for p in out('ls-tree','-r','--name-only',ref).splitlines() if p.startswith('receipt-archive/backfill/'+stream+'/')]
     assert len(nodes)==1 and nodes[0]['phase']=='gap' and nodes[0]['reason']=='count-drift'
     assert nodes[0]['expected_count']==2 and nodes[0]['facts'][0]['page']==1
     manifest=json.loads(git('show',ref+':receipt-archive/backfill/'+stream+'.json').stdout)
     assert manifest['epoch']==1 and manifest['last_round_gaps']==1 and len(manifest['stack'])==1
   nodes=[json.loads(git('show',ref+':'+p).stdout) for p in out('ls-tree','-r','--name-only',ref).splitlines() if p.startswith('receipt-archive/backfill/'+stream+'/')]
   assert nodes and all([f['page'] for f in n['facts']]==list(range(1,len(n['facts'])+1)) for n in nodes)
   assert progress()['watch']['count']>=2 and progress()['coverage_complete'] is False
  print('real Git page2 count rise persists valid gap; range/dense restart recovers PASS')
 if selected_case in ('all','review'):
  class Review(Source):
   error=None;kind='attempt';observed=[]
   def request(self,path,**kwargs):
    if '/actions/workflows/' in path:
     rows=[]
     for n in (20,21):
      row=copy.deepcopy(self.run);row.update(id=n,conclusion='failure');rows.append(row)
     return {'workflow_runs':rows}
    return super().request(path,**kwargs)
   def get(self,path):
    if '/actions/runs/' in path:
     n=int(path.split('/actions/runs/')[1].split('/')[0]);self.active=n;self.observed.append(n)
     if '/attempts/' in path and n==20 and self.kind=='attempt':raise ValueError(self.error)
     row=copy.deepcopy(self.run);row.update(id=n,conclusion='failure',run_attempt=2 if n==20 and self.kind=='attempt' else 1);return row
    return super().get(path)
   def source(self,path,sha):
    if self.kind=='source' and getattr(self,'active',None)==20:raise ValueError(self.error)
    return super().source(path,sha)
  for kind,error in [('attempt','GitHub API request failed: fixture'),('attempt','reporting API failed; reconcile authoritative state before retry'),('source','GitHub API request failed: fixture'),('source','reporting source unavailable'),('source','trusted source unavailable'),('source','receipt source size exceeds bound')]:
   reset();source=Review(policy,receipt);source.kind=kind;source.error=error;source.observed=[]
   d.advance(source,State(),policy,approval,stream,page_size=2,tree_pages=10)
   for repeat in range(2):d.reconcile(source,State(),policy,trust,store,approval,stream,review_rows=2)
   rows=outcomes();assert any(r['run_id']==20 and r['classification']=='watch' and r['reason']=='unavailable' for r in rows)
   assert any(r['run_id']==21 and r['classification']=='watch' for r in rows) and source.observed.count(21)>=2
  for error in ('discovery run identity differs','reporting invocation capacity gap','malformed source JSON'):
   reset();source=Review(policy,receipt);source.kind='source';source.error=error;d.advance(source,State(),policy,approval,stream,page_size=2,tree_pages=10);before=out('rev-parse',ref)
   try:d.reconcile(source,State(),policy,trust,store,approval,stream,review_rows=2)
   except ValueError as observed:assert str(observed)==error
   else:raise AssertionError('malformed identity/JSON/budget failure became unavailable')
   assert out('rev-parse',ref)==before
  print('real Git known attempt/source failures do not starve following watched row; malformed/budget remain strict PASS')
 if selected_case in ('all','head'):
  class Head(Source):
   extra=False;pages=[];count=4
   def request(self,path,**kwargs):
    if '/actions/workflows/' not in path:return super().request(path,**kwargs)
    q=parse_qs(urlsplit(path).query);page=int(q['page'][0]);size=int(q['per_page'][0]);self.pages.append(page);rows=[]
    for n in ([99] if self.extra else [])+list(range(20,20+self.count)):
     row=copy.deepcopy(self.run);row['id']=n;rows.append(row)
    return {'workflow_runs':rows[(page-1)*size:page*size]}
  for count in (3,4):
   reset();source=Head(policy,receipt);source.count=count;source.pages=[]
   for i in range(2 if count==3 else 3):d.advance(source,State(),policy,approval,stream,page_size=2,tree_pages=10)
   assert progress()['pagination']['next_page']==1,'short/empty source tail did not wrap to head'
   source.extra=True;d.advance(source,State(),policy,approval,stream,page_size=2,tree_pages=10)
   watched=[r['run_id'] for n in range(progress()['watch']['segments']) for r in json.loads(git('show',ref+':'+a.state_paths.pending_segment_path(stream,n)).stdout)['rows']]
   assert 99 in watched and progress()['coverage_complete'] is False
   for i in range(8):d.advance(source,State(),policy,approval,stream,page_size=2,tree_pages=10)
   assert max(source.pages)<=3
  print('real Git short/empty pages wrap bounded head polling and retain new head run PASS')
 if selected_case in ('all','head-deep'):
  reset()
  class DeepHead(Source):
   extra=False;pages=[]
   def request(self,path,**kwargs):
    if '/actions/workflows/' not in path:return super().request(path,**kwargs)
    q=parse_qs(urlsplit(path).query);page=int(q['page'][0]);size=int(q['per_page'][0]);self.pages.append(page)
    rows=[dict(copy.deepcopy(self.run),id=n) for n in ([99] if self.extra else [])+list(range(20,50))]
    return {'workflow_runs':rows[(page-1)*size:page*size]}
  source=DeepHead(policy,receipt);cursor_checks=[]
  def observation():
   previous=progress()['pagination'] if git('cat-file','-e',ref+':receipt-archive/progress/'+stream+'.json',check=False).returncode==0 else None
   before=len(source.pages);d.advance(source,State(),policy,approval,stream,page_size=2,tree_pages=10);fetched=source.pages[before:];after=progress()['pagination']
   assert len(fetched)<=2 and len(fetched)==len(set(fetched)),'observation exceeds two distinct source pages'
   if previous and previous['next_page']>1:
    page=previous['next_page'];old=previous['overlap_page'];until=previous['overlap_until']
    if page%2:
     cursor_checks.append(fetched==[page,1] and (after['overlap_page'],after['overlap_until'])==(old,until))
    else:
     cursor_checks.append(fetched==[page,old])
     expected=(1,max(1,page-1)) if old==until else (old+1,until)
     cursor_checks.append((after['overlap_page'],after['overlap_until'])==expected)
   return fetched
  for i in range(7):observation()
  source.extra=True
  first=observation();second=observation()
  watched=[r['run_id'] for n in range(progress()['watch']['segments']) for r in json.loads(git('show',ref+':'+a.state_paths.pending_segment_path(stream,n)).stdout)['rows']]
  assert 99 in watched and 1 not in first and 1 in second,'new deep-listing head run missed two-observation bound'
  assert all(cursor_checks),'unfetched older overlap moved or fetched older overlap failed to advance'
  print('real Git two-page alternating head/older overlap observes new head within two observations PASS')
 if selected_case in ('all','two-page-cap'):
  reset()
  class Wide(Source):
   changed=False;pages=[]
   def request(self,path,**kwargs):
    if '/actions/workflows/' not in path:return super().request(path,**kwargs)
    q=parse_qs(urlsplit(path).query);page=int(q['page'][0]);size=int(q['per_page'][0]);assert size==100;self.pages.append(page)
    first=1001 if page==1 and self.changed else page*100
    return {'workflow_runs':[dict(copy.deepcopy(self.run),id=n) for n in range(first,first+100)]}
  source=Wide(policy,receipt);d.advance(source,State(),policy,approval,stream,page_size=100,tree_pages=10)
  before_count=progress()['watch']['count'];assert before_count==100
  # Authenticate the actual larger inert suffix before the next observation;
  # do not relax bootstrap tree windows or seed completed-origin JSON.
  class OriginState(State):
   def request(self,path,method='GET',payload=None):
    if method=='GET' and '/commits?' in path:
     q=parse_qs(urlsplit(path).query);rows=out('log','-1','--format=%H',q['sha'][0],'--',q['path'][0]).splitlines();return [{'sha':v} for v in rows]
    return super().request(path,method,payload)
  for call in range(64):
   checked=a.advance_origin(OriginState(),approval,commit_budget=16,tree_pages=8)
   if checked['frozen_complete']:break
  else:raise AssertionError('actual bounded origin did not cover100-watch suffix')
  source.changed=True;before=len(source.pages);d.advance(source,OriginState(),policy,approval,stream,page_size=100,tree_pages=10)
  assert source.pages[before:]==[2,1] and progress()['watch']['count']-before_count==200
  assert progress()['coverage_complete'] is False
  print('actual two100-row pages persist at most200 new identities with no completeness credit PASS')
 if selected_case in ('all','artifact-budget'):
  reset()
  class ArtifactBudget(Source):
   def request(self,path,**kwargs):
    if '/actions/workflows/' in path:return {'workflow_runs':[copy.deepcopy(self.run)]}
    value=super().request(path,**kwargs)
    if path.endswith('/artifacts'):value[0]['padding']='x'*2097152
    return value
  source=ArtifactBudget(policy,receipt);d.advance(source,State(),policy,approval,stream,page_size=1,tree_pages=10);before=out('rev-parse',ref)
  try:d.reconcile(source,State(),policy,trust,store,approval,stream)
  except ValueError as error:
   assert str(error)=='discovery observation budget exceeded; explicit coverage gap'
   assert type(error).__name__=='DiscoveryBudgetError'
  else:raise AssertionError('artifact-path discovery budget failure persisted as soft proof outcome')
  assert out('rev-parse',ref)==before and outcomes()==[]
  print('actual source artifact response exceeds own budget: typed failure/ref unchanged PASS')
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
'''
exec(compile(fixture+cases,'discovery-review-real-git','exec'))
PY
