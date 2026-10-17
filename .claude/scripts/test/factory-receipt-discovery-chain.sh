#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 -u - <<'PYTEST'
"""AC-7: protected source checkpoints do not acquire a256-history lifetime cliff."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct approved tasks',1)[0]
provider=Path('.claude/scripts/test/factory-receipt-history.sh').read_text().split("cases=r'''\n",1)[1].split(' total=1001;end=',1)[0]
cases=r'''
 spec=importlib.util.spec_from_file_location('long_discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 class Empty:
  repo='org/repo'
  def request(self,target,**kwargs):
   assert '/actions/workflows/10/runs?' in target and kwargs.get('method','GET')=='GET'
   return {'total_count':0,'workflow_runs':[]}
 class DiscoveryState(HistoryState):
  def request(self,target,**kwargs):
   if '/compare/' in target:target=target.split('?',1)[0]
   return super().request(target,**kwargs)
 stream=a.archive_stream('org/repo');end='2026-10-15T23:00:00Z'
 for number in range(300):
  try:d.backfill(Empty(),DiscoveryState(),policy,approval,stream,interval_end=end,page_size=100)
  except ValueError as error:raise AssertionError(f'actual source checkpoint {number+1}/300 blocked despite authenticated completed origin: {error}') from error
  if number%8==7:
   for resume in range(128):
    origin=a.advance_origin(HistoryState(),approval,commit_budget=16,tree_pages=8)
    if origin['frozen_complete']:break
   assert origin['frozen_complete']
  if number%50==49:print('actual protected source checkpoints='+str(number+1),flush=True)
 assert int(out('rev-list','--count',ref))>256
 progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
 assert progress['watch']=={'segments':0,'count':0} and progress['coverage_complete'] is False
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual300source-checkpoint history remains resumable under current origin without erasing retained discovery state')
'''
exec(compile(fixture+pipeline+provider+cases,'actual-discovery-history-real-git','exec'))
PYTEST
