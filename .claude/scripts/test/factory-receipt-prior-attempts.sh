#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 -u - <<'PYTEST'
"""AC-7: first-seen reruns retrieve available exact prior-attempt metadata."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 spec=importlib.util.spec_from_file_location('prior_discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 policy['merge_enabled']=False
 doc=json.loads(trust.read_bytes());doc['profiles'][0]['policy_sha256']=r.coordinator.policy_hash(policy);trust.write_text(json.dumps(doc))
 class Attempts(Source):
  available=False;attempt_calls=0
  def get(self,target):
   if '/actions/runs/' in target:
    if '/attempts/' in target:
     self.attempt_calls+=1
     assert target in {'repos/org/repo/actions/runs/20/attempts/1','repos/org/repo/actions/runs/20/attempts/2'}
     if not self.available:raise RuntimeError('prior metadata temporarily unavailable')
     value=dict(self.run,run_attempt=int(target.rsplit('/',1)[1]),status='completed',conclusion='failure');value.update(getattr(self,'override',{}));return value
    return copy.deepcopy(self.run)
   return super().get(target)
  def request(self,target,**kwargs):
   if '/actions/workflows/' in target:return {'workflow_runs':[copy.deepcopy(self.run)]} if target.endswith('page=1') else {'workflow_runs':[]}
   return super().request(target,**kwargs)
 runs=Attempts(policy,receipt);runs.run.update(run_attempt=2,created_at='2026-10-15T00:00:00Z')
 stream=a.archive_stream('org/repo');store={'repository':'org/repo','visibility':'public'}
 d.advance(runs,State(),policy,approval,stream,page_size=1)
 def watched():
  progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
  return [row for number in range(progress['watch']['segments']) for row in json.loads(git('show',ref+':'+a.state_paths.pending_segment_path(stream,number)).stdout)['rows']]
 d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
 assert [(row['run_id'],row['attempt']) for row in watched()]==[(20,2)]
 runs.available=True
 for changed in ({'id':21},{'run_attempt':True},{'workflow_id':11},{'repository':{'id':102,'full_name':'org/repo'}},{'head_sha':'f'*40}):
  runs.override=changed;before=out('rev-parse',ref)
  try:d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
  except ValueError as error:assert 'identity' in str(error),str(error)
  else:raise AssertionError('foreign/malformed prior attempt accepted')
  assert out('rev-parse',ref)==before
 runs.override={}
 for _ in range(8):
  d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
  if any(row['attempt']==1 for row in watched()):break
 assert runs.attempt_calls>0,'available prior-attempt endpoint was never queried'
 assert {(row['run_id'],row['attempt']) for row in watched()}=={(20,1),(20,2)},'available prior attempt was not durably watched'
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'

 # A later first-seen third attempt resumes through newly retained predecessor
 # rows after actual CAS conflict/lost acknowledgement, without duplicate rows.
 git('update-ref',ref,initial,out('rev-parse',ref))
 runs.run['run_attempt']=3
 race=State();race.conflict=True;race.lost=True
 d.advance(runs,race,policy,approval,stream,page_size=1)
 import textwrap
 context={'root':str(root),'work':str(work),'ref':ref,'branch':branch,'policies':policies,'policy':policy,'trust':str(trust),'approval':str(approval),'stream':stream,'store':store}
 context_path=root/'prior-context.json';context_path.write_text(json.dumps(context))
 header=fixture.split('\nwith tempfile.TemporaryDirectory() as tmp:',1)[0]
 state_code='class State:'+textwrap.indent(textwrap.dedent(fixture.split(' class State:',1)[1].split('\n source=Source',1)[0]),' ')
 source_code='class Attempts(Source):'+textwrap.indent(textwrap.dedent(cases.split(' class Attempts(Source):',1)[1].split(' runs=Attempts',1)[0]),' ')
 setup='\ncontext=json.loads(pathlib.Path('+repr(str(context_path))+').read_text());globals().update(context);root=pathlib.Path(root);work=pathlib.Path(work);trust=pathlib.Path(trust);approval=pathlib.Path(approval);policies={int(k):v for k,v in policies.items()}\ndef git(*args,input=None,env=None,check=True):return subprocess.run(["git","-C",str(work),*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,check=check)\ndef out(*args):return git(*args).stdout.decode().strip()\n'
 load='\nspec=importlib.util.spec_from_file_location("prior_discovery",scripts/"factory-receipt-discovery.py");d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)\n'
 runner=root/'prior-reader.py';runner.write_text(header+setup+state_code+load+source_code+'\nruns=Attempts(policy,{});runs.run.update(run_attempt=3,created_at="2026-10-15T00:00:00Z");runs.available=True\nd.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)\n')
 for _ in range(4):
  child=subprocess.run([sys.executable,str(runner)],capture_output=True,text=True,timeout=90)
  assert child.returncode==0,child.stderr
 assert {(row['run_id'],row['attempt']) for row in watched()}=={(20,1),(20,2),(20,3)}
 assert len(watched())==3 and git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 # An occupied identity is checked against its retained watch, never a bare
 # existence flag that can suppress required predecessor retrieval.
 key=d.watch_identity('org/repo',stream,20,2);path=f'receipt-archive/pending/{stream}/identities/{key[:2]}/{key}.json'
 saved=out('rev-parse',ref);bad=json.loads(git('show',ref+':'+path).stdout);bad['schema_version']=True
 blob=git('hash-object','-w','--stdin',input=a.canonical(bad)).stdout.decode().strip()
 tree=State().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':[{'path':path,'mode':'100644','type':'blob','sha':blob}]})['sha']
 changed=git('commit-tree',tree,'-p',saved,input=b'malformed predecessor lookup fixture').stdout.decode().strip();git('update-ref',ref,changed,saved)
 rejected=False
 for _ in range(4):
  try:d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
  except ValueError as error:
   assert 'pending identity' in str(error) or 'prior attempt' in str(error),str(error);rejected=True;break
 assert rejected,'malformed occupied predecessor lookup suppressed validation'

 git('update-ref',ref,initial,out('rev-parse',ref));policy['merge_enabled']=True
 doc=json.loads(trust.read_bytes());doc['profiles'][0]['policy_sha256']=r.coordinator.policy_hash(policy);trust.write_text(json.dumps(doc))
 actual=copy.deepcopy(receipt);actual['policy_sha256']=r.coordinator.policy_hash(policy)
 issued=Source(policy,actual)
 class ColdMerged(Attempts):
  available=True
  def get(self,target):
   if '/attempts/' in target:
    self.attempt_calls+=1
    assert target=='repos/org/repo/actions/runs/20/attempts/1'
    return dict(issued.run,created_at='2026-10-15T00:00:00Z')
   return super().get(target)
  def request(self,target,**kwargs):
   if '/actions/workflows/' in target:return super().request(target,**kwargs)
   return issued.request(target,**kwargs)
 cold=ColdMerged(policy,actual);cold.run.update(run_attempt=2,created_at='2026-10-15T00:00:00Z',conclusion='failure')
 d.advance(cold,State(),policy,approval,stream,page_size=1)
 for _ in range(8):
  d.reconcile(cold,State(),policy,trust,store,approval,stream,review_rows=2)
  anchor=a.verify_bootstrap(State(),approval)
  retained=a.retained_execution(State(),anchor,store,stream,20,1)
  if retained is not None:break
 assert retained is not None and json.loads(retained['record']['proof']['provenance'])['receipt']['merged'] is True
 import sqlite3
 db=root/'cold-merged.sqlite';assert a.project_retained(State(),policy,db,trust,store,approval,stream)==1
 with sqlite3.connect(db) as sql:assert sql.execute('SELECT task FROM delivery_receipts').fetchall()==[('T-1',)]
 assert cold.attempt_calls>0 and git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual available prior-attempt resume/fresh-process descending chain/CAS/lostack/typed-identity and cold latest-failed earlier-merged retained/report proof passed')


'''
exec(compile(fixture+cases,'actual-prior-attempt-real-git','exec'))
PYTEST
