#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-7: strict isolated queue identities and safe durable-intent states."""
import copy,hashlib,importlib.util,json
from pathlib import Path
path=Path('.claude/scripts/factory-reporting-queue.py')
assert path.exists(),'isolated queue journal validator is absent'
spec=importlib.util.spec_from_file_location('queue_probe',path);q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
config={'enabled':True,'queue_monitor_enabled':True,'repository':'org/repo','state_repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','grace_minutes':60}
assert q.validate_config(config,repository='org/repo',default_branch='main')==config
stream=q.stream(config);assert stream==hashlib.sha256(q.canonical(['factory-reporting-queue-v1','org/repo','C1','main'])).hexdigest()
assert stream!=hashlib.sha256(q.canonical(['org/repo','C1','main'])).hexdigest()
def event(kind='stalled',status='pending',incident=None):
 row={'kind':kind,'run_id':70 if kind!='recovery' else None,'run_attempt':1 if kind!='recovery' else None,'cutoff':'2026-10-15T00:00:00.000000Z','status':status,'message_id':'100.000001' if status=='confirmed' else None,'incident':incident}
 row['key']=q.event_key(stream,row);row['incident']=incident or row['key'];return row
journal={'schema_version':1,'repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','stream':stream,'events':[event()]}
count=3
def rejects(fn):
 global count
 try:fn()
 except ValueError:count+=1;return
 raise AssertionError('unsafe queue state accepted')
assert q.validate_journal(journal,config)==journal;count+=1
assert q.load_journal(q.canonical(journal),config)==journal;count+=1
for field,value in [('enabled',1),('queue_monitor_enabled','true'),('repository','other/repo'),('state_repository','other/repo'),('branch','feature'),('destination','not-channel'),('team_id','not-team'),('grace_minutes',True),('grace_minutes',14),('grace_minutes',1441),('unknown',True)]:
 bad=dict(config,**{field:value});rejects(lambda bad=bad:q.validate_config(bad,repository='org/repo',default_branch='main'))
for field,value in [('schema_version',True),('repository','foreign/repo'),('branch','other'),('destination','C2'),('team_id','T2'),('stream','0'*64),('unknown',{'raw':'private'})]:
 bad=copy.deepcopy(journal);bad[field]=value;rejects(lambda bad=bad:q.validate_journal(bad,config))
for field,value in [('run_id',True),('run_attempt',0),('key','0'*64),('incident','f'*64),('status','sent'),('message_id','123.1'),('cutoff','2026-10-15T00:00:00Z'),('cutoff','9999-01-01T00:00:00.000000Z'),('unknown',{'sql':'select private'})]:
 bad=copy.deepcopy(journal);bad['events'][0][field]=value;rejects(lambda bad=bad:q.validate_journal(bad,config))
confirmed=event(status='confirmed');recovery=event('recovery',incident=confirmed['key'])
closed=dict(journal,events=[confirmed,recovery]);assert q.validate_journal(closed,config)==closed;count+=1
uncertain=copy.deepcopy(journal);uncertain['events'][0]['status']='uncertain';assert q.validate_journal(uncertain,config)==uncertain;count+=1
for rows in ([event(),event()], [event('recovery',incident='a'*64)], [event(),event('recovery',incident=journal['events'][0]['key'])], [confirmed,recovery,recovery]):
 rejects(lambda rows=rows:q.validate_journal(dict(journal,events=rows),config))
bad=copy.deepcopy(journal);bad['events'][0]['status']='confirmed';rejects(lambda:q.validate_journal(bad,config))
bad=copy.deepcopy(uncertain);bad['events'][0]['message_id']='123.000001';rejects(lambda:q.validate_journal(bad,config))
rejects(lambda:q.load_journal(b'{"schema_version":1,"schema_version":1}',config))
rejects(lambda:q.load_journal(b'x'*(q.MAX_BYTES+1),config))
rejects(lambda:q.validate_journal(dict(journal,events=[event()]*(q.MAX_EVENTS+1)),config))
# Bounded typed shape must reject hostile objects before expensive JSON traversal.
cycle=[];cycle.append(cycle);rejects(lambda:q.validate_journal(dict(journal,events=cycle),config))
class Bomb:
 def __iter__(self):raise AssertionError('untrusted object traversed')
rejects(lambda:q.validate_journal(dict(journal,events=[Bomb()]),config))
rejects(lambda:q.validate_journal(dict(journal,unknown='x'*(q.MAX_BYTES+1)),config))
# Stable logical identity ignores a repeated observation's cutoff.
changed=copy.deepcopy(confirmed);changed['cutoff']='2026-10-15T01:00:00.000000Z'
assert q.event_key(stream,changed)==confirmed['key'];count+=1
rejects(lambda:q.validate_journal(dict(journal,events=[confirmed,changed]),config))
early=copy.deepcopy(recovery);early['cutoff']='2026-10-14T00:00:00.000000Z'
rejects(lambda:q.validate_journal(dict(journal,events=[confirmed,early]),config))
closed_recovery=copy.deepcopy(recovery);closed_recovery.update(status='confirmed',message_id='101.000001')
later=copy.deepcopy(recovery);later.update(cutoff='2026-10-15T01:00:00.000000Z',key='f'*64)
rejects(lambda:q.validate_journal(dict(journal,events=[confirmed,closed_recovery,later]),config))
later['key']=q.event_key(stream,later)
rejects(lambda:q.validate_journal(dict(journal,events=[confirmed,closed_recovery,later]),config))
for branch in ('main/../x','main/','main\nother'):
 bad=dict(config,branch=branch)
 rejects(lambda bad=bad,branch=branch:q.validate_config(bad,repository='org/repo',default_branch=branch))
rejects(lambda:q.load_journal(b'['*2000+b']'*2000,config))
# Python caller objects cannot execute equality hooks inside this data boundary.
class EqualityBomb:
 def __eq__(self,other):raise AssertionError('unsafe equality invoked')
for field in ('repository','state_repository','branch'):
 bad=dict(config,**{field:EqualityBomb()})
 rejects(lambda bad=bad:q.validate_config(bad,repository='org/repo',default_branch='main'))
bad=copy.deepcopy(journal);bad['stream']=EqualityBomb();rejects(lambda:q.validate_journal(bad,config))
bad=copy.deepcopy(journal);bad['events'][0]['incident']=EqualityBomb();rejects(lambda:q.validate_journal(bad,config))
print(f'{count} queue journal identity/schema/state/budget cases passed; no IO or delivery')
PY
