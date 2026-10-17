#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 -u - <<'PY'
"""AC-6/AC-8: authenticated large prefix plus every actual suffix edge, not tree replay."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct approved tasks',1)[0]
provider=Path('.claude/scripts/test/factory-receipt-history.sh').read_text().split("\ncases=r'''\n",1)[1].split(' total=1001;end=',1)[0]
cases=r'''
 stream=a.archive_stream('org/repo');campaign='e'*64
 for n in range(256):
  key=f'{n:02x}'+'0'*62
  for path in (f'receipt-archive/objects/{key[:2]}/{key}.json',f'receipt-archive/materials/{key[:2]}/{key}.json',f'receipt-archive/index/{stream}/identities/{key[:2]}/{key}.json',f'receipt-archive/stages/{campaign}/{key[:2]}/{key}.json'):
   leaf=work/path;leaf.parent.mkdir(parents=True,exist_ok=True);leaf.write_text('{}')
 git('add','receipt-archive');tree_large=out('write-tree');large=git('commit-tree',tree_large,'-p',initial,input=b'large inert namespace, not retained delivery facts').stdout.decode().strip();git('update-ref',ref,large,initial)
 partial=a.advance_origin(HistoryState(),approval,commit_budget=1,tree_pages=1)
 assert not partial['frozen_complete']
 try:a.verify_bootstrap(HistoryState(),approval)
 except ValueError:pass
 else:raise AssertionError('incomplete origin skipped unchecked namespace')
 for invocation in range(256):
  progress=a.advance_origin(HistoryState(),approval,commit_budget=16,tree_pages=8)
  if progress['frozen_complete']:break
 assert progress['frozen_complete'],'real protected origin did not resume'
 stable=out('rev-parse',ref)
 observed=a.verify_bootstrap(HistoryState(),approval)
 assert observed['head']==stable and observed['tree']==out('rev-parse',stable+'^{tree}')
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('real >1000-subtree protected prefix accepted without full namespace replay',flush=True)
 def rejected(call):
  try:call()
  except (ValueError,RuntimeError):pass
  else:raise AssertionError('untrusted suffix accepted')
 def commit_entry(parent,path,mode='100644',remove=False):
  index=root/'negative-index';index.unlink(missing_ok=True);env=dict(os.environ,GIT_INDEX_FILE=str(index));git('read-tree',out('rev-parse',parent+'^{tree}'),env=env)
  if remove:git('update-index','--force-remove',path,env=env)
  else:
   blob=git('hash-object','-w','--stdin',input=b'{}').stdout.decode().strip();git('update-index','--add','--cacheinfo',mode+','+blob+','+path,env=env)
  tree=git('write-tree',env=env).stdout.decode().strip();index.unlink();return git('commit-tree',tree,'-p',parent,input=b'hostile suffix fixture').stdout.decode().strip()
 suffix1=commit_entry(stable,'receipt-archive/objects/ff/'+'f'*64+'.json')
 suffix2=commit_entry(suffix1,'receipt-archive/objects/ee/'+'e'*64+'.json')
 git('update-ref',ref,suffix2,stable);stable=suffix2
 assert a.verify_bootstrap(HistoryState(),approval)['head']==stable,'valid inert suffix rejected'
 for field in ('sha','tree'):
  class ForeignParent(HistoryState):
   def request(self,target,method='GET',payload=None):
    value=super().request(target,method,payload)
    if target.endswith('/git/commits/'+suffix1):
     if field=='sha':value['sha']='f'*40
     else:value['tree']['sha']='../foreign'
    return value
  rejected(lambda:a.verify_bootstrap(ForeignParent(),approval))
 bad=commit_entry(stable,'receipt-archive/objects/aa/'+'a'*64+'.json','100755');removed=commit_entry(bad,'receipt-archive/objects/aa/'+'a'*64+'.json',remove=True);git('update-ref',ref,removed,stable)
 rejected(lambda:a.verify_bootstrap(HistoryState(),approval));git('update-ref',ref,stable,removed)
 merged=git('commit-tree',out('rev-parse',stable+'^{tree}'),'-p',stable,'-p',initial,input=b'merged suffix').stdout.decode().strip();git('update-ref',ref,merged,stable)
 rejected(lambda:a.verify_bootstrap(HistoryState(),approval));git('update-ref',ref,stable,merged)
 class MalformedParent(HistoryState):
  def request(self,target,method='GET',payload=None):
   value=super().request(target,method,payload)
   if target.endswith('/git/commits/'+stable):value['parents']=[{'sha':'../foreign'}]
   return value
 rejected(lambda:a.verify_bootstrap(MalformedParent(),approval))
 class Unavailable(HistoryState):
  def request(self,target,method='GET',payload=None):
   if '/git/trees/' in target:raise RuntimeError('required tree unavailable')
   return super().request(target,method,payload)
 rejected(lambda:a.verify_bootstrap(Unavailable(),approval))
 saved=copy.deepcopy(policies[1]);policies[1]['updated_at']='2026-10-16T00:00:00Z';rejected(lambda:a.verify_bootstrap(HistoryState(),approval));policies[1]=saved
 assert out('rev-parse',ref)==stable
 print('transient executable add/remove, merge, malformed parent, unavailable tree and current protection drift fail closed')
'''
exec(compile(fixture+pipeline+provider+cases,'large-authenticated-prefix-delta','exec'))
PY
