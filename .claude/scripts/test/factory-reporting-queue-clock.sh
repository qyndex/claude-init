#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PYTEST'
"""Metadata read after observation entry must use the actual read-time future bound."""
from pathlib import Path
source=Path('.claude/scripts/test/factory-reporting-queue-observation.sh').read_text().split("python3 - <<'PY'\n",1)[1].split('count=0\nwith tempfile',1)[0]
exec(compile(source,'queue-clock-fixture','exec'))
class Clock(datetime):
 @classmethod
 def now(cls,tz=None):return wall.astimezone(tz) if tz else wall.replace(tzinfo=None)
q.datetime=Clock
now=Clock(2026,10,15,22,tzinfo=timezone.utc);wall=now+timedelta(seconds=5)
with tempfile.TemporaryDirectory() as temp:
 api=API();storage={'state_branch':'factory-reporting-state','bootstrap_sha':api.head,'initialize':False,'policy_approvals':{}}
 hc=ns['config'];state=ns['m'];store=state.HostedDigest(Path(temp)/'worker',hc,state.GitState(api,hc['state_branch'],ns['stream'],hc['bootstrap_sha']))
 batch=store.prepare(ns['ReportAPI'](),state.slack.due(now));store.deliver(batch['key'],ns['Transport']());api.readonly=True;before=api.head
 # API metadata became current two seconds after the captured observation entry.
 api.runs=[dict(copy.deepcopy(run),updated_at=(now+timedelta(seconds=2)).isoformat())]
 result=q.observe_queue(api,config,storage,now)
 assert result['status']=='metadata-current' and not result['stalled'] and result['coverage_complete'],result
 assert api.head==before and result['receipt_verified'] is False and result['recovery_eligible'] is False
 # No skew allowance: one microsecond beyond actual wallclock remains unknown.
 api.runs[0]['updated_at']=(wall+timedelta(microseconds=1)).isoformat()
 result=q.observe_queue(api,config,storage,now)
 assert result['status']=='unknown' and result['reason']=='metadata-clock-invalid' and not result['coverage_complete'],result
 # Existing within-run chronology is still enforced independently.
 api.runs[0].update(created_at='2026-10-15T21:59:00Z',updated_at='2026-10-15T21:58:59Z')
 result=q.observe_queue(api,config,storage,now)
 assert result['status']=='unknown' and result['reason']=='metadata-clock-invalid',result
 assert api.head==before
print('3 captured-clock/read-time/future/chronology controls passed; no live observation')
PYTEST
