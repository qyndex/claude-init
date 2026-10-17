#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: actual bounded cold-start partitions and retained reporting compose."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Fresh processes import actual code',1)[0]
pipeline+=" second=a.checkpoint_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,limit=1)\n context={'history':out('rev-parse',ref)}\n two=a.stage_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=end,history_head=context['history'],limit=1)\n"
cases=r'''
 spec=importlib.util.spec_from_file_location('discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 start='2026-10-15T00:00:00Z';end_created=end
 for n,item in enumerate(sources):item.run['created_at']=f'2026-10-15T00:00:0{n}Z'
 class Runs:
  repo='org/repo'
  def get(self,target):
   if '/actions/runs/' in target:
    self.detail_calls=getattr(self,'detail_calls',0)+1
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
 blob_spec=importlib.util.spec_from_file_location('coverage_blob_provider',scripts/'test/factory-receipt-blob-provider.py');bp=importlib.util.module_from_spec(blob_spec);blob_spec.loader.exec_module(bp);bp.attach(PipelineState,work,root,pull_requests={n:{'number':n,'merged':True,'merge_commit_sha':('b' if n==7 else 'c')*40,'merged_at':'2026-10-15T01:00:00.123456Z','base':{'repo':{'id':101,'full_name':'org/repo'}}} for n in (7,8)})
 original_batch=PipelineState.read_blobs;batch_calls=[]
 original_pr=PipelineState.read_pull_requests;pr_calls=[];pr_rest=[];original_request=PipelineState.request
 def measured_pr(self,repo,numbers):
  pr_calls.append(list(numbers));return original_pr(self,repo,numbers)
 def measured_request(self,target,method='GET',payload=None):
  if '/pulls/' in target:pr_rest.append(target)
  return original_request(self,target,method,payload)
 PipelineState.read_pull_requests=measured_pr;PipelineState.request=measured_request
 def measured_batch(self,repo,entries):
  batch_calls.append(len(entries));return original_batch(self,repo,entries)
 PipelineState.read_blobs=measured_batch
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
 runs.detail_calls=0;pr_rest.clear()
 result=d.coverage(runs,PipelineState(),policy,trust,store,approval,stream,interval_end=end_created,projection_end=end,history_head=context['history'],campaign=campaign,page_size=1)
 assert result['coverage_complete'] and result['source_partition_complete'] and result['frozen_projection_complete'],result
 assert result['all_history_complete'] is False and result['task_credit'] is False
 assert batch_calls, 'coverage discarded concrete bounded Blob capability'
 assert pr_calls and not pr_rest, 'coverage discarded fresh PR batch capability or hid per-PR REST calls'
 assert getattr(runs,'detail_calls',0)==0, 'coverage rereads each listed source run instead of rechecking exact listing pages'
 def verify(source=runs,state=None):
  return d.coverage(source,state or PipelineState(),policy,trust,store,approval,stream,interval_end=end_created,projection_end=end,history_head=context['history'],campaign=campaign,page_size=1)
 before=out('rev-parse',ref)
 class FloatPR(PipelineState):
  def read_pull_requests(self,repo,numbers):
   value=original_pr(self,repo,numbers);value['pull_requests']={float(k):v for k,v in value['pull_requests'].items()};return value
 try:verify(state=FloatPR())
 except ValueError:pass
 else:raise AssertionError('float PR map keys accepted as exact integer identifiers')
 class LatePage(Runs):
  def __init__(self):self.seen={}
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs)
   if '/actions/workflows/' in target:
    self.seen[target]=self.seen.get(target,0)+1
    if self.seen[target]>1 and value['workflow_runs']:value['workflow_runs'][0]['head_sha']='f'*40
   return value
 changed=verify(LatePage());assert not changed['coverage_complete'] and 'source-changed-during-coverage' in changed['gaps'],changed
 class Foreign(Runs):
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs)
   if value.get('workflow_runs'):value['workflow_runs'][0]['repository']['id']=999
   return value
 try:verify(Foreign())
 except ValueError:pass
 else:raise AssertionError('foreign full listing authorized coverage')
 for mutation in ('bool-calls','zero-bytes','oversize-bytes','foreign-object'):
  class Forged(PipelineState):
   def read_blobs(self,repo,entries):
    value=original_batch(self,repo,entries)
    if mutation=='bool-calls':value['calls']=True
    elif mutation=='zero-bytes':value['raw_bytes']=0
    elif mutation=='oversize-bytes':value['raw_bytes']=2097153
    else:value['blobs'][entries[0]['sha']]['sha']='f'*40
    return value
  try:verify(state=Forged())
  except ValueError:pass
  else:raise AssertionError('forged batch metadata authorized coverage: '+mutation)
 for mutation in ('bool-calls','zero-bytes','oversize-bytes','foreign-base'):
  class ForgedPR(PipelineState):
   def read_pull_requests(self,repo,numbers):
    value=original_pr(self,repo,numbers)
    if mutation=='bool-calls':value['calls']=True
    elif mutation=='zero-bytes':value['raw_bytes']=0
    elif mutation=='oversize-bytes':value['raw_bytes']=2097153
    else:value['pull_requests'][numbers[0]]['base']['repo']['id']=999
    return value
  try:verify(state=ForgedPR())
  except ValueError:pass
  else:raise AssertionError('forged PR batch authorized coverage '+mutation)
 facts_path=root/'blob-provider-bin/pull-requests.json';saved_facts=facts_path.read_bytes();changed=json.loads(saved_facts);changed['7']['merged_at']='2026-10-15T01:00:00.123457Z';facts_path.write_text(json.dumps(changed))
 try:verify()
 except ValueError as error:assert 'staged facts differ' in str(error),str(error)
 else:raise AssertionError('fresh changed PR time reused previous observation')
 changed['7']['merged_at']=None;facts_path.write_text(json.dumps(changed));missing=verify();assert not missing['coverage_complete'] and 'required-projection-gap' in missing['gaps'],missing
 facts_path.write_bytes(saved_facts)
 assert out('rev-parse',ref)==before,'read-only coverage changed protected state'
 print('actual protected coverage uses bounded Blob adapter and fresh full source listing identity; late-page drift, foreign repository and four forged batch metadata cases reject without state/task credit')
'''
exec(compile(fixture+pipeline+cases,'actual-coverage-batch-real-git','exec'))
PY
