#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: real Git prior-completed proof while a new scan is incomplete."""
from pathlib import Path
cas=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text();origin=Path('.claude/scripts/test/factory-receipt-origin-windows.sh').read_text()
assert cas.count("<<'PY'\n")==1 and cas.count(" store={'repository'")==1
assert origin.count("cases=r'''\n")==1 and origin.count('\n # More than')==1
fixture=cas.split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
transport=origin.split("cases=r'''\n",1)[1].split(' # More than',1)[0]
cases=r'''
 from unittest.mock import patch
 def publish(entries):
  parent=out('rev-parse',ref);tree=OriginState().request('repos/org/repo/git/trees','POST',{'base_tree':out('rev-parse',ref+'^{tree}'),'tree':entries})['sha']
  commit=git('commit-tree',tree,'-p',parent,input=b'actual fixture origin history').stdout.decode().strip();git('update-ref',ref,commit,parent);return commit
 def leaf(path,raw):
  blob=git('hash-object','-w','--stdin',input=raw).stdout.decode().strip();return {'path':path,'type':'blob','mode':'100644','sha':blob}
 path='receipt-archive/origin/'+a.archive_stream('org/repo')+'.json'
 for number in range(48):publish([leaf('reports/'+'1'*64+'.json',('opaque '+str(number)).encode())])
 for _ in range(64):
  progress=a.advance_origin(OriginState(),approval,commit_budget=16,tree_pages=4)
  if progress['frozen_complete']:break
 else:raise AssertionError('actual fixture origin never completed')
 completed=json.loads(git('show',ref+':'+path).stdout);assert completed['complete'];expected=completed['frozen_head']
 publish([leaf('reports/'+'2'*64+'.json',b'later independent queue journal')])
 first=a.advance_origin(OriginState(),approval,commit_budget=1,tree_pages=1)
 second=a.advance_origin(OriginState(),approval,commit_budget=1,tree_pages=1)
 assert not first['frozen_complete'] and not second['frozen_complete'],'fixture must retain repeated actual incomplete scan publications'
 current=json.loads(git('show',ref+':'+path).stdout);assert current['prior_verified']==expected and current['complete'] is False
 stable=out('rev-parse',ref)
 class Bounded(OriginState):
  def __init__(self):self.calls=0
  def request(self,path,method='GET',payload=None):
   assert method=='GET','readonly proof attempted write'
   if self.calls>=128:raise ValueError('fixture unchanged 128 read capacity')
   self.calls+=1;return super().request(path,method,payload)
 proof=a._completed_origin(OriginState(),a._bootstrap_context(OriginState(),approval))
 measured=Bounded();verified=None;failure=None
 try:verified=a.verify_bootstrap(measured,approval)
 except ValueError as error:failure=str(error)
 print(json.dumps({'actual_git_history_commits':48,'prior_prefix_reused':proof==expected,'public_verify_calls':measured.calls,'public_verify_failure':failure}))
 assert proof==expected,'incomplete scan discarded authenticated prior completed prefix'
 assert verified is not None and verified['head']==stable and measured.calls<128,'prior proof did not preserve bounded actual verification'
 assert out('rev-parse',ref)==stable and git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 def reject(fn,reason):
  before=out('rev-parse',ref)
  try:fn()
  except ValueError as error:assert reason in str(error),(reason,str(error))
  else:raise AssertionError('untrusted prior accepted '+reason)
  assert out('rev-parse',ref)==before
 # A plausible ancestral hash is insufficient without its actual completed proof.
 wrong=dict(current,prior_verified=initial,publication_parent=stable)
 publish([leaf(path,a.canonical(wrong))]);reject(lambda:a.verify_bootstrap(OriginState(),approval),'prior completed origin');git('update-ref',ref,stable,out('rev-parse',ref))
 # Missing earlier role proof cannot be replaced with the current partial flag/hash.
 parent=out('rev-parse',ref);index=root/'delete-origin-index';env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',parent,env=env);git('update-index','--force-remove',path,env=env);tree=git('write-tree',env=env).stdout.decode().strip();index.unlink()
 deleted=git('commit-tree',tree,'-p',parent,input=b'deleted proof fixture').stdout.decode().strip();git('update-ref',ref,deleted,parent)
 publish([leaf(path,a.canonical(dict(current,publication_parent=deleted)))]);reject(lambda:a.verify_bootstrap(OriginState(),approval),'prior completed origin');git('update-ref',ref,stable,out('rev-parse',ref))
 # Native immutable publication linkage is mandatory, even with the correct prior.
 bad=dict(current,publication_parent=initial);publish([leaf(path,a.canonical(bad))]);reject(lambda:a.verify_bootstrap(OriginState(),approval),'publication parent');git('update-ref',ref,stable,out('rev-parse',ref))
 # Reusing the old prefix never skips the suffix or hides a dangerous intermediate.
 dangerous=publish([{'path':'evil.sh','type':'blob','mode':'100755','sha':leaf('ignored',b'unsafe')['sha']}])
 clean=git('commit-tree',out('rev-parse',stable+'^{tree}'),'-p',dangerous,input=b'removed executable fixture').stdout.decode().strip();git('update-ref',ref,clean,dangerous)
 reject(lambda:a.verify_bootstrap(OriginState(),approval),'state blob path/mode');git('update-ref',ref,stable,out('rev-parse',ref))
 # Synthetic corrupted-helper cycle tests the traversal bound, not native Git proof.
 capsule=dict(current);context=a._bootstrap_context(OriginState(),approval);head=context['ref']['object']['sha']
 with patch.object(a,'_origin_publication',return_value=(capsule,head)):
  reject(lambda:a._completed_origin(OriginState(),context),'prior completed origin cycle')
 print('prior-completed origin actual Git bounded reuse, missing/mismatched proof, publication tamper, dangerous intermediate and synthetic cycle PASS; no native capability claim')
'''
exec(compile(fixture+transport+cases,'origin-prior-real-git-fixture','exec'))
PY
