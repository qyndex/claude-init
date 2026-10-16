#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-5: actual cross-caller time spelling must preserve exact supported instants."""
import copy,datetime,json,importlib.util
from pathlib import Path
s=importlib.util.spec_from_file_location('obs','.claude/scripts/factory-policy-observation.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
f=json.loads(Path('.claude/scripts/test/fixtures/factory-policy-equivalent-time.json').read_text());repo=f['repository'];operator=f['operator'];anonymous=f['anonymous'];now=m.timestamp(f['now']);count=0
assert f['actual_app_view'] is False and f['native_attestation'] is False
assert sorted(k for k in m.SEMANTIC if operator[k]!=anonymous[k])==['created_at','updated_at']
original=copy.deepcopy(f);fresh=m.capture(repo,operator,now=now)
assert m.validate(repo,anonymous,fresh,now=now)['mode']=='operator-observation';count+=1
assert m.identity(repo,operator)==m.identity(repo,anonymous);count+=1
assert fresh['metadata_sha256']!=f['operator_legacy_sha256'];count+=1
assert f==original;count+=1
def reject(call):
 global count
 try:call()
 except ValueError:count+=1;return
 raise AssertionError('changed/unsupported policy instant accepted')
legacy=dict(fresh,metadata_sha256=f['operator_legacy_sha256']);reject(lambda:m.validate(repo,anonymous,legacy,now=now))
hidden=copy.deepcopy(operator);hidden.pop('bypass_actors');reject(lambda:m.validate(repo,hidden,legacy,now=now))
for field in ('created_at','updated_at'):
 changed=copy.deepcopy(anonymous);changed[field]=(m.timestamp(changed[field])+datetime.timedelta(microseconds=1)).isoformat();reject(lambda changed=changed:m.validate(repo,changed,fresh,now=now))
changed=dict(fresh,updated_at=(m.timestamp(fresh['updated_at'])+datetime.timedelta(microseconds=1)).isoformat());reject(lambda:m.validate(repo,anonymous,changed,now=now))
for field in ('created_at','updated_at'):
 for value in ('2026-10-16T00:49:11.5570001Z','2026-10-16T00:49:11.5570000Z','2026-10-16T00:49:11+24:00','2026-10-16T00:49:11+00:60','2026-10-16T00:49:11+05:99','2026-10-16T00:49:11','2026-02-30T00:49:11Z'):
  changed=dict(anonymous,**{field:value});reject(lambda changed=changed:m.validate(repo,changed,fresh,now=now))
for field in ('updated_at','observed_at'):
 changed=dict(fresh,**{field:'2026-10-16T00:49:11.5570001Z'});reject(lambda changed=changed:m.validate(repo,anonymous,changed,now=now))
changed=copy.deepcopy(anonymous);changed['name']+=' altered';reject(lambda:m.validate(repo,changed,fresh,now=now))
# Fractional settle must preserve a one-microsecond boundary; no epoch floats.
near=copy.deepcopy(operator);near['updated_at']=(now-datetime.timedelta(seconds=60)+datetime.timedelta(microseconds=1)).isoformat()
reject(lambda:m.capture(repo,near,now=now))
assert m.capture(repo,near,now=now+datetime.timedelta(microseconds=1));count+=1
updated=m.timestamp(anonymous['updated_at'])
for when in (updated+datetime.timedelta(seconds=60)-datetime.timedelta(microseconds=1),now+datetime.timedelta(microseconds=1)):
 changed=dict(fresh,observed_at=when.isoformat());reject(lambda changed=changed:m.validate(repo,anonymous,changed,now=now))
# An alternate valid offset is the same instant, without mutating raw source data.
alternative=copy.deepcopy(anonymous)
for field in ('created_at','updated_at'):alternative[field]=m.timestamp(alternative[field]).astimezone(datetime.timezone(datetime.timedelta(hours=5,minutes=30))).isoformat(timespec='microseconds')
assert m.validate(repo,alternative,fresh,now=now);count+=1
safe=m.failure_diagnostic(repo,anonymous,fresh)
assert safe['timestamps']['updated_at']['raw']==anonymous['updated_at'] and safe['expected_updated_at']['raw']==operator['updated_at'];count+=1
assert safe['matches']['updated_at_raw'] is False and safe['matches']['updated_at_instant'] is True and safe['matches']['metadata_sha256'] is True;count+=1
print(f'{count} actual snapshot/time-equivalence/precision/settle cases passed; actual App view pending')
PY
