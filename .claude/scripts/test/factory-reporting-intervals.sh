#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: two additive actual Git intervals and late retained snapshot revision."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
prefix=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' first=a.checkpoint_projection',1)[0]
prefix=prefix.replace('for n in (1,2)}','for n in (1,2,3)}')
cases=r'''
 class TimedState(PipelineState):
  def request(self,target,method='GET',payload=None):
   if method=='GET' and '/pulls/' in target:
    number=int(target.rsplit('/',1)[1]);assert number in (7,8,9)
    return {'number':number,'merged':True,'merge_commit_sha':{7:'b',8:'c',9:'d'}[number]*40,'merged_at':'2026-10-16T00:30:00Z' if number==9 else '2026-10-15T01:00:00.123456Z','base':{'repo':{'id':101,'full_name':'org/repo'}}}
   return super().request(target,method,payload)
 ends=('2026-10-15T23:00:00Z','2026-10-16T01:00:00Z');saved=[]
 for n,end in enumerate(ends):
  result=a.checkpoint_projection(TimedState(),policy,trust,store,approval,stream,interval_end=end,limit=128,interval_scoped=True)
  assert result['frozen_complete'] and result['next_segment']==2
  history=result['head'];name=out('diff-tree','--no-commit-id','--name-only','-r',history);raw=git('show',history+':'+name).stdout
  staged=a.stage_projection(TimedState(),policy,trust,store,approval,stream,interval_end=end,history_head=history,interval_scoped=True)
  database=root/('day'+str(n)+'.sqlite');projected=a.reconstruct_interval(TimedState(),policy,database,trust,store,approval,stream,interval_end=end,history_head=history,campaign=staged['campaign'],interval_scoped=True)
  assert projected['projection_complete'] and projected['facts_count']==2 and projected['coverage_complete'] is False
  saved.append((name,raw,history,staged['campaign']))
 assert saved[0][0]!=saved[1][0] and git('show',ref+':'+saved[0][0]).stdout==saved[0][1]
 # Actual later append cannot be trapped behind an earlier complete same-cutoff snapshot.
 rc=copy.deepcopy(receipt);rc.update(spec='003',task_ids=['T-3'],pull_request=9,merge_sha='d'*40)
 third=Source(policy,rc);third.run['id']=22;third.pr.update(number=9,merge_commit_sha=rc['merge_sha']);third.sources[policy['specs']['003']['path']]=b'approved spec'
 assert a.append_delivery(third,TimedState(),policy,22,trust,store,approval,stream)['status']=='appended'
 revised=a.checkpoint_projection(TimedState(),policy,trust,store,approval,stream,interval_end=ends[0],limit=128,interval_scoped=True)
 assert revised['frozen_complete'] and revised['next_segment']==3,'late append reused stale complete projection namespace'
 assert git('show',ref+':'+saved[0][0]).stdout==saved[0][1],'prior interval snapshot overwritten'
 stage=a.stage_projection(TimedState(),policy,trust,store,approval,stream,interval_end=ends[0],history_head=revised['head'],interval_scoped=True)
 result=a.reconstruct_interval(TimedState(),policy,root/'revised.sqlite',trust,store,approval,stream,interval_end=ends[0],history_head=revised['head'],campaign=stage['campaign'],interval_scoped=True)
 assert result['projection_complete'] and result['facts_count']==3 and result['interval_facts_count']==2
 # The original selected historical snapshot remains independently reconstructable.
 old=a.reconstruct_interval(TimedState(),policy,root/'historical.sqlite',trust,store,approval,stream,interval_end=ends[0],history_head=saved[0][2],campaign=saved[0][3],interval_scoped=True)
 assert old['projection_complete'] and old['facts_count']==2
 active=trust.read_bytes();revoked=json.loads(active);revoked['profiles'][0]['status']='revoked';trust.write_text(json.dumps(revoked))
 withdrawn=a.reconstruct_interval(TimedState(),policy,root/'withdrawn.sqlite',trust,store,approval,stream,interval_end=ends[0],history_head=saved[0][2],campaign=saved[0][3],interval_scoped=True)
 assert withdrawn['projection_complete']
 with sqlite3.connect(root/'withdrawn.sqlite') as db:assert db.execute('SELECT status FROM delivery_trust').fetchall()==[('withdrawn',),('withdrawn',)]
 trust.write_bytes(active)
 before=out('rev-parse',ref)
 try:a.checkpoint_projection(TimedState(),policy,trust,store,approval,stream,interval_end=ends[0],interval_scoped=1)
 except ValueError as error:assert 'scope' in str(error)
 else:raise AssertionError('integer accepted as interval scope flag')
 assert out('rev-parse',ref)==before
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('two additive real-Git interval checkpoints/stages/readers and same-cutoff late retained revision passed; no coverage/task credit')
'''
exec(compile(fixture+prefix+cases,'actual-additive-intervals','exec'))
PY
