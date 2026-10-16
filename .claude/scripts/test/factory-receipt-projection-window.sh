#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: checked bounded windows require actual protected archive origin."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo')
 for n in (20,21,22):
  item=Source(policy,receipt);item.run['id']=n
  assert a.append_delivery(item,state,policy,n,trust,store,approval,stream)['status']=='appended'
 head=out('rev-parse',ref);end='2026-10-15T23:00:00Z'
 def window(**kwargs):return a.projection_window(State(),policy,trust,store,approval,stream,interval_end=end,**kwargs)
 first=window(start=0,limit=1)
 assert first['references'][0]['run_id']==20 and first['references'][0]['segment']==0
 assert first['start']==0 and first['next_segment']==1 and first['records_count']==3 and len(first['proofs'])==1
 assert first['frozen_head']==head and first['tree']==out('rev-parse',head+'^{tree}') and first['coverage_complete'] is False and first['all_segments_checked'] is False
 second=window(start=1,limit=1,frozen_head=head)
 assert second['next_segment']==2 and json.loads(second['proofs'][0]['provenance'])['run_id']==21
 assert window(start=3,limit=1,frozen_head=head)['proofs']==[]
 before=out('rev-parse',ref)
 def reject(fn,reason):
  try:fn()
  except ValueError as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('accepted '+reason)
  assert out('rev-parse',ref)==before
 reject(lambda:window(start=0,limit=129),'window bounds')
 reject(lambda:window(start=True,limit=1),'window bounds')
 reject(lambda:window(start=4,limit=1),'window range')
 class ForeignFrozen(State):
  def request(self,path,**kwargs):
   if '/compare/' in path:
    base=path.rsplit('/',1)[1].split('...')[0]
    return {'base_commit':{'sha':base},'merge_base_commit':{'sha':'e'*40},'status':'diverged','behind_by':1,'ahead_by':1,'total_commits':1}
   return super().request(path,**kwargs)
 reject(lambda:a.projection_window(ForeignFrozen(),policy,trust,store,approval,stream,interval_end=end,start=0,limit=1,frozen_head='f'*40),'ancestry')
 reject(lambda:window(start=0,limit=3),'conflicting reporting delivery proof')
 reject(lambda:a.projection_window(State(),policy,trust,store,approval,stream,interval_end='2020-01-01T00:00:00Z'),'interval')
 class NoOrigin(State):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/rulesets/1' in path:value=copy.deepcopy(value);value['bypass_actors']=[]
   return value
 reject(lambda:a.projection_window(NoOrigin(),policy,trust,store,approval,stream,interval_end=end),'protection policy changed')
 current=json.loads(trust.read_bytes());current['profiles'][0]['status']='revoked';trust.write_text(json.dumps(current))
 revoked=window(start=0,limit=1,frozen_head=head)
 assert revoked['proofs'][0]['trust_status']=='withdrawn' and revoked['trust_sha256']!=first['trust_sha256']
 class Budget(State):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/git/trees/' in path:value['padding']='x'*2097153
   return value
 reject(lambda:a.projection_window(Budget(),policy,trust,store,approval,stream,interval_end=end),'observation bound')
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 assert not list(root.glob('*.sqlite'))
 class Concurrent(State):
  reads=0
  def request(self,path,**kwargs):
   if '/git/ref/' in path:
    self.reads+=1
    if self.reads==3:
     previous=out('rev-parse',ref);new=git('commit-tree',out('rev-parse',ref+'^{tree}'),'-p',previous,input=b'concurrent reporter').stdout.decode().strip();git('update-ref',ref,new,previous)
   return super().request(path,**kwargs)
 try:a.projection_window(Concurrent(),policy,trust,store,approval,stream,interval_end=end,start=0,limit=1)
 except ValueError as error:assert 'origin changed' in str(error)
 else:raise AssertionError('stale frozen view returned after concurrent reporter')
 git('update-ref',ref,head,out('rev-parse',ref))
 assert not list(root.glob('*.sqlite'))
 print('17 protected frozen-window range/budget/revocation/privacy/read-only cases passed')
'''
exec(compile(fixture+cases,'protected-projection-window-fixture','exec'))
PY
