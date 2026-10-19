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
if selected_case=='stale-source':
 hosted_case=Path('.claude/scripts/test/factory-reporting-hosted-maintenance.sh').read_text().split("cases=r'''\n",1)[1]
 setup=hosted_case.split(' result=hosted.run(',1)[0]
 delivery=' class Delivery:'+hosted_case.split(' class Delivery:',1)[1].split(' gap_seen=False',1)[0]
 cases=r'''
 delivery=Delivery();hosted.slack.transport=lambda client,configured,batch:delivery
 for invocation in range(48):
  result=hosted.run(config,Report(),CurrentState(),NoSlack(),root/('stale-'+str(invocation)+'.sqlite'),datetime.datetime(2026,10,16,0,tzinfo=datetime.timezone.utc))
  if result.get('phase')=='projection-pending':break
  assert result['status']=='incomplete',result
 else:raise AssertionError('actual late source did not produce coverage gap')
 assert visible['late'] and delivery.sends==0 and not ack_seen
 before=json.loads(git('show',ref+':'+progress_leaf).stdout)
 assert before['phase'] in ('verify','backfill')
 if before['phase']=='verify':
  # Complete only actual origin work, then exercise one actual hosted retry.
  # This avoids spending96 repeated stale projection calls to demonstrate the bug.
  for _ in range(16):
   progress=a.advance_origin(PipelineState(),approval,commit_budget=16,tree_pages=4)
   if progress['frozen_complete']:break
  else:raise AssertionError('targeted stale-source origin did not finish')
  result=hosted.run(config,Report(),CurrentState(),NoSlack(),root/'stale-retry.sqlite',datetime.datetime(2026,10,16,0,tzinfo=datetime.timezone.utc))
  after=json.loads(git('show',ref+':'+progress_leaf).stdout)
  assert result['status']=='incomplete' and result['phase']=='projection-pending' and delivery.sends==0
 else:after=before
 assert after['phase']=='backfill','actual changed-source coverage gap retained stale verify campaign'
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('AC-7 actual late-source identity gap starts bounded backfill without delivery PASS',flush=True)
'''
 exec(compile(base+adapter+setup+delivery+cases,'maintenance-actual-stale-source','exec'))
if selected_case in ('all','quiet','ack-resume'):
 rollover=Path('.claude/scripts/test/factory-reporting-rollover.sh').read_text();assert "cases=r'''\n" in rollover
 setup=rollover.split("cases=r'''\n",1)[1].split(' first_now=',1)[0]
 setup=setup.replace("assert kwargs=={},kwargs","assert kwargs in ({},{'paginate':True}),kwargs").replace("query=parse_qs(urlparse(path).query);page=int(query['page'][0]);return self.rows[(page-1)*100:page*100]","if kwargs.get('paginate'):return [copy.deepcopy(self.rows)]\n    query=parse_qs(urlparse(path).query);page=int(query['page'][0]);size=int(query['per_page'][0]);return self.rows[(page-1)*size:page*size]").replace("'pr_discovery_mode':'resumable'","'pr_discovery_mode':'legacy'")
 if selected_case=='ack-resume':
  setup=setup.replace("'pr_discovery_mode':'legacy'","'pr_discovery_mode':'resumable'")
  setup+=r'''
 actual_spec=importlib.util.spec_from_file_location;blocked=[];refused=[];validated=[];ack_epoch=[]
 def instrument(name,path,*args,**kwargs):
  spec=actual_spec(name,path,*args,**kwargs)
  if name=='report_maintenance':
   loader=spec.loader
   class Loader:
    def create_module(self,spec):return loader.create_module(spec)
    def exec_module(self,module):
     loader.exec_module(module);actual_ack=module.acknowledge_reporting
     def delayed_ack(*args,**kwargs):
      if not blocked:
       blocked.append(True);actual_origin=module.archive.advance_origin
       module.archive.advance_origin=lambda *a,**k:{'frozen_complete':False}
       try:result=actual_ack(*args,**kwargs)
       finally:module.archive.advance_origin=actual_origin
       assert result['phase']=='origin' and remote.sends==0
       saved_head=out('rev-parse',ref);saved_raw=git('show',ref+':'+journal_path).stdout
       assert json.loads(saved_raw)['phase']=='verify'
       ack_epoch.append(json.loads(saved_raw)['source_epoch'])
       wrong=dict(kwargs,campaign='f'*64)
       try:actual_ack(*args,**wrong)
       except ValueError as error:assert str(error)=='maintenance projection acknowledgement selector changed'
       else:raise AssertionError('foreign selector acknowledged')
       assert git('show',ref+':'+journal_path).stdout==saved_raw
       # Disposable real-Git fixture branches are restored only after proving each
       # changed current input resets scheduling, never returns retry selectors.
       original_trust=trust.read_bytes()
       for changed in ('trust','policy','ordinary'):
        selected_policy=copy.deepcopy(policy)
        if changed=='trust':trust.write_bytes(original_trust+b' ')
        if changed=='policy':selected_policy['merge_enabled']=not selected_policy['merge_enabled']
        try:
         action=module.maintain if changed=='ordinary' else module.select_reporting
         rejected=action(reports,PipelineState(),selected_policy,trust,{'repository':'org/repo','visibility':'public'},approval,interval_end=kwargs['interval_end'])
         assert rejected['phase']=='backfill' and rejected['status']=='incomplete',changed
         assert remote.sends==0
        finally:
         trust.write_bytes(original_trust)
         git('update-ref',ref,saved_head,out('rev-parse',ref))
       assert git('show',ref+':'+journal_path).stdout==saved_raw
       return result
      return actual_ack(*args,**kwargs)
     module.acknowledge_reporting=delayed_ack
   spec.loader=Loader()
  if name=='report_receipts':
   loader=spec.loader
   class ReceiptLoader:
    def create_module(self,spec):return loader.create_module(spec)
    def exec_module(self,module):
     loader.exec_module(module);actual_project=module.project
     def refused_once(*args,**kwargs):
      result=actual_project(*args,**kwargs);validated.append(result['coverage_complete'])
      if not refused:
       refused.append(True)
       # Explicit synthetic consumer refusal AFTER actual fresh validation.
       return dict(result,coverage_complete=False)
      return result
     module.project=refused_once
   spec.loader=ReceiptLoader()
  return spec
 importlib.util.spec_from_file_location=instrument
'''
 cases=r'''
 now=datetime(2026,10,14,22,5,tzinfo=timezone.utc);role=a.digest(a.canonical(['reporting-maintenance-v1','org/repo',branch]));journal_path='reports/'+role+'.json'
 def step(index):return h.run(config,reports,PipelineState(),None,root/('legacy-'+str(index)+'.sqlite'),now)
 for index in range(96):
  result=step(index)
  if selected_case=='ack-resume' and result.get('phase')=='projection-pending':
   assert remote.sends==0 and refused and not blocked
  if result['status']=='delivered':break
 else:raise AssertionError('actual legacy durable interval never delivered')
 if selected_case=='ack-resume':
  assert blocked and refused and len(validated)>=3 and all(validated),'retry skipped actual fresh projection'
  saved=json.loads(git('show',ref+':'+journal_path).stdout)
  assert saved['source_epoch']==ack_epoch[0],'acknowledgement retry rebuilt the same interval campaign'
  assert saved['phase']=='ready' and remote.sends==1
  print('AC-7 actual hosted retry after incomplete acknowledgement origin delivers without campaign rebuild PASS',flush=True)
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
if [[ "${1:-all}" == all ]]; then
  bash "$0" ack-resume
  bash "$0" stale-source
fi
