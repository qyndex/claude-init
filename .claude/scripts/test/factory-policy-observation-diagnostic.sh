#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-5: actual observed metadata diagnosis never changes failed enforcement."""
import sys,os
from pathlib import Path
sys.argv=['test',str(Path.cwd())]
fixture=Path('.claude/scripts/test/factory-coordinator.sh').read_text().split("<<'PY'\n",1)[1].split('def hidden_check',1)[0]
exec(compile(fixture,'coordinator-observation-fixture','exec'))
count=0
def check(condition):
 global count
 assert condition
 count+=1
def unexpected_case():
 fake=Hidden();audit=[];original=m.policy_observation.validate
 failure=RuntimeError('DO_NOT_ECHO_UNEXPECTED_SENTINEL')
 def raises(*args,**kwargs):raise failure
 try:
  m.policy_observation.validate=raises
  try:m.coordinate(fake,policy,42,observations=[observation],audit=audit)
  except RuntimeError as error:assert error is failure
  else:raise AssertionError('unexpected validation failure accepted')
 finally:m.policy_observation.validate=original
 check(len(audit)==1 and audit[0]['mode']=='rejected-observation')
 check(audit[0]['diagnostic']['reason']=='validation-rejected' and audit[0]['rejection']=='unexpected-validation-error')
 check('DO_NOT_ECHO_UNEXPECTED_SENTINEL' not in json.dumps(audit))
if os.environ.get('T304_ONLY')=='unexpected':
 unexpected_case();print('unexpected exception audit cases passed');raise SystemExit(0)
# AC-5: coordinator must preserve bounded diagnostic unavailability separately.
for hostile in ('oversized','cyclic'):
 fake=Hidden();audit=[]
 if hostile=='oversized':fake.metadata['rules']=[{'large':'x'*(obs.MAX_BYTES+1)}]
 else:
  cycle=[];cycle.append(cycle);fake.metadata['rules']=cycle
 original=m.policy_observation.validate;failures=[]
 def retain_error(*args,**kwargs):
  try:return original(*args,**kwargs)
  except Exception as error:failures.append(error);raise
 try:
  m.policy_observation.validate=retain_error
  try:m.coordinate(fake,policy,42,observations=[observation],audit=audit)
  except Exception as error:check(len(failures)==1 and error is failures[0])
  else:raise AssertionError('hostile metadata accepted')
 finally:m.policy_observation.validate=original
 check(len(audit)==1 and audit[0]['diagnostic']=={'schema_version':1,'reason':'diagnostic-unavailable'})
 check(audit[0]['rejection']==obs.rejection_category(failures[0]))
f=Hidden();f.metadata['name']='changed';audit=[]
try:m.coordinate(f,policy,42,observations=[observation],audit=audit)
except ValueError as error:assert str(error)=='observation metadata changed or foreign'
else:raise AssertionError('changed App metadata accepted')
check(len(audit)==1 and audit[0]['mode']=='rejected-observation')
diag=audit[0]['diagnostic'];check(diag['metadata_sha256']!=observation['metadata_sha256'])
check(diag['components']['name']['sha256']==hashlib.sha256(obs.canonical('changed')).hexdigest())
check(diag['expected_metadata_sha256']==observation['metadata_sha256'] and diag['ruleset_id']==1 and diag['repository_id']==42)
check(diag['timestamps']['updated_at']['raw']==full_rules['updated_at'])
check(diag['expected_updated_at']['raw']==observation['updated_at'])
check(diag['matches']=={'repository':True,'repository_id':True,'ruleset_id':True,'metadata_sha256':False,'updated_at_raw':True,'updated_at_instant':True})
check(diag['reason']=='validation-rejected' and audit[0]['rejection']=='metadata-mismatch' and len(obs.canonical(diag))<=8192)
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
# Timestamp strings are diagnostic facts only; raw spelling is distinct from accepted semantic equality.
alternative=copy.deepcopy(full_rules);alternative.pop('bypass_actors');alternative['updated_at']=obs.timestamp(full_rules['updated_at']).isoformat().replace('+00:00','Z')
safe=obs.failure_diagnostic(repository,alternative,observation)
assert safe['timestamps']['updated_at']['raw']==alternative['updated_at'];count+=1
assert obs.validate(repository,alternative,observation);count+=1
# Actual CLI failure path must still replace prior same-head eligible success.
import tempfile
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
unexpected_case()
for message,category in [('complete observation required','observation-incomplete'),('observation schema invalid','observation-schema'),('observation unsettled or future','observation-clock'),('DO_NOT_ECHO_CATEGORY_SENTINEL','unexpected-validation-error')]:
 check(obs.rejection_category(ValueError(message))==category)
for expected in ('DO_NOT_ECHO_EXPECTED_SENTINEL','x'*41,None):
 malformed=dict(observation,updated_at=expected,repository_id=True)
 safe=obs.failure_diagnostic(repository,full_rules,malformed)
 check(safe['expected_updated_at']=={'status':'invalid'} and safe['matches']['repository_id'] is None and safe['matches']['updated_at_raw'] is None and safe['matches']['updated_at_instant'] is None)
 check('DO_NOT_ECHO_EXPECTED_SENTINEL' not in json.dumps(safe))
# The allocation threshold above is a CPython resource regression, not a timing benchmark.
print(f'{count} bounded failed-observation diagnostic cases passed; strict authority checks retained')
PY
