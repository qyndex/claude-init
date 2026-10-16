#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: exact PR merge time derives only from protected retained delivery."""
from pathlib import Path
base=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo')
 a.append_delivery(Source(policy,receipt),state,policy,20,trust,store,approval,stream)
 before=out('rev-parse',ref);beforetree=out('rev-parse',ref+'^{tree}')
 pr={'number':7,'merged':True,'merge_commit_sha':'b'*40,'merged_at':'2026-10-15T12:00:00.123456+11:00','base':{'repo':{'id':101,'full_name':'org/repo'}}}
 class TimeState(State):
  unavailable=False
  def request(self,path,method='GET',payload=None):
   assert method=='GET' and payload is None,'merge-time boundary attempted write'
   if path=='repos/org/repo/pulls/7':
    if self.unavailable:raise RuntimeError('private transport sentinel')
    return copy.deepcopy(pr)
   return super().request(path,method,payload)
 result=a.retained_merge_time(TimeState(),policy,store,approval,stream,20,1)
 assert result['status']=='observed' and result['fact']['merged_at']=='2026-10-15T01:00:00.123456Z' and result['coverage_complete'] is False
 assert result['fact']['pr']==7 and result['fact']['merge_sha']=='b'*40 and result['fact']['repository_id']==101
 assert result['fact']['record_sha256']==a.retained_execution(State(),a.verify_bootstrap(State(),approval),store,stream,20,1)['record_sha256']
 original=copy.deepcopy(pr)
 def rejects(change):
  pr.clear();pr.update(copy.deepcopy(original));change(pr)
  try:a.retained_merge_time(TimeState(),policy,store,approval,stream,20,1)
  except ValueError:pass
  else:raise AssertionError('invalid PR/time accepted')
  assert out('rev-parse',ref)==before
 for field,value in [('number',True),('number',8),('merged',False),('merge_commit_sha','e'*40),('merged_at','2026-10-15T01:00:00.1234567Z'),('merged_at','2026-10-15T01:00:00+00:60'),('merged_at','2026-10-15T01:00:00'),('merged_at','9999-01-01T00:00:00Z')]:
  rejects(lambda value_pr,field=field,value=value:value_pr.update({field:value}))
 rejects(lambda value_pr:value_pr['base']['repo'].update(id=102))
 rejects(lambda value_pr:value_pr['base']['repo'].update(full_name='foreign/repo'))
 pr.clear();pr.update(original)
 for absent in (None,'missing'):
  if absent is None:pr['merged_at']=None
  else:pr.pop('merged_at',None)
  gap=a.retained_merge_time(TimeState(),policy,store,approval,stream,20,1)
  assert gap['status']=='gap' and gap['reason']=='merge-time-missing' and 'fact' not in gap
 pr.clear();pr.update(original)
 unavailable=TimeState();unavailable.unavailable=True
 gap=a.retained_merge_time(unavailable,policy,store,approval,stream,20,1)
 assert gap['status']=='gap' and gap['reason']=='merge-time-unavailable' and 'sentinel' not in json.dumps(gap)
 class AdapterUnavailable(TimeState):
  def request(self,path,method='GET',payload=None):
   if path=='repos/org/repo/pulls/7':raise ValueError('GitHub API request failed: repos/org/repo/pulls/7')
   return super().request(path,method,payload)
 assert a.retained_merge_time(AdapterUnavailable(),policy,store,approval,stream,20,1)['reason']=='merge-time-unavailable'
 class InvalidResponse(TimeState):
  def request(self,path,method='GET',payload=None):
   if path=='repos/org/repo/pulls/7':raise ValueError('malformed PR transport JSON')
   return super().request(path,method,payload)
 try:a.retained_merge_time(InvalidResponse(),policy,store,approval,stream,20,1)
 except ValueError as error:assert str(error)=='malformed PR transport JSON'
 else:raise AssertionError('malformed response counted as unavailability')
 pr['merged_at']='2026-10-15T01:00:00.123455Z'
 distinct=a.retained_merge_time(TimeState(),policy,store,approval,stream,20,1)
 assert distinct['fact']['merged_at']=='2026-10-15T01:00:00.123455Z' and distinct['fact']!=result['fact']
 pr.clear();pr.update(original)
 missing=a.retained_merge_time(TimeState(),policy,store,approval,stream,999,1)
 assert missing['status']=='gap' and missing['reason']=='retained-proof-missing'
 assert out('rev-parse',ref)==before and out('rev-parse',ref+'^{tree}')==beforetree
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('20 protected retained PR merge-time cases passed; no inferred dates or task credit')
'''
exec(compile(base+cases,'real-git-projection-time','exec'))
PY
