#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""Exercise the actual nested queue delivery adapter, never a mirrored classifier."""
import ast,copy,importlib.util,json
from pathlib import Path
spec=importlib.util.spec_from_file_location('queue_cache',Path('.claude/scripts/factory-reporting-queue.py'));q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
tree=ast.parse(Path(q.__file__).read_text())
run=next(node for node in tree.body if isinstance(node,ast.FunctionDef) and node.name=='run_queue')
node=next(node for node in run.body if isinstance(node,ast.ClassDef) and node.name=='DeliveryAPI')
class API:
 repo='org/repo'
 def __init__(self):self.calls=[];self.value={'sha':'a'*40,'nested':{'value':1}}
 def request(self,path,method='GET',payload=None):self.calls.append((path,method,payload));return copy.deepcopy(self.value)
def adapter(archive=True):
 api=API();scope=dict(vars(q),api=api,storage={'state_view':{'mode':'archive'}} if archive else {})
 exec(compile(ast.fix_missing_locations(ast.Module(body=[node],type_ignores=[])),'actual-queue-delivery-class','exec'),scope)
 return api,scope['DeliveryAPI']()
path='repos/org/repo/git/blobs/'+'a'*40
api,delivery=adapter();first=delivery.request(path);first['nested']['value']=99
api.value['nested']['value']=2
second=delivery.request(path)
assert second['nested']['value']==1 and len(api.calls)==1,'immutable repeated read charged/refetched or returned mutable alias'
second['nested']['value']=100;assert delivery.request(path)['nested']['value']==1
for suffix in ('git/ref/heads/state','rulesets/1','actions/runs/1','pulls/7','commits?path=x','git/blobs/'+'b'*40+'?query=x'):
 target='repos/org/repo/'+suffix;before=len(api.calls);delivery.request(target);api.value['nested']['value']+=1;result=delivery.request(target)
 assert len(api.calls)==before+2 and result['nested']['value']==api.value['nested']['value'],'mutable/query response cached'
for method,payload in [('POST',{}),('GET',{})]:
 before=len(api.calls);delivery.request(path,method,payload);delivery.request(path,method,payload);assert len(api.calls)==before+2
legacy,off=adapter(False);off.request(path);off.request(path);assert len(legacy.calls)==2,'legacy mode changed'
api,bounded=adapter()
for number in range(512):bounded.request('repos/org/repo/git/trees/'+f'{number:040x}')
try:bounded.request('repos/org/repo/git/trees/'+'f'*40)
except ValueError as error:assert 'API bound exceeded' in str(error)
else:raise AssertionError('unique request capacity enlarged')
assert len(api.calls)==512
assert bounded.request('repos/org/repo/git/trees/'+'0'*40)['nested']['value']==1
for target in ('repos/foreign/repo/git/blobs/'+'a'*40,'repos/org/repository/git/blobs/'+'a'*40):
 try:bounded.request(target)
 except ValueError:pass
 else:raise AssertionError('foreign API accepted')
api,large=adapter();api.value='x'*16000001
try:large.request(path)
except ValueError as error:assert 'byte bound exceeded' in str(error)
else:raise AssertionError('oversized immutable object cached')
config={'enabled':True,'queue_monitor_enabled':True,'repository':'org/repo','state_repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','grace_minutes':60}
storage={'state_branch':'factory-reporting-state','bootstrap_sha':'a'*40,'initialize':False,'policy_approvals':{},'state_view':{'mode':'archive','approval_path':'/private/tmp/queue-immutable-bootstrap.json'}}
api=API();store=q.QueueStore(api,config,storage)
first=store.request(path);first['nested']['value']=99;api.value['nested']['value']=2
assert store.request(path)['nested']['value']==1 and len(api.calls)==1,'QueueStore recharges immutable proof or aliases caller mutation'
for suffix in ('git/ref/heads/state','rulesets/1','actions/runs/1','pulls/7','git/blobs/'+'b'*40+'?query=x'):
 target='repos/org/repo/'+suffix;before=len(api.calls);store.request(target);api.value['nested']['value']+=1;assert store.request(target)['nested']['value']==api.value['nested']['value'] and len(api.calls)==before+2
for method,payload in [('POST',{}),('GET',{})]:
 before=len(api.calls);store.request(path,method,payload);store.request(path,method,payload);assert len(api.calls)==before+2
legacy=API();off=q.QueueStore(legacy,config,{k:v for k,v in storage.items() if k!='state_view'});off.request(path);off.request(path);assert len(legacy.calls)==2
api=API();store=q.QueueStore(api,config,storage)
for number in range(128):store.request('repos/org/repo/git/trees/'+f'{number:040x}')
try:store.request('repos/org/repo/git/trees/'+'f'*40)
except ValueError as error:assert 'API bound exceeded' in str(error)
else:raise AssertionError('QueueStore unique request bound enlarged')
assert len(api.calls)==128 and store.request('repos/org/repo/git/trees/'+'0'*40)['nested']['value']==1
print('actual queue adapter immutable isolation, mutable freshness, legacy mode, same-repo and unchanged unique-call/byte limits PASS')
PY
