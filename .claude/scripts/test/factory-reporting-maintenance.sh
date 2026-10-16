#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: bounded real protected maintenance before fresh reporting state."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
cases=r'''
 assert a.verify_bootstrap(State(),approval)['head']==initial
 print('actual disposable Git origin and opaque feedback baseline verified',flush=True)
 class EmptySource:
  repo='org/repo'
  def request(self,target,**kwargs):
   assert not kwargs and target.startswith('repos/org/repo/actions/workflows/') and '/runs?' in target
   return {'workflow_runs':[],'total_count':0}
  def get(self,target):raise AssertionError('empty source has no run detail or artifacts')
 ds=importlib.util.spec_from_file_location('discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(ds);ds.loader.exec_module(d)
 stream=a.archive_stream('org/repo');ends=('2026-10-15T00:01:00Z','2026-10-16T00:01:00Z')
 for end in ends:
  for _ in range(3):d.backfill(EmptySource(),State(),policy,approval,stream,interval_end=end,page_size=100,tree_pages=10,interval_scoped=True)
  anchor=a.verify_bootstrap(State(),approval);key=a.interval_scope(anchor,stream,end,True)
  saved=json.loads(git('show',ref+':receipt-archive/backfill/'+key+'.json').stdout)
  assert saved['interval_start']=='2026-10-15T00:00:00Z' and saved['interval_end']==end and saved['epoch']>=1
 assert a.interval_scope(anchor,stream,ends[0],True)!=a.interval_scope(anchor,stream,ends[1],True)
 assert git('show',ref+':receipt-archive/backfill/'+a.interval_scope(anchor,stream,ends[0],True)+'.json').stdout
 path=scripts/'factory-reporting-maintenance.py'
 assert path.exists(),'missing bounded protected reporting maintenance'
 module=importlib.util.spec_from_file_location('maintenance',path);m=importlib.util.module_from_spec(module);module.loader.exec_module(m)
 store={'repository':'org/repo','visibility':'public'}
 result=m.maintain(EmptySource(),State(),policy,trust,store,approval,interval_end='2026-10-15T00:01:00Z')
 assert result['status']=='incomplete' and result['coverage_complete'] is False and result['task_credit'] is False
 assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('bounded first maintenance transition preserves opaque feedback; no caller completion authority')
'''
exec(compile(fixture+cases,'reporting-maintenance-fixture','exec'))
PY
