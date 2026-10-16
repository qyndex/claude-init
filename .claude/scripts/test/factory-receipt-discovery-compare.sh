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
 spec=importlib.util.spec_from_file_location('compact_discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
 old=out('rev-parse',ref);new=git('commit-tree',out('rev-parse',old+'^{tree}'),'-p',old,input=b'actual descendant metadata\n').stdout.decode().strip()
 class Metadata(HistoryState):
  def request(self,target,**kwargs):
   if '/compare/' in target:
    assert target.count('?')==1 and target.split('?',1)[1]=='per_page=1&page=2', 'compare must have exactly one metadata-only page query'
    return super().request(target.split('?',1)[0],**kwargs)
   return super().request(target,**kwargs)
 d._checkpoint_ancestor(Metadata().request,'/repos/org/repo',old,old)
 d._checkpoint_ancestor(Metadata().request,'/repos/org/repo',old,new)
 try:d._checkpoint_ancestor(Metadata().request,'/repos/org/repo',new,old)
 except ValueError:pass
 else:raise AssertionError('reverse ancestry accepted')
 print('actual Git identical ancestry metadata uses bounded second-page compare')
'''
exec(compile(fixture+pipeline+provider+cases,'compact-discovery-compare-real-git','exec'))
PYTEST
