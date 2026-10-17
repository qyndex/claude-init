#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7: cold watched reruns, retained-first expiry and source-authenticated non-delivery."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 s=importlib.util.spec_from_file_location('discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(s);s.loader.exec_module(d)
 class Runs(Source):
  artifact_calls=0;source_unavailable=False;artifact_unavailable=False
  def get(self,path):
   if '/actions/runs/' in path:
    if getattr(self,'metadata_unavailable',False):raise RuntimeError('metadata temporarily unavailable')
    if getattr(self,'metadata_api_unavailable',False):raise ValueError('GitHub API request failed: repos/org/repo/actions/runs/20')
    run_id=int(path.split('/actions/runs/',1)[1].split('/')[0])
    if run_id in getattr(self,'old_runs',{}):return self.old_runs[run_id]
    if '/attempts/' in path:return self.attempts[int(path.rsplit('/',1)[1])]
    return self.run
   return super().get(path)
  def source(self,path,sha):
   if self.source_unavailable:raise RuntimeError('source temporarily unavailable')
   return super().source(path,sha)
  def request(self,path,**kwargs):
   if '/actions/workflows/' in path:return {'workflow_runs':[getattr(self,'late',None) or self.run] if path.endswith('page=1') else []}
   if '/artifacts' in path:
    self.artifact_calls+=1
    if self.artifact_unavailable:raise RuntimeError('artifact unavailable')
   return super().request(path,**kwargs)
 runs=Runs(policy,receipt);runs.run['conclusion']='failure';runs.attempts={1:copy.deepcopy(runs.run)};stream=a.archive_stream('org/repo');store={'repository':'org/repo','visibility':'public'}
 d.advance(runs,State(),policy,approval,stream,page_size=1)
 runs.metadata_unavailable=True
 result=d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
 assert result['complete'] is False
 runs.metadata_unavailable=False
 def outcomes():
  result=[]
  for name in out('ls-tree','-r','--name-only',ref).splitlines():
   if name.startswith('receipt-archive/outcomes/'):result.append(json.loads(git('show',ref+':'+name).stdout))
  return result
 assert outcomes()[-1]['classification']=='watch' and outcomes()[-1]['reason']=='unavailable'
 d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
 assert outcomes()[-1]['classification']=='watch' and not any(name.startswith('receipt-archive/objects/') for name in out('ls-tree','-r','--name-only',ref).splitlines())
 # Revisit a frozen overlap page: a previously invisible older ID is retained too.
 runs.late=copy.deepcopy(runs.run);runs.late['id']=19;runs.old_runs={19:runs.late}
 d.advance(runs,State(),policy,approval,stream,page_size=1)
 progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
 watched=[row['run_id'] for number in range(progress['watch']['segments']) for row in json.loads(git('show',ref+':'+a.state_paths.pending_segment_path(stream,number)).stdout)['rows']]
 assert set(watched)=={19,20};runs.late=None
 # No creation-time watermark: revisiting the same old ID discovers attempt2.
 runs.run.update(run_attempt=2,status='completed',conclusion='success');runs.attempts[2]=copy.deepcopy(runs.run)
 for _ in range(6):d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
 assert any(x['attempt']==2 and x['classification']=='retained-delivery' for x in outcomes())
 calls=runs.artifact_calls;runs.expired=True;runs.artifact_unavailable=True
 for _ in range(3):d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
 assert runs.artifact_calls==calls  # Known retained index before any Actions artifact call.
 runs.metadata_api_unavailable=True
 for _ in range(3):d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
 assert any(x['attempt']==2 and x['classification']=='retained-delivery' for x in outcomes()) and runs.artifact_calls==calls
 runs.metadata_api_unavailable=False
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 # Copied retained proof in a bootstrap is not a reviewed authenticated import.
 imported=root/'copied-archive-bootstrap.json';copied=json.loads(approval.read_text());copied.update(bootstrap_sha=out('rev-parse',ref),bootstrap_tree=out('rev-parse',ref+'^{tree}'));imported.write_text(json.dumps(copied));import_anchor=a.verify_bootstrap(State(),imported)
 try:a.retained_execution(State(),import_anchor,store,stream,20,2)
 except ValueError as error:assert 'pre-bootstrap' in str(error)
 else:raise AssertionError('copied bootstrap receipt became authenticated proof')
 try:a.project_retained(State(),policy,root/'copied.sqlite',trust,store,imported,stream)
 except ValueError as error:assert 'pre-bootstrap' in str(error)
 else:raise AssertionError('copied bootstrap archive projected')
 original_head=out('rev-parse',ref);runs.expired=False;runs.artifact_unavailable=False
 for keep_objects in (True,False):
  index=root/'alias-index';env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',original_head,env=env)
  for name in out('ls-tree','-r','--name-only',original_head).splitlines():
   if name.startswith(('receipt-archive/index/','receipt-archive/discovery/')) or (not keep_objects and name.startswith('receipt-archive/objects/')):git('update-index','--force-remove',name,env=env)
  alias_tree=git('write-tree',env=env).stdout.decode().strip();index.unlink();alias_head=git('commit-tree',alias_tree,'-p',original_head,input=b'copied record/material bootstrap').stdout.decode().strip();git('update-ref',ref,alias_head,out('rev-parse',ref))
  copied=json.loads(approval.read_text());copied.update(bootstrap_sha=alias_head,bootstrap_tree=alias_tree);imported.write_text(json.dumps(copied))
  a.append_delivery(runs,State(),policy,20,trust,store,imported,stream)
  alias_anchor=a.verify_bootstrap(State(),imported)
  try:a.retained_execution(State(),alias_anchor,store,stream,20,2)
  except ValueError as error:assert ('object pre-bootstrap' if keep_objects else 'material pre-bootstrap') in str(error)
  else:raise AssertionError('copied object/material alias became proof')
 git('update-ref',ref,original_head,out('rev-parse',ref));runs.expired=True;runs.artifact_unavailable=True
 # Fresh epoch: an unapproved source is never permanently discarded.
 original=trust.read_bytes();unknown=json.loads(original);unknown['profiles']=[];trust.write_text(json.dumps(unknown))
 for _ in range(3):d.reconcile(runs,State(),policy,trust,store,approval,stream,review_rows=2)
 assert any(x['classification']=='retained-delivery' and x['trust_status']=='withdrawn' for x in outcomes())
 trust.write_bytes(original)
 # Separate shadow fixture: exact approved merge-disabled source needs no artifact.
 git('update-ref',ref,initial,out('rev-parse',ref));shadow_policy=copy.deepcopy(policy);shadow_policy['merge_enabled']=False
 shadow=Runs(shadow_policy,receipt);shadow.run['head_sha']='e'*40;shadow.run['conclusion']='failure';shadow.attempts={1:copy.deepcopy(shadow.run)};shadow.artifact_unavailable=True
 shadow_trust={'schema_version':1,'repository':'org/repo','profiles':[{'id':'shadow','status':'active','policy_sha256':r.coordinator.policy_hash(shadow_policy),'runtime':policy['receipts']['trusted_revisions']['a'*40]}],'legacy_revisions':{}};trust.write_text(json.dumps(shadow_trust))
 d.advance(shadow,State(),shadow_policy,approval,stream,page_size=1)
 d.reconcile(shadow,State(),shadow_policy,trust,store,approval,stream)
 assert outcomes()[-1]['classification']=='non-delivery' and outcomes()[-1]['reason']=='source-merge-disabled' and shadow.artifact_calls==0
 shadow.source_unavailable=True;d.reconcile(shadow,State(),shadow_policy,trust,store,approval,stream)
 assert outcomes()[-1]['classification']=='non-delivery' and shadow.artifact_calls==0
 # Cached dispositions are trust-epoch bound; revocation cannot reuse a positive source approval.
 shadow.source_unavailable=False;shadow_trust['profiles'][0]['status']='revoked';trust.write_text(json.dumps(shadow_trust))
 d.reconcile(shadow,State(),shadow_policy,trust,store,approval,stream)
 assert any(x['classification']=='unapproved' for x in outcomes())
 shadow_trust['profiles']=[];trust.write_text(json.dumps(shadow_trust));d.reconcile(shadow,State(),shadow_policy,trust,store,approval,stream)
 assert outcomes() and all(x['classification']!='retained-delivery' for x in outcomes())
 shadow_trust['profiles']=[{'id':'shadow2','status':'active','policy_sha256':r.coordinator.policy_hash(shadow_policy),'runtime':policy['receipts']['trusted_revisions']['a'*40]}];trust.write_text(json.dumps(shadow_trust));d.reconcile(shadow,State(),shadow_policy,trust,store,approval,stream)
 assert any(x['classification']=='non-delivery' and x['source']['profile_id']=='shadow2' for x in outcomes())
 assert not any(name.startswith('receipt-archive/objects/') for name in out('ls-tree','-r','--name-only',ref).splitlines())
 # Merge-capable successful shadow also retains exact source and digest-verified receipt bytes.
 git('update-ref',ref,initial,out('rev-parse',ref));trust.write_bytes(original)
 shadow_receipt=copy.deepcopy(receipt);shadow_receipt['merged']=False;shadow_receipt.pop('merge_sha');shadow_receipt.pop('task_ids')
 capable=Runs(policy,shadow_receipt);capable.attempts={1:copy.deepcopy(capable.run)}
 d.advance(capable,State(),policy,approval,stream,page_size=1);capable.artifact_unavailable=True;d.reconcile(capable,State(),policy,trust,store,approval,stream)
 assert outcomes()[-1]['classification']=='watch' and outcomes()[-1]['record_sha256'] is None
 capable.artifact_unavailable=False;d.reconcile(capable,State(),policy,trust,store,approval,stream)
 assert outcomes()[-1]['classification']=='non-delivery' and outcomes()[-1]['reason']=='authenticated-shadow'
 calls=capable.artifact_calls;capable.expired=True;capable.source_unavailable=True;capable.artifact_unavailable=True
 d.reconcile(capable,State(),policy,trust,store,approval,stream)
 assert capable.artifact_calls==calls and outcomes()[-1]['classification']=='non-delivery'
 capable.metadata_api_unavailable=True;d.reconcile(capable,State(),policy,trust,store,approval,stream)
 assert capable.artifact_calls==calls and outcomes()[-1]['classification']=='non-delivery'
 capable.metadata_api_unavailable=False
 # A copied source/receipt capsule cannot become origin merely by appearing at bootstrap.
 current=out('rev-parse',ref);index=root/'copied-index';env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',current,env=env)
 for name in out('ls-tree','-r','--name-only',ref).splitlines():
  if name.startswith(('receipt-archive/progress/','receipt-archive/pending/')):git('update-index','--force-remove',name,env=env)
 copied_tree=git('write-tree',env=env).stdout.decode().strip();index.unlink();copied_head=git('commit-tree',copied_tree,'-p',current,input=b'copied bootstrap capsule').stdout.decode().strip();git('update-ref',ref,copied_head,current)
 copied=json.loads(approval.read_text());copied.update(bootstrap_sha=copied_head,bootstrap_tree=copied_tree);imported.write_text(json.dumps(copied))
 d.advance(capable,State(),policy,imported,stream,page_size=1)
 try:d.reconcile(capable,State(),policy,trust,store,imported,stream)
 except ValueError as error:assert 'pre-bootstrap' in str(error)
 else:raise AssertionError('copied source capsule became authenticated outcome')
 print('20 coldwatch/rerun/retained-expiry/source-authenticated shadow/epoch scenarios passed')
'''
exec(compile(fixture+cases,'real-git-rerun-fixture','exec'))
PY
