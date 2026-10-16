#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-5: actual observed metadata diagnosis never changes failed enforcement."""
import sys
from pathlib import Path
sys.argv=['test',str(Path.cwd())]
fixture=Path('.claude/scripts/test/factory-coordinator.sh').read_text().split("<<'PY'\n",1)[1].split('def hidden_check',1)[0]
exec(compile(fixture,'coordinator-observation-fixture','exec'))
f=Hidden();f.metadata['name']='changed';audit=[]
try:m.coordinate(f,policy,42,observations=[observation],audit=audit)
except ValueError as error:assert str(error)=='observation metadata changed or foreign'
else:raise AssertionError('changed App metadata accepted')
assert len(audit)==1 and audit[0]['mode']=='rejected-observation', 'failed App view lost before audit append'
diag=audit[0]['diagnostic'];assert diag['metadata_sha256']!=observation['metadata_sha256']
assert diag['components']['name']['sha256']==hashlib.sha256(obs.canonical('changed')).hexdigest()
assert diag['expected_metadata_sha256']==observation['metadata_sha256'] and diag['ruleset_id']==1 and diag['repository_id']==42
assert diag['timestamps']['updated_at']['raw']==full_rules['updated_at']
assert diag['reason']=='validation-rejected' and len(obs.canonical(diag))<=8192
count=6
for key in obs.SEMANTIC:
 changed=copy.deepcopy(full_rules);changed.pop('bypass_actors');changed.pop(key)
 safe=obs.failure_diagnostic(repository,changed,observation)
 assert safe['components'][key]['status']=='missing' and safe['metadata_sha256'] is None;count+=1
# No actor values, transport/unknown fields or nested rule content can leak.
sentinel='DO_NOT_ECHO_DIAGNOSTIC_SENTINEL'
for value in ({'bypass_actors':[{'actor_id':sentinel}]},{'unknown':sentinel},{'rules':[{'unknown':sentinel}]},{'updated_at':sentinel}):
 changed=dict(full_rules,**value);safe=obs.failure_diagnostic(repository,changed,observation)
 assert sentinel not in json.dumps(safe);count+=1
huge=dict(full_rules,rules=[{'large':'x'*(obs.MAX_BYTES+1)}])
assert obs.failure_diagnostic(repository,huge,observation)['reason']=='diagnostic-unavailable';count+=1
# Construction budget covers queued frontier, not just eventually visited nodes.
import tracemalloc
wide=dict(full_rules,rules=[{f'k{i:04d}':0 for i in range(8192)}])
tracemalloc.start()
try:
 assert obs.failure_diagnostic(repository,wide,observation)['reason']=='diagnostic-unavailable'
 peak=tracemalloc.get_traced_memory()[1]
finally:tracemalloc.stop()
assert peak < 524288, ('oversized diagnostic frontier allocated',peak)
count+=1
nested=[];nested.append(nested)
assert obs.failure_diagnostic(repository,dict(full_rules,rules=nested),observation)['reason']=='diagnostic-unavailable';count+=1
# Timestamp strings are diagnostic facts only; equivalent spellings still reject.
alternative=copy.deepcopy(full_rules);alternative.pop('bypass_actors');alternative['updated_at']=obs.timestamp(full_rules['updated_at']).isoformat().replace('+00:00','Z')
safe=obs.failure_diagnostic(repository,alternative,observation)
assert safe['timestamps']['updated_at']['raw']==alternative['updated_at'];count+=1
try:obs.validate(repository,alternative,observation)
except ValueError:pass
else:raise AssertionError('timestamp diagnostics relaxed exact enforcement')
# Actual CLI failure path must still replace prior same-head eligible success.
import tempfile,contextlib
with tempfile.TemporaryDirectory() as temp:
 directory=Path(temp);pp=directory/'policy.json';pp.write_text(json.dumps(policy));ip=directory/'observations.json';ip.write_text(json.dumps({'schema_version':1,'repository':policy['repository'],'observations':[observation]}))
 output=directory/'receipt.json';ap=directory/'audit.json';fake=Hidden();fake.metadata['name']='changed'
 original_api=m.GitHub;original_args=sys.argv[:]
 try:
  m.GitHub=lambda repository:fake;sys.argv=['coordinator','--policy',str(pp),'--pr','42','--merge','--output',str(output),'--policy-observations',str(ip),'--policy-audit',str(ap)]
  for break_diagnostic in (False,True):
   original=m.policy_observation.failure_diagnostic
   if break_diagnostic:m.policy_observation.failure_diagnostic=lambda *args:(_ for _ in ()).throw(RuntimeError('diagnostic failed'))
   try:
    try:m.main()
    except ValueError as error:assert str(error)=='observation metadata changed or foreign'
    else:raise AssertionError('failed observation accepted')
   finally:m.policy_observation.failure_diagnostic=original
   failed=[call[1] for call in fake.calls if isinstance(call,tuple) and call[0].endswith('/check-runs')]
   assert failed[-1]['conclusion']=='failure' and failed[-1]['head_sha']==head and not output.exists();count+=1
   assert len(ap.read_bytes())<=obs.MAX_BYTES and sentinel not in ap.read_text()
 finally:m.GitHub=original_api;sys.argv=original_args
print(f'{count} bounded failed-observation diagnostic cases passed; enforcement unchanged')
PY
