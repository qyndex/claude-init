#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: completed protected origin removes lifetime ancestor cliff."""
from pathlib import Path
origin=Path('.claude/scripts/test/factory-receipt-origin-windows.sh').read_text()
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
prefix=origin.split("cases=r'''\n",1)[1].split(' def rejects(fn,reason):',1)[0]
cases=r'''
 store={'repository':'org/repo','visibility':'public'};stream=a.archive_stream('org/repo');end='2026-10-15T23:00:00Z'
 source=Source(policy,receipt)
 result=a.append_delivery(source,OriginState(),policy,20,trust,store,approval,stream)
 assert result['status']=='appended'
 assert a.append_delivery(source,OriginState(),policy,20,trust,store,approval,stream)['status']=='already-appended'
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 # Every core consumer uses the same authenticated prefix, not a scanner-only API.
 import sqlite3
 db=root/'completed.sqlite';assert a.project_retained(OriginState(),policy,db,trust,store,approval,stream)==1
 active=trust.read_bytes();revoked=json.loads(active);revoked['profiles'][0]['status']='revoked';trust.write_text(json.dumps(revoked))
 assert a.project_retained(OriginState(),policy,db,trust,store,approval,stream)==1
 with sqlite3.connect(db) as sql:assert sql.execute('SELECT status FROM delivery_trust').fetchall()==[('withdrawn',)]
 trust.write_bytes(active)
 assert a.checkpoint_projection(OriginState(),policy,trust,store,approval,stream,interval_end=end,limit=1)['next_segment']==1
 spec=importlib.util.spec_from_file_location('discovery',scripts/'factory-receipt-discovery.py');discovery=importlib.util.module_from_spec(spec);spec.loader.exec_module(discovery)
 class Runs(Source):
  def request(self,target,**kwargs):
   if '/actions/workflows/' in target:return {'workflow_runs':[],'total_count':0}
   return super().request(target,**kwargs)
 assert discovery.advance(Runs(policy,receipt),OriginState(),policy,approval,stream)['status']=='checkpointed'
 # Fresh interpreter validates the shared entry again, never a caller cursor.
 runner.write_text(runner.read_text().replace('a.advance_origin(OriginState(),c["approval"],commit_budget=16,tree_pages=4)','a.verify_bootstrap(OriginState(),c["approval"])'))
 restarted=subprocess.run([sys.executable,str(runner),str(config)],capture_output=True,text=True,timeout=60)
 assert restarted.returncode==0,restarted.stderr
 assert json.loads(restarted.stdout)['head']==out('rev-parse',ref)
 stable=out('rev-parse',ref)
 def reject(call,reason):
  before=out('rev-parse',ref)
  try:call()
  except ValueError as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('untrusted completed origin accepted '+reason)
  assert out('rev-parse',ref)==before
 def publish(raw,extra=None):
  before=out('rev-parse',ref);blob=git('hash-object','-w','--stdin',input=raw).stdout.decode().strip()
  entries=[{'path':path,'type':'blob','mode':'100644','sha':blob}]+(extra or [])
  newtree=OriginState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':entries})['sha']
  commit=git('commit-tree',newtree,'-p',before,input=b'negative origin fixture').stdout.decode().strip();git('update-ref',ref,commit,before);return commit
 def restore():git('update-ref',ref,stable,out('rev-parse',ref))
 # Copying an old genuine capsule cannot forge the actual publication parent.
 # Remove/re-add changes actual path history; a byte-identical no-op commit
 # legitimately leaves the original genuine publication as the latest path change.
 index=root/'remove-origin-index';env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',out('rev-parse',ref+'^{tree}'),env=env)
 git('update-index','--force-remove',path,env=env);removed_tree=git('write-tree',env=env).stdout.decode().strip();index.unlink()
 removed=git('commit-tree',removed_tree,'-p',stable,input=b'remove origin fixture').stdout.decode().strip();git('update-ref',ref,removed,stable)
 publish(a.canonical(saved));reject(lambda:a.verify_bootstrap(OriginState(),approval),'publication parent');restore()
 # Partial progress is never completed-prefix credit: old256guard remains a gap.
 partial=dict(saved,complete=False,next_sha=frozen,tree_cursor=None,publication_parent=stable)
 publish(a.canonical(partial));reject(lambda:a.verify_bootstrap(OriginState(),approval),'ancestry bound');restore()
 # Invalid schema and an unrelated delta are not App-writer scanner publications.
 changed=dict(saved,schema_version=True,publication_parent=stable)
 publish(a.canonical(changed));reject(lambda:a.verify_bootstrap(OriginState(),approval),'schema/binding');restore()
 changed=dict(saved,publication_parent=stable)
 payload=a.canonical(changed);blob=git('hash-object','-w','--stdin',input=payload).stdout.decode().strip()
 publish(payload,[{'path':'README.md','type':'blob','mode':'100644','sha':blob}]);reject(lambda:a.verify_bootstrap(OriginState(),approval),'checkpoint-only');restore()
 original=approval.read_bytes();foreign=json.loads(original);foreign.update(bootstrap_sha=stable,bootstrap_tree=out('rev-parse',stable+'^{tree}'));approval.write_text(json.dumps(foreign))
 reject(lambda:a.verify_bootstrap(OriginState(),approval),'pre-bootstrap');approval.write_bytes(original)
 # Full intermediate suffix validation remains mandatory, even with a complete prefix.
 stable_tree=out('rev-parse',ref+'^{tree}');merge=git('commit-tree',stable_tree,'-p',stable,'-p',initial,input=b'merged suffix').stdout.decode().strip();git('update-ref',ref,merge,stable)
 reject(lambda:a.verify_bootstrap(OriginState(),approval),'missing or merged');restore()
 executable=git('hash-object','-w','--stdin',input=b'unsafe').stdout.decode().strip()
 evil_tree=OriginState().request('repos/org/repo/git/trees','POST',{'base_tree':stable_tree,'tree':[{'path':'evil.sh','type':'blob','mode':'100755','sha':executable}]})['sha']
 evil=git('commit-tree',evil_tree,'-p',stable,input=b'executable suffix').stdout.decode().strip();safe=git('commit-tree',stable_tree,'-p',evil,input=b'removed executable').stdout.decode().strip();git('update-ref',ref,safe,stable)
 reject(lambda:a.verify_bootstrap(OriginState(),approval),'state blob path/mode');restore()
 class Drift(OriginState):
  reads=0
  def request(self,target,method='GET',payload=None):
   value=super().request(target,method,payload)
   if target.endswith('/rulesets/1'):
    self.reads+=1
    if self.reads>1:value=copy.deepcopy(value);value['updated_at']='2026-10-16T00:00:00Z'
   return value
 reject(lambda:a.verify_bootstrap(Drift(),approval),'protection changed during')
 class NoWriter(OriginState):
  def request(self,target,method='GET',payload=None):
   value=super().request(target,method,payload)
   if target.endswith('/rulesets/1'):value=copy.deepcopy(value);value['bypass_actors']=[]
   return value
 reject(lambda:a.verify_bootstrap(NoWriter(),approval),'protection policy changed')
 # A real unscanned suffix longer than the original per-invocation bound blocks.
 parent=stable
 for number in range(257):parent=git('commit-tree',stable_tree,'-p',parent,input=('suffix'+str(number)).encode()).stdout.decode().strip()
 git('update-ref',ref,parent,stable);reject(lambda:a.verify_bootstrap(OriginState(),approval),'ancestry bound');restore()
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('completed-origin: PASS; real300-history completed-origin append/discovery/projection/retained/fresh-process and strict partial/copy/schema/delta/bootstrap/merge/inert-tree/mutable-policy/App-writer/suffix-bound checks passed')
'''
early=r'''
 # Malformed ref identity must reject before it becomes a commit API selector.
 class BadRef(State):
  invalid_commit=False
  def request(self,target,method='GET',payload=None):
   if '/git/ref/' in target:return {'ref':ref,'object':{'type':'commit','sha':'../foreign'}}
   if '/git/commits/' in target and not a.state_paths.valid_hash(target.rsplit('/',1)[1],40):
    self.invalid_commit=True;raise AssertionError('malformed ref reached commit GET')
   return super().request(target,method,payload)
 badref=BadRef()
 try:a.verify_bootstrap(badref,approval)
 except ValueError as error:assert 'ancestry invalid' in str(error),str(error)
 else:raise AssertionError('malformed state ref accepted')
 assert badref.invalid_commit is False
'''
cases=early+prefix+cases
exec(compile(fixture+cases,'completed-origin-real-git-fixture','exec'))
PY
