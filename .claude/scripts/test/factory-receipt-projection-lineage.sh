#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: actual protected Git publication lineage, never blob-only trust."""
from pathlib import Path
base=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
setup=Path('.claude/scripts/test/factory-receipt-projection-checkpoint.sh').read_text().split("cases=r'''\n",1)[1].split(' # Current revocation',1)[0]
cases=r'''
 latest=out('rev-parse',ref)
 class HistoryState(ProjectionState):
  def request(self,path,method='GET',payload=None):
   assert method=='GET','lineage reader attempted write'
   if '/commits?' in path:
    query=parse_qs(urlparse(path).query);size=int(query['per_page'][0]);page=int(query.get('page',['1'])[0]);rows=out('log','--format=%H',query['sha'][0],'--',query['path'][0]).splitlines()
    return [{'sha':sha} for sha in rows[(page-1)*size:page*size]]
   return super().request(path,method,payload)
 onepage=a.projection_lineage(HistoryState(),policy,trust,store,approval,stream,interval_end=end,limit=1)
 assert len(onepage['windows'])==1 and onepage['windows'][0]['checkpoint']['window']['start']==1
 assert onepage['coverage_complete'] is False and onepage['partial'] and onepage['suffix_pending']
 second=a.projection_lineage(HistoryState(),policy,trust,store,approval,stream,interval_end=end,page=2,limit=1,history_head=onepage['history_head'])
 assert second['windows'][0]['checkpoint']['window']['start']==0 and second['reaches_start']
 assert onepage['windows'][0]['checkpoint']['previous_blob']==second['windows'][0]['blob_sha']
 assert onepage['observed_head']==second['observed_head']==latest
 def reject(api=HistoryState(),reason='',**kwargs):
  try:a.projection_lineage(api,policy,trust,store,approval,stream,interval_end=end,**kwargs)
  except (ValueError,TypeError) as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('accepted '+reason)
 reject(reason='bounds',limit=33)
 reject(reason='bounds',page=True)
 reject(reason='unexpected keyword',cursor={'authenticated':True})
 class Foreign(HistoryState):repo='foreign/repo'
 reject(Foreign(),'repository')
 class ForgedHistory(HistoryState):
  def request(self,path,method='GET',payload=None):
   if '/commits?' in path:return [{'sha':frozen}]
   return super().request(path,method,payload)
 reject(ForgedHistory(),'publication')
 class Duplicate(HistoryState):
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if '/commits?' in path:return [value[0],value[0]]
   return value
 reject(Duplicate(),'duplicate',limit=2)
 class Reordered(HistoryState):
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if '/commits?' in path:return list(reversed(value))
   return value
 reject(Reordered(),'latest publication',limit=2)
 empty=a.projection_lineage(HistoryState(),policy,trust,store,approval,stream,interval_end=end,page=99,limit=1)
 assert empty['partial'] and not empty['reaches_start'] and not empty['coverage_complete'] and empty['suffix_pending']
 # New reporter commits cannot shift a requested immutable pagination view.
 reporter=git('commit-tree',out('rev-parse',latest+'^{tree}'),'-p',latest,input=b'concurrent reporter').stdout.decode().strip();git('update-ref',ref,reporter,latest)
 anchored=a.projection_lineage(HistoryState(),policy,trust,store,approval,stream,interval_end=end,page=2,limit=1,history_head=latest)
 assert anchored['history_head']==latest and anchored['observed_head']==reporter and anchored['windows']==second['windows']
 git('update-ref',ref,latest,reporter)
 # Actual checkpoint-only commit with forged parent binding must still reject.
 bad=json.loads(git('show',ref+':'+path).stdout);bad['publication_parent']='f'*40
 raw=a.canonical(bad);blob=git('hash-object','-w','--stdin',input=raw).stdout.decode().strip()
 tree=ProjectionState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':path,'type':'blob','mode':'100644','sha':blob}]})['sha']
 tampered=git('commit-tree',tree,'-p',latest,input=b'forged checkpoint parent').stdout.decode().strip();git('update-ref',ref,tampered,latest)
 reject(reason='publication parent')
 git('update-ref',ref,latest,tampered)
 # Independent protected origin is mandatory even for correct checkpoint bytes.
 class NoOrigin(HistoryState):
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if '/rulesets/1' in path:value=copy.deepcopy(value);value['bypass_actors']=[]
   return value
 reject(NoOrigin(),'protection policy changed')
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('16 protected projection lineage cases passed; partial windows never grant coverage')
'''
exec(compile(base+setup+cases,'real-git-projection-lineage','exec'))
PY
