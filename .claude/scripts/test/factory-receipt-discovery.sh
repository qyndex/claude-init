#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: protected bounded checkpoint, real Git CAS and restart progress."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 s=importlib.util.spec_from_file_location('discovery',scripts/'factory-receipt-discovery.py')
 # The first regression demands persisted progress, not merely a cursor-shaped return.
 if s.loader is None or not pathlib.Path(s.origin).exists():raise AssertionError('no protected restartable discovery checkpoint exists')
 discovery=importlib.util.module_from_spec(s);s.loader.exec_module(discovery)
 class Runs(Source):
  calls=[]
  def request(self,path,**kwargs):
   if '/actions/workflows/' in path:
    self.calls.append(path);page=int(path.split('page=')[-1]);run=copy.deepcopy(self.run);run['id']=page+30
    return {'workflow_runs':[run], 'total_count':10000}
   return super().request(path,**kwargs)
 runs=Runs(policy,receipt);stream=a.archive_stream('org/repo');state.conflict=True;state.lost=True
 result=discovery.advance(runs,state,policy,approval,stream,page_size=1,tree_pages=1)
 assert result['status']=='checkpointed' and state.patches==2 and result['complete'] is False
 path='receipt-archive/progress/'+stream+'.json';first=json.loads(git('show',ref+':'+path).stdout)
 assert first['pagination']['next_page']==2 and first['scan']['complete'] is False and first['watch']=={'segments':1,'count':1}
 assert first['scan']['tree']==first['anchor']['tree'] and first['anchor']['head']==out('rev-parse',ref+'^')
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope', (oldpath,git('show',ref+':'+oldpath).stdout)
 second=discovery.advance(Runs(policy,receipt),State(),policy,approval,stream,page_size=1,tree_pages=1)
 saved=json.loads(git('show',ref+':'+path).stdout)
 assert saved['scan']['complete'] is True and saved['pagination']['next_page']==3 and saved['watch']=={'segments':2,'count':2}
 assert saved['coverage_complete'] is False and saved['scan']['head']==first['scan']['head']
 assert all(row['classification']=='pending' for n in range(saved['watch']['segments']) for row in json.loads(git('show',ref+':'+a.state_paths.pending_segment_path(stream,n)).stdout)['rows'])
 before=out('rev-parse',ref)
 class BadSource(Runs):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/actions/workflows/' in path:value['workflow_runs'][0]['repository']['full_name']='foreign/repo'
   return value
 try:discovery.advance(BadSource(policy,receipt),State(),policy,approval,stream,page_size=1)
 except ValueError as e:assert 'run identity' in str(e)
 else:raise AssertionError('foreign run persisted')
 assert out('rev-parse',ref)==before
 class Drift(State):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/rulesets/1' in path:value=copy.deepcopy(value);value['bypass_actors']=[]
   return value
 try:discovery.advance(runs,Drift(),policy,approval,stream,page_size=1)
 except ValueError as e:assert 'policy changed' in str(e)
 else:raise AssertionError('untrusted checkpoint origin accepted')
 assert out('rev-parse',ref)==before
 # Caller-provided JSON is not an API: no checkpoint/cursor parameter may bypass protected reads.
 try:discovery.advance(runs,State(),policy,approval,stream,cursor=saved)
 except TypeError:pass
 else:raise AssertionError('arbitrary cursor became authoritative')
 class IdentityChange(Runs):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/actions/workflows/' in path:value['workflow_runs'][0].update(id=31,head_sha='e'*40)
   return value
 try:discovery.advance(IdentityChange(policy,receipt),State(),policy,approval,stream,page_size=1)
 except ValueError as e:assert 'immutable pending' in str(e)
 else:raise AssertionError('pending source identity changed')
 assert out('rev-parse',ref)==before
 conflict=State();conflict.always_conflict=True
 try:discovery.advance(runs,conflict,policy,approval,stream,page_size=1)
 except ValueError as e:assert 'three CAS' in str(e)
 else:raise AssertionError('CAS retry unbounded')
 assert conflict.patches==3
 progress=json.loads(git('show',ref+':'+path).stdout);assert progress==saved
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope', (oldpath,git('show',ref+':'+oldpath).stdout)
 # More than128 unresolved observations persist across fresh invocations in bounded segments.
 prior=out('rev-parse',ref);git('update-ref',ref,initial,prior)
 class Many(Runs):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/actions/workflows/' in path:
    page=int(path.split('page=')[-1]);template=value['workflow_runs'][0];value['workflow_runs']=[dict(template,id=1000*page+i) for i in range(100)]
   return value
 # The real origin validator reads latest path history; serve it from actual Git.
 from urllib.parse import urlparse,parse_qs
 class LargeState(State):
  def request(self,target,method='GET',payload=None):
   if method=='GET' and target.startswith('repos/org/repo/commits?'):
    query=parse_qs(urlparse(target).query)
    assert set(query)=={'sha','path','per_page'} and query['per_page']==['1']
    assert query['path']==['receipt-archive/origin/'+stream+'.json']
    return [{'sha':sha} for sha in out('log','--format=%H','-1',query['sha'][0],'--',query['path'][0]).splitlines()]
   return super().request(target,method,payload)
 # Each broad publication needs real checked origin progress before its next consumer.
 # Each fresh LargeState()/advance_origin call models a separate bounded invocation.
 # This fixture loop does not enlarge a production single-run shared budget.
 origin_windows=[]
 def checked_origin():
  for _ in range(32):
   result=a.advance_origin(LargeState(),approval)
   origin_windows.append(result)
   if result['frozen_complete']:return
  raise AssertionError('actual protected origin did not resume within fixture invocations')
 for _ in range(4):
  discovery.advance(Many(policy,receipt),LargeState(),policy,approval,stream,page_size=100)
  checked_origin()
 journal=json.loads(git('show',ref+':'+path).stdout);assert journal['watch']=={'segments':4,'count':400} and journal['pagination']['next_page']==5 and journal['coverage_complete'] is False
 identities=[]
 for number in range(4):
  segment=json.loads(git('show',ref+':'+a.state_paths.pending_segment_path(stream,number)).stdout);assert len(segment['rows'])==100;identities.extend(row['run_id'] for row in segment['rows'])
 assert len(set(identities))==400 and len(a.canonical(journal))<65536
 # Concurrent checkpoint writers coalesce identical pages without dropping older watch segments.
 def concurrent_page():
  discovery.advance(Many(policy,receipt),LargeState(),policy,approval,stream,page_size=100)
  checked_origin()
 outer=LargeState();outer.before_patch=concurrent_page
 discovery.advance(Many(policy,receipt),outer,policy,approval,stream,page_size=100)
 journal=json.loads(git('show',ref+':'+path).stdout);assert journal['watch']=={'segments':5,'count':500} and outer.patches==1
 assert origin_windows and origin_windows[-1]['frozen_complete']
 # Check every immutable publication against its real parent's scanner state.
 # A new commit alone is not evidence that the authenticated cursor advanced.
 origin_checks=[];origin_path='receipt-archive/origin/'+stream+'.json'
 fields=('frozen_head','next_sha','tree_cursor','checked_commits','complete')
 for result in origin_windows:
  current=json.loads(git('show',result['head']+':'+origin_path).stdout)
  assert out('show','-s','--format=%P',result['head'])==current['publication_parent']
  previous=git('show',current['publication_parent']+':'+origin_path,check=False)
  assert previous.returncode in (0,128)
  old={key:json.loads(previous.stdout)[key] for key in fields} if previous.returncode==0 else None
  new={key:current[key] for key in fields};assert old!=new,'origin scanner made no actual progress'
  assert current['complete']==result['frozen_complete'] and current['checked_commits']==result['checked_commits']
  origin_checks.append({'publication':result['head'],'before':hashlib.sha256(a.canonical(old)).hexdigest(),'after':hashlib.sha256(a.canonical(new)).hexdigest()})
 print('actual checked origin transitions='+json.dumps(origin_checks),flush=True)
 all_rows=[]
 for number in range(5):
  segment=json.loads(git('show',ref+':'+a.state_paths.pending_segment_path(stream,number)).stdout)
  assert len(segment['rows'])==100;all_rows.extend(row['run_id'] for row in segment['rows'])
 assert len(set(all_rows))==500 and set(identities)<=set(all_rows)
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 before=out('rev-parse',ref);preexisting=json.loads(approval.read_text());preexisting.update(bootstrap_sha=before,bootstrap_tree=out('rev-parse',ref+'^{tree}'));import_path=root/'import-approval.json';import_path.write_text(json.dumps(preexisting))
 try:discovery.advance(Many(policy,receipt),LargeState(),policy,import_path,stream,page_size=100)
 except ValueError as e:assert str(e)=='origin checkpoint pre-bootstrap requires explicit reviewed import'
 else:raise AssertionError('arbitrary existing checkpoint imported')
 assert out('rev-parse',ref)==before
 print('11 bounded protected discovery/CAS/restart/origin scenarios passed; complete coverage remains false; actual origin windows='+str(len(origin_windows)))
'''
exec(compile(fixture+cases,'real-git-discovery-fixture','exec'))
PY
