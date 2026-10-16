#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: actual bounded cold-start partitions and retained reporting compose."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Live source artifacts',1)[0]
cases=r'''
 spec=importlib.util.spec_from_file_location('discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 start='2026-10-15T00:00:00Z';end_created=end
 for n,item in enumerate(sources):item.run['created_at']=f'2026-10-15T00:00:0{n}Z'
 class Runs:
  repo='org/repo'
  def get(self,target):
   if '/actions/runs/' in target:
    identity=int(target.split('/actions/runs/')[1].split('/')[0]);item=next(s for s in sources if s.run['id']==identity)
    return copy.deepcopy(item.run)
   return sources[0].get(target)
  def source(self,name,sha):return sources[0].source(name,sha)
  def request(self,target,**kwargs):
   if '/actions/workflows/' in target:
    query=parse_qs(urlparse(target).query);lo,hi=query.get('created',[start+'..'+end_created])[0].split('..');size=int(query['per_page'][0]);page=int(query['page'][0])
    rows=[copy.deepcopy(item.run) for item in sources if lo<=item.run['created_at']<=hi];rows.sort(key=lambda row:row['id'])
    return {'total_count':len(rows),'workflow_runs':rows[(page-1)*size:page*size]}
   return sources[0].request(target,**kwargs)
 runs=Runs()
 d.advance(runs,PipelineState(),policy,approval,stream,page_size=1)
 for _ in range(3):assert d.backfill(runs,PipelineState(),policy,approval,stream,interval_end=end_created,page_size=1)['complete'] is False
 manifest=json.loads(git('show',ref+':receipt-archive/backfill/'+stream+'.json').stdout)
 assert manifest['epoch']==1 and manifest['last_round_gaps']==0
 d.reconcile(runs,PipelineState(),policy,trust,store,approval,stream,review_rows=4)
 partial=d.coverage(runs,PipelineState(),policy,trust,store,approval,stream,interval_end=end_created,projection_end=end,history_head=context['history'],campaign=campaign,page_size=1)
 assert partial['coverage_complete'] is False and partial['verified_until'] is None and 'protected-scan-incomplete' in partial['gaps'],partial
 for _ in range(32):
  progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
  if progress['scan']['complete']:break
  d.reconcile(runs,PipelineState(),policy,trust,store,approval,stream,review_rows=4)
 assert progress['scan']['complete'],'actual protected tree scan did not resume'
 result=d.coverage(runs,PipelineState(),policy,trust,store,approval,stream,interval_end=end_created,projection_end=end,history_head=context['history'],campaign=campaign,page_size=1)
 assert result['coverage_complete'] and result['source_partition_complete'] and result['frozen_projection_complete'],result
 assert result['all_history_complete'] is False and result['task_credit'] is False
 def evaluate(provider=runs,state=None):
  before=out('rev-parse',ref)
  result=d.coverage(provider,state or PipelineState(),policy,trust,store,approval,stream,interval_end=end_created,projection_end=end,history_head=context['history'],campaign=campaign,page_size=1)
  assert out('rev-parse',ref)==before,'coverage attempted a state write'
  return result
 def gap(provider,reason):
  result=evaluate(provider);assert result['coverage_complete'] is False and result['verified_until'] is None and reason in result['gaps'],result
 class Swap(Runs):
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs)
   if '/actions/workflows/' in target and value['workflow_runs']:
    value=copy.deepcopy(value);value['workflow_runs'][0]['id']=99
   return value
 gap(Swap(),'source-identities-changed') # same count, late old-created identity swap
 class CountDrift(Runs):
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs)
   return dict(value,total_count=value['total_count']+1) if '/actions/workflows/' in target else value
 gap(CountDrift(),'source-identities-changed')
 class Capped(Runs):
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs)
   return dict(value,total_count=1000) if '/actions/workflows/' in target else value
 gap(Capped(),'source-identities-changed')
 class Unavailable(Runs):
  def request(self,target,**kwargs):raise RuntimeError('DO_NOT_PERSIST_SOURCE_TRANSPORT')
 gap(Unavailable(),'required-observation-unavailable')
 class Budget(Runs):
  def request(self,target,**kwargs):return dict(super().request(target,**kwargs),padding='x'*2097153)
 gap(Budget(),'invocation-capacity')
 class During(Runs):
  queries={}
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs);self.queries[target]=self.queries.get(target,0)+1
   if self.queries[target]>1 and value.get('workflow_runs'):
    value=copy.deepcopy(value);value['workflow_runs'][0]['id']=98
   return value
 gap(During(),'source-changed-during-coverage')
 active=trust.read_bytes();withdrawn=json.loads(active);withdrawn['profiles'][0]['status']='revoked';trust.write_text(json.dumps(withdrawn))
 revoked=evaluate();assert revoked['coverage_complete'] and revoked['withdrawn_attempts']==2,revoked
 trust.write_bytes(active)
 # Missing required immutable partition history is not an empty-source observation.
 part=next(name for name in out('ls-tree','-r','--name-only',ref).splitlines() if name.startswith('receipt-archive/backfill/'+stream+'/'))
 oldblob=out('rev-parse',ref+':'+part);index=root/'coverage-remove-index';env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',out('rev-parse',ref+'^{tree}'),env=env);git('update-index','--force-remove',part,env=env)
 removed_tree=git('write-tree',env=env).stdout.decode().strip();index.unlink();before=out('rev-parse',ref);removed=git('commit-tree',removed_tree,'-p',before,input=b'missing coverage partition').stdout.decode().strip();git('update-ref',ref,removed,before)
 gap(runs,'required-partition-missing')
 restored=PipelineState().request('repos/org/repo/git/trees','POST',{'base_tree':removed_tree,'tree':[{'path':part,'type':'blob','mode':'100644','sha':oldblob}]})['sha'];restored_head=git('commit-tree',restored,'-p',removed,input=b'restore partition').stdout.decode().strip();git('update-ref',ref,restored_head,removed)
 # A saturated parent's lower-bound count cannot contradict its child union.
 class HierarchyCap(Runs):
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs)
   if '/actions/workflows/' in target and parse_qs(urlparse(target).query).get('created')==[start+'..'+end_created]:value=dict(value,total_count=1000)
   return value
 capped=HierarchyCap();savedhead=out('rev-parse',ref);epoch_before=manifest['epoch']
 for _ in range(12):
  d.backfill(capped,PipelineState(),policy,approval,stream,interval_end=end_created,page_size=1)
  updated=json.loads(git('show',ref+':receipt-archive/backfill/'+stream+'.json').stdout)
  if updated['epoch']>epoch_before:break
 assert updated['epoch']==epoch_before+1 and updated['last_round_gaps']==0
 gap(capped,'source-partition-count-inconsistent')
 git('update-ref',ref,savedhead,out('rev-parse',ref))
 # An actual new attempt on an old-created run is not skipped by a watermark.
 sources[0].run.update(run_attempt=2,conclusion='failure')
 gap(runs,'source-identities-changed')
 for _ in range(3):d.backfill(runs,PipelineState(),policy,approval,stream,interval_end=end_created,page_size=1)
 for _ in range(4):d.reconcile(runs,PipelineState(),policy,trust,store,approval,stream,review_rows=4)
 unresolved=evaluate();assert unresolved['coverage_complete'] is False and unresolved['verified_until'] is None and 'required-attempt-unresolved' in unresolved['gaps'],unresolved
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 # Actual publication origin cannot turn a false zero count over known data
 # into an empty reconstruction. This is a disposable forged-writer negative.
 stable=out('rev-parse',ref);positive=out('rev-parse',first['head']+'^');path='receipt-archive/projection/'+stream+'.json'
 empty_claim=json.loads(git('show',first['head']+':'+path).stdout)
 empty_claim.update(records_count=0,next_segment=0,previous_blob=None,publication_parent=positive)
 empty_claim['window'].update(start=0,stop=0,references=[])
 raw=a.canonical(empty_claim);blob=git('hash-object','-w','--stdin',input=raw).stdout.decode().strip()
 newtree=PipelineState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',positive+'^{tree}'),'tree':[{'path':path,'type':'blob','mode':'100644','sha':blob}]})['sha']
 forged=git('commit-tree',newtree,'-p',positive,input=b'false zero checkpoint fixture').stdout.decode().strip();git('update-ref',ref,forged,stable)
 empty_campaign=a.digest(a.canonical(dict(empty_claim['binding'],frozen_head=empty_claim['frozen_head'],frozen_tree=empty_claim['frozen_tree'],trust_sha256=a.digest(trust.read_bytes()))))
 try:a.reconstruct_interval(PipelineState(),policy,root/'false-empty.sqlite',trust,store,approval,stream,interval_end=end,history_head=forged,campaign=empty_campaign)
 except ValueError as error:assert 'empty retained snapshot differs' in str(error),str(error)
 else:raise AssertionError('false empty checkpoint hid actual retained data')
 assert not (root/'false-empty.sqlite').exists()
 git('update-ref',ref,stable,forged)
 print('actual cold-start/protected projection coverage passed: resolved interval, old-created rerun and same-count late swap/count/capacity/unavailable/mutable-source/missing-history gaps, current withdrawal, no cursor advance or state/task writes')
'''
# Keep the fixture's dynamic PipelineState extraction bound to its original text.
original=pipeline
pipeline=pipeline.replace("cases.split(' class PipelineState(State):',1)","original.split(' class PipelineState(State):',1)")
exec(compile(fixture+pipeline+cases,'composed-coverage-real-git-fixture','exec'))
empty_setup=pipeline.split(' # Two distinct approved tasks',1)[0]
empty=r'''
 spec=importlib.util.spec_from_file_location('empty_discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo');end='2026-10-15T00:00:00Z'
 class EmptyRuns(Source):
  def request(self,target,**kwargs):
   if '/actions/workflows/' in target:return {'total_count':0,'workflow_runs':[]}
   return super().request(target,**kwargs)
 runs=EmptyRuns(policy,receipt)
 for _ in range(2):d.backfill(runs,PipelineState(),policy,approval,stream,interval_end=end,page_size=1)
 missing=d.coverage(runs,PipelineState(),policy,trust,store,approval,stream,interval_end=end,projection_end=end,history_head=out('rev-parse',ref),campaign='f'*64,page_size=1)
 assert missing['coverage_complete'] is False and missing['verified_until'] is None,missing
 checkpoint=a.checkpoint_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,limit=1)
 assert checkpoint['frozen_complete'] and checkpoint['next_segment']==0
 history=out('rev-parse',ref)
 stage=a.stage_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,history_head=history,limit=1)
 assert stage['facts_count']==0
 result=d.coverage(runs,PipelineState(),policy,trust,store,approval,stream,interval_end=end,projection_end=end,history_head=history,campaign=stage['campaign'],page_size=1)
 assert result['coverage_complete'] and result['retained_attempts']==0 and result['verified_until']==end,result
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 # New known retained data after the empty freeze cannot hide behind API lag.
 assert a.append_delivery(Source(policy,receipt),PipelineState(),policy,20,trust,store,approval,stream)['status']=='appended'
 stale=d.coverage(runs,PipelineState(),policy,trust,store,approval,stream,interval_end=end,projection_end=end,history_head=history,campaign=stage['campaign'],page_size=1)
 assert stale['coverage_complete'] is False and stale['verified_until'] is None and 'retained-snapshot-incomplete' in stale['gaps'],stale
 print('actual empty reviewed-origin/protected-checkpoint/fresh-SQLite initialization and known retained-suffix refusal passed; missing checkpoint never complete')
'''
exec(compile(fixture+empty_setup+empty,'empty-coverage-real-git-fixture','exec'))
prior=r'''
 spec=importlib.util.spec_from_file_location('prior_discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo');end='2026-10-15T23:00:00Z'
 item=Source(policy,receipt);item.run.update(run_attempt=2,created_at='2026-10-15T00:00:00Z')
 assert a.append_delivery(item,PipelineState(),policy,20,trust,store,approval,stream)['status']=='appended'
 class Latest:
  repo='org/repo'
  def get(self,target):
   if '/attempts/' in target:raise RuntimeError('prior attempt history unavailable')
   return copy.deepcopy(item.run) if '/actions/runs/' in target else item.get(target)
  def source(self,name,sha):return item.source(name,sha)
  def request(self,target,**kwargs):return {'total_count':1,'workflow_runs':[copy.deepcopy(item.run)]} if '/actions/workflows/' in target else item.request(target,**kwargs)
 latest=Latest()
 for _ in range(2):d.backfill(latest,PipelineState(),policy,approval,stream,interval_end=end,page_size=1)
 for _ in range(32):
  progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
  if progress['scan']['complete']:break
  d.reconcile(latest,PipelineState(),policy,trust,store,approval,stream,review_rows=4)
 assert progress['scan']['complete']
 checkpoint=a.checkpoint_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,limit=1);history=out('rev-parse',ref)
 stage=a.stage_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,history_head=history,limit=1)
 before=out('rev-parse',ref)
 result=d.coverage(latest,PipelineState(),policy,trust,store,approval,stream,interval_end=end,projection_end=end,history_head=history,campaign=stage['campaign'],page_size=1)
 assert result['coverage_complete'] is False and result['verified_until'] is None and 'required-prior-attempt-history-missing' in result['gaps'],result
 assert out('rev-parse',ref)==before and git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual first-seen retained attempt2 keeps unknown merge-capable prior attempt1 as explicit history gap')
'''
exec(compile(fixture+empty_setup+prior,'prior-attempt-real-git-fixture','exec'))
PY
