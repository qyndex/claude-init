#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: actual real-Git old4/new16 review continuation and cursor controls."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
adapter=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct',1)[0]
cases=r'''
 ms=importlib.util.spec_from_file_location('maintenance',scripts/'factory-reporting-maintenance.py');m=importlib.util.module_from_spec(ms);ms.loader.exec_module(m)
 stream=a.archive_stream('org/repo');end='2026-10-15T01:00:00Z';store={'repository':'org/repo','visibility':'public'}
 class Runs(Source):
  def __init__(self):super().__init__(policy,receipt);self.lookups=[]
  def request(self,target,**kwargs):
   if '/actions/workflows/' in target:
    query=parse_qs(urlparse(target).query);page=int(query['page'][0]);size=int(query['per_page'][0]);rows=[]
    for n in range(20):
     run=copy.deepcopy(self.run);run.update(id=31+n,created_at='2026-10-15T00:00:30Z',conclusion='failure');rows.append(run)
    return {'total_count':20,'workflow_runs':rows[(page-1)*size:page*size]}
   return super().request(target,**kwargs)
  def get(self,target):
   if '/actions/runs/' in target:
    n=int(target.rsplit('/',1)[1]);self.lookups.append(n);run=copy.deepcopy(self.run);run.update(id=n,created_at='2026-10-15T00:00:30Z',conclusion='failure');return run
   return super().get(target)
 runs=Runs();role=a.digest(a.canonical(['reporting-maintenance-v1','org/repo',branch]));journal_path='reports/'+role+'.json';watch_path='receipt-archive/progress/'+stream+'.json'
 def journal():return json.loads(git('show',ref+':'+journal_path).stdout)
 def watch():return json.loads(git('show',ref+':'+watch_path).stdout)
 def step():
  result=m.maintain(runs,PipelineState(),policy,trust,store,approval,interval_end=end)
  assert result['coverage_complete'] is False and result['task_credit'] is False
  assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
  return result
 for _ in range(48):
  step();saved=journal()
  if saved['phase']=='review' and saved['review_blob'] is not None:break
 else:raise AssertionError('real protected review capture unavailable')
 assert saved['remaining']==20 and saved['review_cursor']=={'segment':0,'row':0}
 # Simulate an interrupted prior version with its ACTUAL admitted4-row reconciler.
 m.discovery.reconcile(runs,PipelineState(),policy,trust,store,approval,stream,review_rows=4)
 for _ in range(8):
  step();saved=journal()
  if saved['review_cursor']=={'segment':0,'row':4}:break
 else:raise AssertionError('old4 cursor acknowledgement unavailable')
 assert saved['remaining']==16,'old4 resume overcredited or reset'
 before=len(runs.lookups)
 for _ in range(8):
  step()
  if watch()['review']!={'segment':0,'row':4}:break
 assert watch()['review']=={'segment':0,'row':0},'maintenance still dispatches4 instead of admitted16 rows'
 assert len(runs.lookups)-before==16,'new review failed to observe exactly16 actual runs'
 for _ in range(8):
  result=step();saved=journal()
  if saved['phase']=='checkpoint':break
 else:raise AssertionError('new16 acknowledgement never completed scheduling round')
 assert saved['remaining']==0 and result['coverage_complete'] is False
 print('actual old4 credits4; new16 observes16 and credits16; no coverage/task authority; real Git opaque bytes preserved',flush=True)
 # Unit controls execute the actual production review block, not a second algorithm.
 import ast
 tree=ast.parse((scripts/'factory-reporting-maintenance.py').read_text());fn=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='maintain')
 branch_node=next(n for n in fn.body if isinstance(n,ast.If) and ast.unparse(n.test)=="journal['phase'] == 'review'")
 unit=ast.FunctionDef(name='review_unit',args=ast.arguments(posonlyargs=[],args=[],kwonlyargs=[],kw_defaults=[],defaults=[]),body=branch_node.body,decorator_list=[]);code=compile(ast.fix_missing_locations(ast.Module(body=[unit],type_ignores=[])),'actual-review-block','exec')
 def control(label,size,segments,old,current,remaining,expected):
  rows=[{'run_id':n+1,'attempt':1,'source_sha':'a'*40,'classification':'pending'} for n in range(size)]
  segment={'schema_version':1,'repository':'org/repo','stream':stream,'number':old['segment'],'rows':rows}
  j={'phase':'review','remaining':remaining,'review_watch_count':30,'review_watch_segments':segments,'review_blob':'a'*40,'review_cursor':old}
  w={'watch':{'count':30,'segments':segments},'review':current};env={'watch':w,'journal':j,'state':m.state,'watch_raw':b'changed','anchor':{'tree':'b'*40},'archive':m.archive,'stream':stream,'api':type('A',(),{'repo':'org/repo'})(),'discovery':m.discovery,'require':m.require,'blob_at':lambda *a:m.archive.canonical(segment),'persist':lambda changed:changed}
  exec(code,env);result=env['review_unit']();assert result['remaining']==expected,(label,result)
 for args in [('old4',20,1,{'segment':0,'row':0},{'segment':0,'row':4},20,16),('new16',20,1,{'segment':0,'row':0},{'segment':0,'row':16},20,4),('short-wrap',20,2,{'segment':0,'row':17},{'segment':1,'row':0},20,17),('one-wrap',1,1,{'segment':0,'row':0},{'segment':0,'row':0},1,0),('backwards',20,2,{'segment':0,'row':8},{'segment':0,'row':4},20,30),('too-far',40,2,{'segment':0,'row':0},{'segment':0,'row':17},20,30),('unrelated',20,3,{'segment':0,'row':0},{'segment':2,'row':0},20,30)]:control(*args)
 print('actual review-block cursor distance controls PASS; unit fixtures do not authenticate state')
'''
exec(compile(fixture+adapter+cases,'review-throughput-real-git','exec'))
PY
