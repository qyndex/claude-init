#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
from pathlib import Path
import copy,tempfile
from urllib.parse import urlparse,parse_qs
source=Path('.claude/scripts/test/factory-reporting-queue-observation.sh').read_text().split("python3 - <<'PY'\n",1)[1].split('count=0\nwith tempfile',1)[0]
exec(compile(source,'actual-queue-list-retry-fixture','exec'))
BaseAPI=API
class RetryAPI(BaseAPI):
 def __init__(self):super().__init__();self.mode='none';self.sweeps=0
 def request(self,path,method='GET',payload=None):
  if self.readonly:assert method=='GET' and payload is None,'observer wrote state'
  if '/actions/workflows/' in path and '/runs?' in path:
   parts=path.split('/');workflow=int(parts[5]);query=parse_qs(urlparse(path).query);status=query['status'][0];page=int(query['page'][0])
   if workflow==9 and status=='queued' and page==1:self.sweeps+=1
   if workflow==9 and status=='queued':
    if self.mode in ('transient','persistent','second-transient') and (self.mode=='persistent' or self.sweeps==(2 if self.mode=='second-transient' else 1)):return {'total_count':1,'workflow_runs':[]}
    if self.mode=='page2' and self.sweeps==1:return {'total_count':101 if page==1 else 100,'workflow_runs':[dict(copy.deepcopy(run),id=700+i,status='queued') for i in range(100)] if page==1 else []}
    if self.mode.startswith('invalid:'):
     kind=self.mode.split(':')[1]
     if kind=='boolean-count':return {'total_count':True,'workflow_runs':[]}
     if kind=='capacity':return {'total_count':201,'workflow_runs':[]}
     value=dict(copy.deepcopy(run),status='queued')
     if kind=='foreign':value['repository']={'id':102,'full_name':'org/repo'}
     if kind=='clock':value['updated_at']='9999-01-01T00:00:00Z'
     if kind=='attempt':value['run_attempt']=True
     if kind=='duplicate':return {'total_count':2,'workflow_runs':[value,value]}
     return {'total_count':1,'workflow_runs':[value]}
   if self.mode=='discard-partial' and self.sweeps==1:
    if workflow==9 and status=='waiting':return {'total_count':1,'workflow_runs':[copy.deepcopy(run)]}
    if workflow==10 and status=='queued':return {'total_count':1,'workflow_runs':[]}
  return super().request(path,method,payload)
with tempfile.TemporaryDirectory() as temp:
 api=RetryAPI();storage={'state_branch':'factory-reporting-state','bootstrap_sha':api.head,'initialize':False,'policy_approvals':{}}
 hc=ns['config'];state=ns['m'];store=state.HostedDigest(Path(temp)/'worker',hc,state.GitState(api,hc['state_branch'],ns['stream'],hc['bootstrap_sha']))
 batch=store.prepare(ns['ReportAPI'](),state.slack.due(now));store.deliver(batch['key'],ns['Transport']());api.readonly=True;before=api.head
 def candidate(mode):
  value=copy.deepcopy(api);value.mode=mode;value.calls=[];value.sweeps=0;return value
 def observe(mode):
  value=candidate(mode);result=q.observe_queue(value,config,storage,now);assert value.head==before;return value,result
 for mode in ['transient','second-transient','page2','discard-partial']:
  value,result=observe(mode)
  assert result['status']=='metadata-current' and result['coverage_complete'] and not result['stalled'],(mode,result)
  assert value.sweeps==3,(mode,value.sweeps) # One failed whole sweep, then two complete equal snapshots.
  assert result['receipt_verified'] is False and result['recovery_eligible'] is False
 value,result=observe('persistent');assert result['status']=='unknown' and result['reason']=='run-list-incomplete-or-changed' and value.sweeps==2
 for kind in ['boolean-count','capacity','foreign','clock','attempt','duplicate']:
  value,result=observe('invalid:'+kind);assert result['status']=='unknown' and not result['coverage_complete'] and value.sweeps==1,(kind,result,value.sweeps)
 # Existing outer changes and partial jobs are not retried by this narrow list wrapper.
 value=candidate('none');value.late=True;result=q.observe_queue(value,config,storage,now);assert result['status']=='unknown' and result['reason']=='metadata-observation-changed' and value.sweeps==2
 value=candidate('none');value.runs=[copy.deepcopy(run)];value.partial_jobs=True;result=q.observe_queue(value,config,storage,now);assert result['status']=='unknown' and result['reason']=='job-list-incomplete-or-capacity' and value.sweeps==1
 # Existing after-observation protected health/repository equality still rejects drift.
 for method,field,replacement in [('worker_health','checkpoint_sha','e'*40),('repository_metadata','private',True)]:
  value=candidate('none');reader=q._QueueReader(value,config,storage,now);original=getattr(reader,method);observations=[0]
  def changed():
   item=original();observations[0]+=1
   if method=='repository_metadata' or observations[0]>1:item[field]=replacement
   return item
  setattr(reader,method,changed)
  try:reader.observe()
  except q._QueueObservationError as error:assert error.args==('protected-health-or-repository-changed',),error.args
  else:raise AssertionError('protected observation drift accepted')
  assert value.head==before
 # Retry requires the exact trusted exception class and one exact fixed argument.
 for failure in [ValueError('run-list-incomplete-or-changed'),q._QueueObservationError('metadata-invalid'),q._QueueObservationError('run-list-incomplete-or-changed','extra')]:
  value=candidate('none');reader=q._QueueReader(value,config,storage,now);attempts=[0]
  def fail_once():attempts[0]+=1;raise failure
  reader._runs_once=fail_once
  try:reader.runs()
  except ValueError as error:assert error is failure
  else:raise AssertionError('nonmatching exception accepted')
  assert attempts==[1] and value.head==before
 # Neither retry resets the same store's original call/byte budgets or captured clock.
 for budget in ['calls','bytes']:
  value=candidate('transient');reader=q._QueueReader(value,config,storage,now);original_now=reader.now;owned=reader.store
  if budget=='calls':owned.calls=126
  else:
   meta={'id':9,'path':workflows[9],'state':'active'};failed={'total_count':1,'workflow_runs':[]}
   owned.consumed=33554432-len(q.canonical(meta))-len(q.canonical(failed))
  try:reader.runs()
  except ValueError as error:assert 'bound exceeded' in str(error),str(error)
  else:raise AssertionError('retry reset '+budget+' budget')
  assert reader.store is owned and reader.now==original_now and value.sweeps==1 and value.head==before
  if budget=='calls':assert owned.calls==128
  else:assert owned.consumed>33554432
 print('Actual queue list retry: transient/full-sweep discard, persistent two-bound, nonretryable identity/clock/jobs/outer drift and shared128call/32MiB budgets PASS; no state writes or receipt credit')
PY
