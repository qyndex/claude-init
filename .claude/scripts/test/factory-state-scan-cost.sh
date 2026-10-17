#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 -u - <<'PYTEST'
"""AC-7: conditional inert-tree deltas bound work to changed subtrees, not all history."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 entries=[];blob=git('hash-object','-w','--stdin',input=b'public fixture').stdout.decode().strip()
 for n in range(512):
  key=hashlib.sha256(str(n).encode()).hexdigest()
  entries.append({'path':f'receipt-archive/materials/{key[:2]}/{key}.json','type':'blob','mode':'100644','sha':blob})
 base=State().request('repos/org/repo/git/trees','POST',{'base_tree':tree,'tree':entries})['sha']
 original=a.state_paths.validate_entry;calls=0
 def counted(entry):
  global calls
  calls+=1;return original(entry)
 a.state_paths.validate_entry=counted
 cursor=None;total=0
 for window in range(10):
  value=a.state_paths.scan_tree(State(),'repos/org/repo',base,cursor=cursor,page_budget=100)
  total+=len(value['entries'])
  if value['complete']:break
  cursor=value['cursor']
 assert value['complete']
 print('actual validated entries='+str(total)+'; validate_entry calls='+str(calls),flush=True)
 assert calls<=3*total,'immutable subtree scan repeatedly revalidates accumulated entries instead of linear checked work'
 a.state_paths.validate_entry=original
 class Duplicate(State):
  def request(self,target,method='GET',payload=None):
   value=super().request(target,method,payload)
   if '/git/trees/' in target and value['tree']:value=dict(value,tree=value['tree']+[dict(value['tree'][0])])
   return value
 try:a.state_paths.scan_tree(Duplicate(),'repos/org/repo',base)
 except ValueError:pass
 else:raise AssertionError('duplicate immediate metadata path accepted')
 report_tree=next(row['sha'] for row in State().request('repos/org/repo/git/trees/'+base)['tree'] if row['path']=='reports')
 cursor={'root':base,'pending':[{'prefix':'','sha':base},{'prefix':'reports','sha':report_tree}]}
 try:a.state_paths.scan_tree(State(),'repos/org/repo',base,cursor=cursor,page_budget=100)
 except ValueError:pass
 else:raise AssertionError('overlapping frontier repeated full path accepted')
 print('linear work preserves immediate and cross-subtree duplicate rejection')

'''
exec(compile(fixture+cases,'linear-state-scan-real-git','exec'))
PYTEST
