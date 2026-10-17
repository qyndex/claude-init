#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - "$@" <<'PY'
"""Actual stage rotation and delivered legacy interval remain scheduling-safe."""
from pathlib import Path
import sys
selected_case=sys.argv[1] if len(sys.argv)>1 else 'all'
base=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
adapter=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct',1)[0]
if selected_case in ('all','campaign'):
 cases=r'''
 ms=importlib.util.spec_from_file_location('maintenance_liveness',scripts/'factory-reporting-maintenance.py');m=importlib.util.module_from_spec(ms);ms.loader.exec_module(m)
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo');end='2026-10-15T23:00:00Z'
 source=Source(policy,receipt);source.run['created_at']='2026-10-15T00:00:30Z'
 assert a.append_delivery(source,PipelineState(),policy,20,trust,store,approval,stream)['status']=='appended'
 class Runs:
  repo='org/repo'
  def get(self,path):return source.get(path)
  def source(self,*args):return source.source(*args)
  def request(self,path,**kwargs):
   if '/actions/workflows/' in path:
    q=parse_qs(urlparse(path).query);lo,hi=q['created'][0].split('..');page=int(q['page'][0]);size=int(q['per_page'][0]);rows=[copy.deepcopy(source.run)] if lo<=source.run['created_at']<=hi else []
    return {'total_count':len(rows),'workflow_runs':rows[(page-1)*size:page*size]}
   return source.request(path,**kwargs)
 role=a.digest(a.canonical(['reporting-maintenance-v1','org/repo',branch]));journal_path='reports/'+role+'.json'
 for call in range(96):
  result=m.maintain(Runs(),PipelineState(),policy,trust,store,approval,interval_end=end)
  if result['phase']=='stage':break
 else:raise AssertionError('actual stage journal never reached')
 before=git('show',ref+':'+journal_path).stdout;journal=json.loads(before);assert journal['offset']==0
 original=trust.read_bytes();actual_stage=m.archive.stage_projection;observed=[]
 def rotate(*args,**kwargs):
  trust.write_bytes(original+b' ')
  result=actual_stage(*args,**kwargs);observed.append(result);return result
 m.archive.stage_projection=rotate
 try:
  try:m.maintain(Runs(),PipelineState(),policy,trust,store,approval,interval_end=end)
  except ValueError as error:assert str(error)=='maintenance staged campaign differs'
  else:raise AssertionError('wrong actual stage campaign credited to maintenance offset')
 finally:m.archive.stage_projection=actual_stage;trust.write_bytes(original)
 assert len(observed)==1 and observed[0]['status']=='staged' and observed[0]['facts_count']==1
 assert observed[0]['campaign']!=journal['campaign']
 assert git('show',ref+':'+journal_path).stdout==before,'rotation changed scheduling journal'
 # Real matching stage can recover after the orphaned new-campaign publication.
 for call in range(32):
  m.maintain(Runs(),PipelineState(),policy,trust,store,approval,interval_end=end)
  saved=json.loads(git('show',ref+':'+journal_path).stdout)
  if saved['offset']==1:break
 else:raise AssertionError('matching actual campaign did not advance')
 assert saved['campaign']==journal['campaign'] and git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual stage under rotated valid trust refuses wrong-campaign offset; matching stage recovers PASS',flush=True)
'''
 exec(compile(base+adapter+cases,'maintenance-actual-campaign-rotation','exec'))
if selected_case in ('all','quiet'):
 rollover=Path('.claude/scripts/test/factory-reporting-rollover.sh').read_text();assert "cases=r'''\n" in rollover
 setup=rollover.split("cases=r'''\n",1)[1].split(' first_now=',1)[0]
 setup=setup.replace("assert kwargs=={},kwargs","assert kwargs in ({},{'paginate':True}),kwargs").replace("query=parse_qs(urlparse(path).query);page=int(query['page'][0]);return self.rows[(page-1)*100:page*100]","if kwargs.get('paginate'):return [copy.deepcopy(self.rows)]\n    query=parse_qs(urlparse(path).query);page=int(query['page'][0]);size=int(query['per_page'][0]);return self.rows[(page-1)*size:page*size]").replace("'pr_discovery_mode':'resumable'","'pr_discovery_mode':'legacy'")
 cases=r'''
 now=datetime(2026,10,14,22,5,tzinfo=timezone.utc);role=a.digest(a.canonical(['reporting-maintenance-v1','org/repo',branch]));journal_path='reports/'+role+'.json'
 def step(index):return h.run(config,reports,PipelineState(),None,root/('legacy-'+str(index)+'.sqlite'),now)
 for index in range(96):
  result=step(index)
  if result['status']=='delivered':break
 else:raise AssertionError('actual legacy durable interval never delivered')
 assert remote.sends==1;payloads=copy.deepcopy(remote.payloads);receipts=copy.deepcopy(remote.messages)
 before=git('show',ref+':'+journal_path).stdout;assert json.loads(before)['phase']=='ready'
 for repeat in range(2):
  result=step(100+repeat)
  assert result['status']=='not-due','delivered interval reentered work'
  assert git('show',ref+':'+journal_path).stdout==before,'not-due interval published verify/backfill intent'
 assert remote.sends==1 and remote.payloads==payloads and remote.messages==receipts
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual delivered legacy durable interval twice not-due, ready journal/receipt/payload unchanged PASS',flush=True)
'''
 exec(compile(base+adapter+setup+cases,'maintenance-actual-legacy-quiet','exec'))
PY
