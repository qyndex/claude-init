#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 -u - <<'PYTEST'
"""AC-7: conditional inert-tree deltas bound work to changed subtrees, not all history."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 entries=[]
 for n in range(512):
  key=hashlib.sha256(str(n).encode()).hexdigest();blob=git('hash-object','-w','--stdin',input=b'public fixture').stdout.decode().strip()
  entries.append({'path':f'receipt-archive/materials/{key[:2]}/{key}.json','type':'blob','mode':'100644','sha':blob})
 base=State().request('repos/org/repo/git/trees','POST',{'base_tree':tree,'tree':entries})['sha']
 content=git('hash-object','-w','--stdin',input=b'changed README').stdout.decode().strip()
 changed=State().request('repos/org/repo/git/trees','POST',{'base_tree':base,'tree':[{'path':'README.md','type':'blob','mode':'100644','sha':content}]})['sha']
 class Count(State):
  calls=0
  def request(self,target,method='GET',payload=None):
   assert method=='GET' and payload is None
   self.calls+=1;return super().request(target,method,payload)
 full=Count();assert a.state_paths.scan_tree(full,'repos/org/repo',changed,page_budget=8)['complete'] is False
 assert hasattr(a.state_paths,'scan_delta'),'bounded changed-subtree scanner is missing'
 api=Count();result=a.state_paths.scan_delta(api,'repos/org/repo',changed,base,page_budget=4)
 assert result['complete'] and result['cursor'] is None and api.calls<=4,result
 for prefix in (0,False,None,[],{}):
  bad={'kind':'delta','root':changed,'base':base,'pending':[{'prefix':prefix,'sha':changed,'base':base}]}
  try:a.state_paths.scan_delta(Count(),'repos/org/repo',changed,base,cursor=bad,page_budget=4)
  except ValueError:pass
  else:raise AssertionError('untyped delta cursor prefix accepted')
 # Delta completion is only a conditional invariant; it never authenticates origin.
 assert result['coverage_complete'] is False

 from urllib.parse import parse_qs,urlparse
 import textwrap
 pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r"+chr(39)*3+"\n",1)[1].split(' # Two distinct approved tasks',1)[0]
 exec(compile(textwrap.dedent(pipeline),'real-git-pipeline-api','exec'))
 parent=git('commit-tree',base,'-p',initial,input=b'introduce inert materials').stdout.decode().strip()
 for number in range(32):parent=git('commit-tree',changed,'-p',parent,input=('unchanged material history'+str(number)).encode()).stdout.decode().strip()
 git('update-ref',ref,parent,initial)
 observed=a.advance_origin(PipelineState(),approval,commit_budget=16,tree_pages=8)
 assert observed['checked_commits']==16 and observed['frozen_complete'] is False,observed

 for resume in range(64):
  if observed['frozen_complete']:break
  observed=a.advance_origin(PipelineState(),approval,commit_budget=16,tree_pages=8)
 assert observed['frozen_complete'] and observed['checked_commits']==34,observed
 assert a.verify_bootstrap(PipelineState(),approval)['head']==out('rev-parse',ref)
 print('real-Git origin window advances16delta edges and completes only after actual introduced subtrees/bootstrap validation',flush=True)


'''
exec(compile(fixture+cases,'actual-state-delta-real-git','exec'))
PYTEST
