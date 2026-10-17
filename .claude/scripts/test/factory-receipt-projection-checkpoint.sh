#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: protected checkpoint lineage and real Git CAS across invocations."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 from urllib.parse import urlparse,parse_qs
 class ProjectionState(State):
  def request(self,path,method='GET',payload=None):
   if method=='GET' and '/compare/' in path:
    base,head=path.split('?',1)[0].rsplit('/',1)[1].split('...');ancestor=git('merge-base','--is-ancestor',base,head,check=False).returncode==0
    return {'base_commit':{'sha':base},'merge_base_commit':{'sha':out('merge-base',base,head)},'status':'identical' if base==head else 'ahead' if ancestor else 'diverged','behind_by':0 if ancestor else 1,'ahead_by':0 if base==head else 1,'total_commits':0 if base==head else 1}
   if method=='GET' and '/commits?' in path:
    query=parse_qs(urlparse(path).query);value=out('log','-1','--format=%H',query['sha'][0],'--',query['path'][0]);return [{'sha':value}] if value else []
   return super().request(path,method,payload)
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo');end='2026-10-15T23:00:00Z'
 for n in (20,21,22):
  item=Source(policy,receipt);item.run['id']=n;a.append_delivery(item,state,policy,n,trust,store,approval,stream)
 frozen=out('rev-parse',ref);frozen_tree=out('rev-parse',ref+'^{tree}')
 reporter=git('commit-tree',frozen_tree,'-p',frozen,input=b'reporter before checkpoint').stdout.decode().strip();git('update-ref',ref,reporter,frozen)
 older=a.projection_window(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,start=0,limit=1,frozen_head=frozen)
 assert older['frozen_head']==frozen and older['tree']==frozen_tree and older['observed_head']==reporter
 path='receipt-archive/projection/'+stream+'.json'
 first=ProjectionState();first.conflict=True;first.lost=True
 result=a.checkpoint_projection(first,policy,trust,store,approval,stream,interval_end=end,limit=1)
 assert result['next_segment']==1 and result['coverage_complete'] is False and first.patches==2
 first_head=out('rev-parse',ref);one=json.loads(git('show',ref+':'+path).stdout)
 assert one['previous_blob'] is None and one['window']['start']==0 and one['window']['references'][0]['run_id']==20
 # A separate API instance reconstructs progress only from protected state.
 result=a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=1)
 two=json.loads(git('show',ref+':'+path).stdout)
 assert result['next_segment']==2 and two['previous_blob']==out('rev-parse',first_head+':'+path)
 assert two['window']['references'][0]['run_id']==21 and two['frozen_head']==one['frozen_head']
 assert json.loads(git('cat-file','blob',two['previous_blob']).stdout)==one
 # Current revocation is rebound per window; retained facts are never pruned.
 current=json.loads(trust.read_bytes());current['profiles'][0]['status']='revoked';trust.write_text(json.dumps(current))
 third=a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=2)
 assert third['next_segment']==3 and third['frozen_complete'] and third['coverage_complete'] is False
 done=out('rev-parse',ref)
 assert a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=1)['status']=='already-checkpointed'
 assert out('rev-parse',ref)==done
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 assert git('show',ref+':reports/'+'1'*64+'.json').stdout==b'concurrent encrypted checkpoint'
 def reject(fn,reason):
  before=out('rev-parse',ref)
  try:fn()
  except ValueError as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('accepted '+reason)
  assert out('rev-parse',ref)==before
 reject(lambda:a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end='2026-10-15T22:00:00Z',limit=1),'binding')
 reject(lambda:a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=129),'bounds')
 class NoOrigin(ProjectionState):
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if '/rulesets/1' in path:value=copy.deepcopy(value);value['bypass_actors']=[]
   return value
 reject(lambda:a.checkpoint_projection(NoOrigin(),policy,trust,store,approval,stream,interval_end=end,limit=1),'protection policy changed')
 # Same bytes copied into a foreign publication do not establish publication origin.
 bad=json.loads(git('show',ref+':'+path).stdout);bad['publication_parent']='f'*40
 raw=a.canonical(bad);blob=git('hash-object','-w','--stdin',input=raw).stdout.decode().strip();newtree=ProjectionState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':path,'type':'blob','mode':'100644','sha':blob}]})['sha'];badhead=git('commit-tree',newtree,'-p',done,input=b'bad publication').stdout.decode().strip();git('update-ref',ref,badhead,done)
 reject(lambda:a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=1),'publication parent')
 git('update-ref',ref,done,badhead)
 # Tamper lineage and actual checkpoint-only delta independently of parent checks.
 def bad_publication(change,extra=False):
  previous=out('rev-parse',ref);value=json.loads(git('show',ref+':'+path).stdout);value['publication_parent']=previous;change(value)
  data=a.canonical(value);sha=git('hash-object','-w','--stdin',input=data).stdout.decode().strip();entries=[{'path':path,'type':'blob','mode':'100644','sha':sha}]
  if extra:
   other=git('hash-object','-w','--stdin',input=b'changed unrelated README').stdout.decode().strip();entries.append({'path':'README.md','type':'blob','mode':'100644','sha':other})
  newtree=ProjectionState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':entries})['sha'];new=git('commit-tree',newtree,'-p',previous,input=b'bad checkpoint fixture').stdout.decode().strip();git('update-ref',ref,new,previous)
  return new
 badhead=bad_publication(lambda value:value.update(previous_blob='0'*40))
 reject(lambda:a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=1),'previous blob')
 git('update-ref',ref,done,badhead)
 badhead=bad_publication(lambda value:None,extra=True)
 reject(lambda:a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=1),'checkpoint-only')
 git('update-ref',ref,done,badhead)
 # Even reviewed bootstrap copying cannot import an existing progress capsule.
 saved=approval.read_bytes();changed=json.loads(saved);changed['bootstrap_sha']=done;changed['bootstrap_tree']=out('rev-parse',done+'^{tree}');approval.write_text(json.dumps(changed))
 reject(lambda:a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=1),'pre-bootstrap')
 approval.write_bytes(saved)
 # Three real CAS conflicts terminate without publishing any checkpoint.
 git('update-ref',ref,reporter,done);exhausted=ProjectionState();exhausted.always_conflict=True
 try:a.checkpoint_projection(exhausted,policy,trust,store,approval,stream,interval_end=end,limit=1)
 except ValueError as error:assert 'three CAS' in str(error)
 else:raise AssertionError('unbounded retry accepted')
 assert exhausted.patches==3 and git('cat-file','-e',ref+':'+path,check=False).returncode!=0
 git('update-ref',ref,reporter,out('rev-parse',ref));lost=ProjectionState();lost.lost=True;lost.fail_after_ack=True
 try:a.checkpoint_projection(lost,policy,trust,store,approval,stream,interval_end=end,limit=1)
 except ValueError as error:assert 'acknowledgement uncertain' in str(error)
 else:raise AssertionError('unreadable acknowledgement counted as success')
 retained=json.loads(git('show',ref+':'+path).stdout);assert retained['next_segment']==1
 assert a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=1)['next_segment']==2
 try:a.checkpoint_projection(ProjectionState(),policy,trust,store,approval,stream,interval_end=end,limit=1,window={'authenticated':True})
 except TypeError:pass
 else:raise AssertionError('caller cursor granted origin')
 assert not list(root.glob('*.sqlite'))
 print('20 protected projection checkpoint/CAS/lostack/history/origin/preservation cases passed')
'''
exec(compile(fixture+cases,'real-git-projection-checkpoint-fixture','exec'))
PY
