#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: capped created partitions and atomic protected watch observations."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 from urllib.parse import parse_qs,urlsplit
 import datetime
 spec=importlib.util.spec_from_file_location('backfill',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 start='2026-10-15T00:00:00Z';end='2026-10-15T00:00:03Z';stream=a.archive_stream('org/repo')
 class Runs(Source):
  queries=[];late=False;attempt=1
  def request(self,path,**kwargs):
   if '/actions/workflows/' not in path:return super().request(path,**kwargs)
   q=parse_qs(urlsplit(path).query);assert 'created' in q,'unpartitioned filtered query'
   assert q.get('branch')==['main'],'source query is not bound to protected default branch'
   lo,hi=q['created'][0].split('..');page=int(q['page'][0]);size=int(q['per_page'][0]);rows=[]
   for number in range(1100):
    created='2026-10-15T00:00:0'+str(number%4)+'Z'
    if lo<=created<=hi:
     row=copy.deepcopy(self.run);row.update(id=number+100,run_attempt=self.attempt,created_at=created);rows.append(row)
   if self.late:
    row=copy.deepcopy(self.run);row.update(id=9999,created_at=start)
    if lo<=start<=hi:rows.append(row)
   rows.sort(key=lambda r:r['id'],reverse=True);self.queries.append((lo,hi,page,len(rows)))
   return {'total_count':len(rows),'workflow_runs':rows[(page-1)*size:page*size]}
 runs=Runs(policy,receipt);state=State();state.conflict=True;state.lost=True
 first=d.backfill(runs,state,policy,approval,stream,interval_end=end,page_size=2)
 assert first['complete'] is False and state.patches==2
 assert runs.queries[0][3]>=1000
 # Restart reads the next partition/page only from durable Git state.
 # One real fresh Python process resumes protected Git state without parent memory.
 import textwrap,ast
 transport='class State:\n'+textwrap.indent(textwrap.dedent(fixture.split(' class State:',1)[1].split(' source=Source',1)[0]).lstrip('\n'),' ')
 listing='class Runs'+textwrap.dedent(cases.split(' class Runs',1)[1].split(' runs=Runs',1)[0])
 config=root/'backfill-config.json';config.write_text(json.dumps({'root':str(root),'work':str(work),'ref':ref,'branch':branch,'policies':policies,'policy':policy,'run':runs.run,'approval':str(approval),'scripts':str(scripts),'end':end,'start':start,'stream':stream}))
 runner=root/'backfill-runner.py'
 header='import pathlib,json,subprocess,os,base64,sys,importlib.util,copy\nfrom urllib.parse import parse_qs,urlsplit\nc=json.loads(pathlib.Path(sys.argv[1]).read_text());root=pathlib.Path(c["root"]);work=pathlib.Path(c["work"]);ref=c["ref"];branch=c["branch"];start=c["start"];policies={int(k):v for k,v in c["policies"].items()}\ndef git(*args,input=None,env=None,check=True):return subprocess.run(["git","-C",str(work),*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=check)\ndef out(*args):return git(*args).stdout.decode().strip()\nclass Source:\n def __init__(self,policy,receipt):self.repo=policy["repository"];self.run=c["run"]\n def request(self,path,**kwargs):raise AssertionError(path)\n'
 code=header+transport+'\n'+listing+'\ns=importlib.util.spec_from_file_location("discovery",pathlib.Path(c["scripts"])/"factory-receipt-discovery.py");d=importlib.util.module_from_spec(s);s.loader.exec_module(d)\nprint(json.dumps(d.backfill(Runs(c["policy"],None),State(),c["policy"],c["approval"],c["stream"],interval_end=c["end"],page_size=2)))\n'
 ast.parse(code);runner.write_text(code)
 child=subprocess.run([sys.executable,str(runner),str(config)],capture_output=True,text=True,timeout=60);assert child.returncode==0,child.stderr
 second=json.loads(child.stdout)
 third=d.backfill(Runs(policy,receipt),State(),policy,approval,stream,interval_end=end,page_size=2)
 manifest_path='receipt-archive/backfill/'+stream+'.json'
 saved=json.loads(git('show',ref+':'+manifest_path).stdout)
 assert saved['interval_start']==start and saved['interval_end']==end and len(saved['stack'])<=64
 progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
 assert progress['watch']['count']>=4 and progress['coverage_complete'] is False
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 prior=out('rev-parse',ref)
 try:d.backfill(Runs(policy,receipt),State(),policy,approval,stream,interval_end='2026-10-15T00:00:04Z',page_size=2)
 except ValueError as error:assert 'binding' in str(error)
 else:raise AssertionError('protected interval silently reset')
 assert out('rev-parse',ref)==prior
 # Full partition state machine with1100runs; origin/CAS integration above is realGit.
 anchor=a.verify_bootstrap(State(),approval);objects={};known=set();rounds=[]
 def blob(tree,name):return None if tree==anchor['bootstrap_tree'] else objects.get(name)
 source=Runs(policy,receipt)
 for call in range(300):
  rows,changes,summary=d.backfill_page(source,anchor,policy,stream,end,100,blob)
  objects.update(changes);known.update((row['id'],row['run_attempt']) for row in rows)
  if summary['rounds_observed']>=1:break
 assert len(known)==1100 and summary['coverage_complete'] is False and summary['last_round_gaps']==0
 # Late old-created IDs and reruns must be picked up in subsequent epochs.
 source.late=True;source.attempt=2
 for call in range(300):
  rows,changes,summary=d.backfill_page(source,anchor,policy,stream,end,100,blob);objects.update(changes);known.update((row['id'],row['run_attempt']) for row in rows)
  if summary['rounds_observed']>=2:break
 assert (9999,1) in known and (100,1) in known and (100,2) in known
 # Saturated one-second partitions remain explicit gaps and are revisited.
 class Dense(Runs):
  def request(self,path,**kwargs):return {'total_count':1000,'workflow_runs':[]}
 dense_objects={}
 def dense_blob(tree,name):return None if tree==anchor['bootstrap_tree'] else dense_objects.get(name)
 for count in range(2):
  rows,changes,dense=d.backfill_page(Dense(policy,receipt),anchor,policy,stream,start,10,dense_blob);dense_objects.update(changes)
  assert dense['rounds_observed']==count+1 and dense['last_round_gaps']==1 and dense['partition_phase']=='gap'
 # Count/page/unique/confirmation inconsistencies never become observed coverage.
 class Small(Runs):
  kind='valid';calls=0
  def request(self,path,**kwargs):
   self.calls+=1;query=parse_qs(urlsplit(path).query);page=int(query['page'][0]);size=int(query['per_page'][0])
   if self.kind=='unavailable':raise RuntimeError('DO_NOT_PERSIST_TRANSPORT_SENTINEL')
   if self.kind=='denied':raise ValueError('GitHub API request failed: fixture')
   if self.kind=='budget':raise ValueError('discovery observation budget exceeded; explicit coverage gap')
   rows=[]
   for number in (1,2):
    run=copy.deepcopy(self.run);run.update(id=number,created_at=start);rows.append(run)
   total=2
   if self.kind=='count-drift' and self.calls>1:total=3
   if self.kind=='duplicate':rows=[rows[0],rows[0]]
   if self.kind=='repeat-page' and page>1:page=1
   selected=rows[(page-1)*size:page*size]
   if self.kind=='short':selected=[]
   if self.kind=='foreign':selected[0]['repository']['id']=999
   if self.kind=='outside':selected[0]['created_at']='2026-10-14T00:00:00Z'
   if self.kind=='boolean':total=True
   if self.kind=='confirm-change':
    total=1;selected=[rows[0]]
    if self.calls>1:selected[0]['id']=999
   return {'total_count':total,'workflow_runs':selected}
 for kind,size in [('count-drift',1),('duplicate',2),('repeat-page',1),('short',1),('confirm-change',1),('unavailable',1),('denied',1)]:
  source=Small(policy,receipt);source.kind=kind;memory={}
  def read(tree,name):return None if tree==anchor['bootstrap_tree'] else memory.get(name)
  for count in range(4):
   rows,changes,summary=d.backfill_page(source,anchor,policy,stream,end,size,read);memory.update(changes)
   if summary['rounds_observed']:break
  assert summary['last_round_gaps']>0 and summary['coverage_complete'] is False,kind
  assert all(b'DO_NOT_PERSIST_TRANSPORT_SENTINEL' not in value for value in memory.values())
 for kind in ('foreign','outside','boolean','budget'):
  source=Small(policy,receipt);source.kind=kind
  try:d.backfill_page(source,anchor,policy,stream,end,1,lambda tree,name:None)
  except ValueError:pass
  else:raise AssertionError('invalid source accepted '+kind)
 # Corrupt retained page facts cannot be promoted merely by preserving hashes.
 base_source=Small(policy,receipt);rows,first_changes,summary=d.backfill_page(base_source,anchor,policy,stream,end,1,lambda tree,name:None)
 part=next(name for name in first_changes if name!=manifest_path)
 for corrupt in ('digest','unknown'):
  memory=dict(first_changes);node=json.loads(memory[part])
  if corrupt=='digest':node['facts'][0]['rows_sha256']='0'*64
  else:node['unknown']=True
  memory[part]=a.canonical(node)
  try:d.backfill_page(base_source,anchor,policy,stream,end,1,lambda tree,name:None if tree==anchor['bootstrap_tree'] else memory.get(name))
  except ValueError:pass
  else:raise AssertionError('tampered retained page accepted '+corrupt)
 # Actual protected pending lookup deduplicates the same boundary ID across partitions.
 stable=out('rev-parse',ref);git('update-ref',ref,initial,stable)
 class Boundary(Runs):
  def request(self,path,**kwargs):
   query=parse_qs(urlsplit(path).query);lo,hi=query['created'][0].split('..');run=copy.deepcopy(self.run);run.update(id=1,created_at=start)
   return {'total_count':1000 if lo<=start<=hi else 0,'workflow_runs':[run] if lo<=start<=hi else []}
 for count in range(3):d.backfill(Boundary(policy,receipt),State(),policy,approval,stream,interval_end=end,page_size=1)
 watched=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
 assert watched['watch']['count']==1 and watched['coverage_complete'] is False
 rows=json.loads(git('show',ref+':'+a.state_paths.pending_segment_path(stream,0)).stdout)['rows']
 assert all(row['classification']=='pending' for row in rows)
 assert not out('ls-tree','-r',ref,'--','receipt-archive/objects')
 git('update-ref',ref,stable,out('rev-parse',ref))
 # Copied reviewed-origin state never grants progress through a JSON hash.
 try:d.backfill_page(Runs(policy,receipt),anchor,policy,stream,end,100,lambda tree,name:b'{}')
 except ValueError as error:assert 'pre-bootstrap' in str(error)
 else:raise AssertionError('bootstrap copied manifest accepted')
 print('backfill: PASS; capped1100partitioned rows, realGit atomicCAS/fresh-process restart, dense gaps/count-identity-access negatives, dedup boundaries, epochs/late/reruns, fixed origin/end; coverage remains false')
'''
exec(compile(fixture+cases,'backfill-real-git-fixture','exec'))
PY
