#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: actual protected two-day maintenance with fresh process/CAS/gaps."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
adapter=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct',1)[0]
cases=r'''
 import textwrap
 assert a.verify_bootstrap(PipelineState(),approval)['head']==initial
 path=scripts/'factory-reporting-maintenance.py';assert path.exists(),'missing bounded protected reporting maintenance'
 ms=importlib.util.spec_from_file_location('maintenance',path);m=importlib.util.module_from_spec(ms);ms.loader.exec_module(m)
 store={'repository':'org/repo','visibility':'public'};ends=('2026-10-15T00:01:00Z','2026-10-16T00:01:00Z');stream=a.archive_stream('org/repo')
 context={'root':str(root),'work':str(work),'ref':ref,'branch':branch,'policies':policies,'policy':policy,'trust':str(trust),'approval':str(approval),'store':store}
 context_path=root/'context.json';context_path.write_text(json.dumps(context))
 header=fixture.split('\nwith tempfile.TemporaryDirectory() as tmp:',1)[0]
 state_code=textwrap.dedent(fixture.split(' class State:',1)[1].split('\n source=Source',1)[0]);state_code='class State:'+textwrap.indent(state_code,' ')
 adapter_code=textwrap.dedent(adapter)
 child='import sys\nselected_args=sys.argv[1:]\n'+header+'\nfrom urllib.parse import urlparse,parse_qs\nimport copy\ncontext=json.loads(pathlib.Path('+repr(str(context_path))+').read_text());globals().update(context);root=pathlib.Path(root);work=pathlib.Path(work);policies={int(k):v for k,v in policies.items()}\ndef git(*args,input=None,env=None,check=True):return subprocess.run(["git","-C",str(work),*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=check)\ndef out(*args):return git(*args).stdout.decode().strip()\n'+state_code+'\n'+adapter_code
 child+=textwrap.dedent(r"""
 late=Source(policy,receipt);late.run['created_at']='2026-10-15T00:00:30Z'
 mode=selected_args[1]
 class SourceView:
  repo='org/repo'
  def request(self,target,**kwargs):
   if mode=='unavailable':raise RuntimeError('synthetic source unavailable')
   if '/actions/workflows/' in target and '/runs?' in target:
    query=parse_qs(urlparse(target).query);lo,hi=query['created'][0].split('..');page=int(query['page'][0]);size=int(query['per_page'][0])
    rows=[]
    if mode in ('late','rerun') and lo<=late.run['created_at']<=hi:
     run=copy.deepcopy(late.run)
     if mode=='rerun':run.update(run_attempt=2,conclusion='failure')
     rows=[run]
    return {'total_count':len(rows),'workflow_runs':rows[(page-1)*size:page*size]}
   return late.request(target,**kwargs)
  def get(self,target):
   if '/actions/runs/' in target:
    run=copy.deepcopy(late.run)
    if mode=='rerun' and '/attempts/1' not in target:run.update(run_attempt=2,conclusion='failure')
    return run
   return late.get(target)
  def source(self,name,sha):return late.source(name,sha)
 def foreign_write():
  api=PipelineState();head=out('rev-parse',ref);blob=api.request('repos/org/repo/git/blobs','POST',{'encoding':'base64','content':base64.b64encode(b'opaque concurrent worker').decode()})
  tree=api.request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',head+'^{tree}'),'tree':[{'path':'reports/'+'9'*64+'.json','mode':'100644','type':'blob','sha':blob['sha']}]})
  commit=api.request('repos/org/repo/git/commits','POST',{'tree':tree['sha'],'parents':[head],'message':'concurrent protected worker'})
  api.request('repos/org/repo/git/refs/heads/'+branch,'PATCH',{'sha':commit['sha'],'force':False})
 class Interleaved(PipelineState):
  injected=False
  def request(self,target,method='GET',payload=None):
   if method=='POST' and target.endswith('/git/commits') and payload['message'].startswith('factory: reporting checkpoint ') and not self.injected:
    self.injected=True
    if mode=='race':self.before_patch=foreign_write
    elif mode=='lost':self.lost=True
   return super().request(target,method,payload)
 ms=importlib.util.spec_from_file_location('maintenance',scripts/'factory-reporting-maintenance.py');m=importlib.util.module_from_spec(ms);ms.loader.exec_module(m)
 print(json.dumps(m.maintain(SourceView(),Interleaved(),policy,trust,store,approval,interval_end=selected_args[0])))
 """)
 runner=root/'fresh-step.py';runner.write_text(child);compile(child,'actual-fresh-maintenance-step','exec')
 def step(end,mode='normal'):
  completed=subprocess.run([sys.executable,str(runner),end,mode],capture_output=True,text=True,timeout=90)
  assert completed.returncode==0,completed.stderr
  result=json.loads(completed.stdout);assert result['all_history_complete'] is False and result['task_credit'] is False
  return result
 def ready(end,mode='normal'):
  previous=None
  for invocation in range(96):
   result=step(end,mode)
   if result['phase']!=previous:print('fresh maintenance phase '+result['phase']+' invocation '+str(invocation),flush=True);previous=result['phase']
   if result['status']=='ready':assert result['coverage_complete'] is True;return result
   assert result['coverage_complete'] is False
  raise AssertionError('bounded protected phase progress did not reach usable interval coverage: '+str(result))
 first=ready(ends[0]);anchor=a.verify_bootstrap(PipelineState(),approval)
 first_manifest='receipt-archive/backfill/'+a.interval_scope(anchor,stream,ends[0],True)+'.json';old_manifest=git('show',ref+':'+first_manifest).stdout
 second_manifest='receipt-archive/backfill/'+a.interval_scope(anchor,stream,ends[1],True)+'.json'
 assert git('cat-file','-e',ref+':'+second_manifest,check=False).returncode!=0,'second interval was preseeded'
 # Actual non-fast-forward and lost acknowledgement must not silently reset state.
 race=subprocess.run([sys.executable,str(runner),ends[1],'race'],capture_output=True,text=True,timeout=90)
 assert race.returncode!=0 and 'CAS conflict' in race.stderr,race.stderr
 assert git('show',ref+':reports/'+'9'*64+'.json').stdout==b'opaque concurrent worker'
 lost=subprocess.run([sys.executable,str(runner),ends[1],'lost'],capture_output=True,text=True,timeout=90)
 assert lost.returncode!=0 and 'acknowledgement lost' in lost.stderr,lost.stderr
 second=ready(ends[1]);assert second['interval_end']==ends[1]
 assert git('show',ref+':'+first_manifest).stdout==old_manifest
 assert json.loads(git('show',ref+':'+second_manifest).stdout)['interval_start']=='2026-10-15T00:00:00Z'
 assert step(ends[1],'unavailable')['status']=='incomplete';second=ready(ends[1])
 # A genuinely late source is appended by actual reconciliation, then projected.
 late=ready(ends[1],'late')
 journal=json.loads(git('show',ref+':receipt-archive/discovery/'+stream+'.json').stdout);assert journal['records_count']==1
 assert step(ends[1],'rerun')['status']=='incomplete','unresolved later attempt granted coverage'
 for _ in range(8):assert step(ends[1],'rerun')['coverage_complete'] is False
 assert json.loads(git('show',ref+':receipt-archive/discovery/'+stream+'.json').stdout)['records_count']==1,'rerun duplicated retained delivery'
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual two-day scoped source/backfill/coverage, fresh-process resume, real CAS/lostack, late append/rerun gap and opaque preservation passed; no Slack/task credit')
'''
exec(compile(fixture+adapter+cases,'reporting-maintenance-fixture','exec'))
PY
