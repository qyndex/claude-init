#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: protected derived stages, real Git CAS and global conflict guards."""
from pathlib import Path
base=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
setup=Path('.claude/scripts/test/factory-receipt-projection-checkpoint.sh').read_text().split("cases=r'''\n",1)[1].split(' # Current revocation',1)[0]
cases=r'''
 class StageState(ProjectionState):
  def request(self,path,method='GET',payload=None):
   if method=='GET' and '/commits?' in path:
    query=parse_qs(urlparse(path).query);size=int(query['per_page'][0]);page=int(query.get('page',['1'])[0]);rows=out('log','--format=%H',query['sha'][0],'--',query['path'][0]).splitlines();return [{'sha':sha} for sha in rows[(page-1)*size:page*size]]
   if method=='GET' and path=='repos/org/repo/pulls/7':return {'number':7,'merged':True,'merge_commit_sha':'b'*40,'merged_at':'2026-10-15T01:00:00.123456Z','base':{'repo':{'id':101,'full_name':'org/repo'}}}
   return super().request(path,method,payload)
 before=out('rev-parse',ref);initial_feedback=git('show',ref+':'+oldpath).stdout
 writer=StageState();writer.conflict=True;writer.lost=True
 result=a.stage_projection(writer,policy,trust,store,approval,stream,interval_end=end,history_head=before)
 assert result['status']=='staged' and result['coverage_complete'] is False and result['facts_count']==1 and writer.patches==2 and result['uncertain_write_reconciled']
 assert git('show',ref+':'+oldpath).stdout==initial_feedback
 assert git('show',ref+':reports/'+'1'*64+'.json').stdout==b'concurrent encrypted checkpoint'
 after=out('rev-parse',ref)
 repeated=a.stage_projection(StageState(),policy,trust,store,approval,stream,interval_end=end,history_head=before)
 assert repeated['status']=='already-staged' and out('rev-parse',ref)==after
 def rejects(fn,reason):
  previous=out('rev-parse',ref)
  try:fn()
  except (ValueError,TypeError) as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('invalid derived stage accepted')
  assert out('rev-parse',ref)==previous
 # Same task in a different retained execution, located in another checkpoint.
 rejects(lambda:a.stage_projection(StageState(),policy,trust,store,approval,stream,interval_end=end,history_head=before,page=2),'conflicting task')
 rejects(lambda:a.stage_projection(StageState(),policy,trust,store,approval,stream,interval_end=end,history_head=before,limit=True),'bounds')
 rejects(lambda:a.stage_projection(StageState(),policy,trust,store,approval,stream,interval_end=end,facts=[{'authenticated':True}]),'unexpected keyword')
 # An unavailable merge time never advances or removes an existing historical fact.
 class MissingTime(StageState):
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   return dict(value,merged_at=None) if path=='repos/org/repo/pulls/7' else value
 gap=a.stage_projection(MissingTime(),policy,trust,store,approval,stream,interval_end=end,history_head=before)
 assert gap['status']=='gap' and not gap['coverage_complete'] and out('rev-parse',ref)==after
 class ChangedTime(StageState):
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   return dict(value,merged_at='2026-10-15T01:00:00.123455Z') if path=='repos/org/repo/pulls/7' else value
 rejects(lambda:a.stage_projection(ChangedTime(),policy,trust,store,approval,stream,interval_end=end,history_head=before),'conflicting window')
 # JSON booleans/floats must not compare equal to strict integer schema fields.
 campaign=result['campaign'];key=a.digest(a.canonical(['execution',[21,1]]));typed_index='receipt-archive/stages/'+campaign+'/'+key[:2]+'/'+key+'.json'
 for typed_path,kind,typed in ((path,kind,typed) for path,kind in ((result['stage_path'],'window'),(typed_index,'execution')) for typed in (True,1.0)):
  stage=json.loads(git('show',ref+':'+typed_path).stdout);stage['schema_version']=typed
  blob=git('hash-object','-w','--stdin',input=a.canonical(stage)).stdout.decode().strip()
  tree=StageState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':typed_path,'type':'blob','mode':'100644','sha':blob}]})['sha']
  bad=git('commit-tree',tree,'-p',after,input=b'wrong typed stage schema').stdout.decode().strip();git('update-ref',ref,bad,after)
  rejects(lambda:a.stage_projection(StageState(),policy,trust,store,approval,stream,interval_end=end,history_head=before),'conflicting '+kind)
  git('update-ref',ref,after,bad)
 # Stored index JSON is not authority: trusted origin does not excuse conflicts.
 campaign=result['campaign'];key=a.digest(a.canonical(['execution',[21,1]]));index_path='receipt-archive/stages/'+campaign+'/'+key[:2]+'/'+key+'.json'
 index=json.loads(git('show',ref+':'+index_path).stdout);index['attempt']=999
 blob=git('hash-object','-w','--stdin',input=a.canonical(index)).stdout.decode().strip()
 tree=StageState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':index_path,'type':'blob','mode':'100644','sha':blob}]})['sha']
 forged=git('commit-tree',tree,'-p',after,input=b'malformed protected derived index').stdout.decode().strip();git('update-ref',ref,forged,after)
 rejects(lambda:a.stage_projection(StageState(),policy,trust,store,approval,stream,interval_end=end,history_head=before),'conflicting execution')
 git('update-ref',ref,after,forged)
 for bad in ({'path':result['stage_path'],'type':'blob','mode':'120000','sha':'a'*40,'size':12},{'path':result['stage_path']+'.sql','type':'blob','mode':'100644','sha':'a'*40,'size':12}):
  try:a.state_paths.validate_entry(bad)
  except ValueError:pass
  else:raise AssertionError('executable or SQL stage path allowed')
 assert git('show',ref+':'+oldpath).stdout==initial_feedback
 class ProtectionDrift(StageState):
  changed=False
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if path=='repos/org/repo/pulls/7' and not self.changed:
    self.changed=True;policies[1]['updated_at']='2026-10-15T00:00:00Z'
   return value
 saved=copy.deepcopy(policies[1]);rejects(lambda:a.stage_projection(ProtectionDrift(),policy,trust,store,approval,stream,interval_end=end,history_head=before),'protection')
 policies[1]=saved
 class HeadDrift(StageState):
  changed=False
  def request(self,path,method='GET',payload=None):
   value=super().request(path,method,payload)
   if path=='repos/org/repo/pulls/7' and not self.changed:
    self.changed=True
    current=out('rev-parse',ref);self.reporter=git('commit-tree',out('rev-parse',ref+'^{tree}'),'-p',current,input=b'concurrent reporter during PR observation').stdout.decode().strip();git('update-ref',ref,self.reporter,current)
   return value
 head_change=HeadDrift()
 try:a.stage_projection(head_change,policy,trust,store,approval,stream,interval_end=end,history_head=before)
 except ValueError as error:assert 'origin changed' in str(error)
 else:raise AssertionError('mutable head was hidden by immutable cache')
 assert head_change.patches==0 and out('rev-parse',ref)==head_change.reporter
 assert git('show',ref+':'+oldpath).stdout==initial_feedback
 print('17 real Git protected stage/CAS/lostack/restart/global conflict/gap/namespace/mutable-origin cases passed; no task credit')
'''
exec(compile(base+setup+cases,'real-git-projection-stage','exec'))
PY
