#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
import importlib.util,json
from pathlib import Path
from types import SimpleNamespace
spec=importlib.util.spec_from_file_location('transport',Path('.claude/scripts/factory-reporting-transport.py'));t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
calls=[];response=b'{"status":"ahead","behind_by":0,"nested":{"value":1}}'
def provider(command,**kwargs):
 assert command[:6]==['gh','api','--hostname','github.com','--method','GET']
 assert kwargs['env']['GH_TOKEN']=='writer-fixture'
 calls.append(command[6]);return SimpleNamespace(returncode=0,stdout=response,stderr=b'')
t.process.run=provider
root='repos/org/repo';pair='a'*40+'...'+'b'*40;path=root+'/compare/'+pair+'?per_page=1&page=2'
api=t.RoutedAPI('org/repo','source-fixture','writer-fixture');first=api.request(path);first['nested']['value']=999
second=api.request(path)
assert len(calls)==1,'exact immutable ancestry comparison fetched twice'
assert second['nested']['value']==1 and api.budget.calls==1 and api.budget.bytes==len(response)
print('PASS exact immutable comparison single physical fetch/deep-copy/raw-byte accounting')
for other in [path.replace('b'*40,'c'*40),path.replace('per_page=1&page=2','page=2&per_page=1'),path.replace('page=2','page=1'),path.replace('per_page=1','per_page=2')]:
 before=len(calls);api.request(other);api.request(other)
 assert len(calls)-before==(1 if other==path.replace('b'*40,'c'*40) else 2)
for mutable in [root,root+'/git/ref/heads/state',root+'/rulesets/1',root+'/rules/branches/state']:
 before=len(calls);api.request(mutable);api.request(mutable);assert len(calls)==before+2
for bad,options in [(root+'/compare/main...topic?per_page=1&page=2',{}),(path.replace('org/repo','foreign/repo'),{}),(path,{'method':'POST','payload':{}}),(path,{'raw':True}),(path.replace('a'*40,'%2E%2E'),{})]:
 before=len(calls)
 try:api.request(bad,**options)
 except ValueError:pass
 else:raise AssertionError('invalid comparison route accepted')
 assert len(calls)==before
before=len(calls);response=b'{"status":1,"status":2}'
fresh=t.RoutedAPI('org/repo','source-fixture','writer-fixture')
for _ in range(2):
 try:fresh.request(path)
 except ValueError:pass
 else:raise AssertionError('invalid JSON comparison cached')
assert len(calls)==before+2 and not fresh._immutable
response=b'{"nested":{"value":1}}';fresh=t.RoutedAPI('org/repo','source-fixture','writer-fixture');fresh._immutable_bytes=t.MAX_BYTES
try:fresh.request(path)
except ValueError as error:assert 'cache capacity' in str(error)
else:raise AssertionError('comparison cache byte bound bypassed')
assert not fresh._immutable
print('PASS unique selectors/unrecognized query/mutable freshness/foreign/raw/mutation/invalid JSON/cache byte controls')
PY
