#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: actual offline subprocess count and bounded immutable reuse."""
import importlib.util,json,os,tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('transport',Path('.claude/scripts/factory-reporting-transport.py'));t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
with tempfile.TemporaryDirectory() as directory:
 root=Path(directory);response=root/'response';calls=root/'calls'
 stub=root/'gh';stub.write_text('''#!/usr/bin/env python3
import os,sys
from pathlib import Path
root=Path(os.environ['HOME'])
with (root/'calls').open('a') as out:out.write('call\\n')
sys.stdout.buffer.write((root/'response').read_bytes())
''');stub.chmod(0o755)
 saved=dict(os.environ);os.environ.update(PATH=str(root)+os.pathsep+saved['PATH'],HOME=str(root))
 try:
  api=t.RoutedAPI('org/repo','source-fixture','writer-fixture');response.write_text('{"nested":{"value":1}}')
  def count():return len(calls.read_text().splitlines()) if calls.exists() else 0
  for kind in ('commits','trees','blobs'):
   path='repos/org/repo/git/'+kind+'/'+'a'*40;before=count();meter=(api.budget.calls,api.budget.bytes)
   first=api.request(path);first['nested']['value']=999
   assert api.request(path)=={'nested':{'value':1}},'cached response was caller-mutable'
   assert count()==before+1,'same immutable Git object fetched more than once in one invocation'
   assert (api.budget.calls,api.budget.bytes)==(meter[0]+1,meter[1]+response.stat().st_size)
  for path in ('repos/org/repo','repos/org/repo/git/ref/heads/state','repos/org/repo/rulesets/7','repos/org/repo/pulls/7','repos/org/repo/actions/runs/7','repos/org/repo/git/trees/'+'b'*40+'?recursive=1'):
   before=count();response.write_text('{"value":1}');assert api.request(path)=={'value':1}
   response.write_text('{"value":2}');assert api.request(path)=={'value':2};assert count()==before+2,'mutable/query endpoint was cached'
  before=count()
  try:api.request('repos/org/repo/git/blobs/'+'a'*40,'POST',{})
  except ValueError:pass
  else:raise AssertionError('cache bypassed route method guard')
  assert count()==before
  before=count();api.repo='foreign/repo'
  try:api.request('repos/org/repo/git/blobs/'+'a'*40)
  except ValueError:pass
  else:raise AssertionError('cache bypassed same repository guard')
  assert count()==before;api.repo='org/repo'
  response.write_text('{"value":3}');fresh=t.RoutedAPI('org/repo','source-fixture','writer-fixture')
  assert fresh.request('repos/org/repo/git/blobs/'+'a'*40)=={'value':3};assert count()==before+1,'cache escaped invocation'
  before=count();compare='repos/org/repo/compare/'+'a'*40+'...'+'b'*40+'?per_page=1&page=2'
  assert api.request(compare)=={'value':3};assert count()==before+1
  for bad in ('repos/org/repo/compare/'+'a'*39+'...'+'b'*40,'repos/org/repo/compare/'+'a'*40+'...'+'b'*40+'/../heads'):
   before=count()
   try:api.request(bad)
   except ValueError:pass
   else:raise AssertionError('malformed compare/traversal accepted')
   assert count()==before
  # UTF8 wire bytes are smaller than canonical ASCII serialization. Storage,
  # rather than only input/network accounting, must remain bounded too.
  response.write_text(json.dumps({'text':'😀'*140000},ensure_ascii=False));bounded=t.RoutedAPI('org/repo','source-fixture','writer-fixture')
  for number in range(1,30):
   try:bounded.request('repos/org/repo/git/blobs/'+format(number,'040x'))
   except ValueError as error:
    assert 'capacity' in str(error);assert bounded.budget.bytes<33554432;break
  else:raise AssertionError('normalized immutable cache exceeded 32MiB')
  assert bounded._immutable_bytes<=33554432
  print('immutable actual subprocess reuse/deepcopy/accounting, fresh mutable reads, route guards, invocation isolation and normalized memory bound passed')
 finally:os.environ.clear();os.environ.update(saved)
PY
