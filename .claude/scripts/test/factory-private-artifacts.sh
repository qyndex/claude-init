#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import fcntl,hashlib,importlib.util,json,os,subprocess,sys,tempfile,time
root=Path(sys.argv[1]);helper=root/'.claude/scripts/factory-bounded-process.py';assert helper.exists(),'streaming private artifact bounds absent'
def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
bounded=module('bounded',helper);artifacts=module('artifacts',root/'.claude/scripts/factory-private-artifacts.py');sup=module('sup',root/'.claude/scripts/factory-supervisor.py')
def rejects(fn):
 try:fn()
 except (ValueError,OSError):return
 raise AssertionError('unsafe private artifact operation accepted')
with tempfile.TemporaryDirectory() as temporary:
 base=Path(temporary).resolve();private=base/'private';private.mkdir(mode=0o700);candidate=base/'candidate';candidate.mkdir();attempts=private/'attempts';attempts.mkdir(mode=0o700);database=private/'runtime.sqlite';store=sup.runtime.Store(database);database.chmod(0o600)
 env={'PATH':os.defpath}
 normal=bounded.run([sys.executable,'-c','print("complete")'],env=env,cwd=base,timeout=2,limit=1024);assert normal.returncode==0 and normal.stdout==b'complete\n'
 for script in ('import sys;sys.stdout.write("x"*10000000)','import sys;sys.stderr.write("x"*10000000)','import time;time.sleep(10)'):
  started=time.monotonic();rejects(lambda:bounded.run([sys.executable,'-c',script],env=env,cwd=base,timeout=.5,limit=1024));assert time.monotonic()-started<3
 print('AC-1: real stdout/stderr floods and timeout are bounded during collection; complete subprocess output remains intact')
 for task,script,timeout,success in [('T-1','import sys;sys.stdout.write("x"*10000000)',5,False),('T-2','print("complete")',5,True),('T-3','import os,time;pid=os.fork();time.sleep(20) if pid==0 else None',1,False)]:
  store.enqueue(task,'a'*64,[]);code=sup.supervise(database,task,[sys.executable,'-c',script],candidate,attempts,timeout=timeout,lease=3,resources={'output_limit_bytes':4096})
  assert (code==0)==success and store.get(task)['state']==('verifying' if success else 'blocked')
  directory=next(attempts.glob(task+'-*'));log=directory/'worker.log';assert log.stat().st_size<=4096 and log.stat().st_mode&0o777==0o600
  outcome=json.loads((directory/'guardian.json').read_text());assert outcome['worker_cleanup_confirmed'] is True
  if task=='T-1':assert outcome['reason']=='output-limit' and log.stat().st_size==4096
 print('AC-2: actual worker floods block verification at exact log bound, complete output succeeds, and descendant-held output times out with confirmed cleanup')
 rejects(lambda:artifacts.metrics(store,'fixture/artifacts'))
 store.enqueue('T-9','a'*64,[]);token=store.claim('T-9','owner',100);identity={'repository':'fixture/artifacts','namespace':f'T-9-{token}-'+('a'*32),'name':'factory-'+('b'*32),'image':'sha256:'+('c'*64)};store.register_worker_effect('T-9','owner',token,identity['name'],identity)
 metrics=artifacts.metrics(store,'fixture/artifacts');assert set(metrics)=={'schema_version','repository','runtime_states','unresolved_worker_effects','engineering_verified'} and metrics['engineering_verified'] is False and metrics['unresolved_worker_effects']==1
 rejects(lambda:artifacts.metrics(store,'foreign/repo'));assert 'owner' not in json.dumps(metrics) and 'argv' not in json.dumps(metrics)
 rejects(lambda:artifacts.retain(store,'fixture/artifacts',candidate,1));assert database.exists()
 print('AC-3: unbound/foreign stores and nonprivate paths reject; public-eligible output contains sanitized aggregate counts only and never certifies engineering verification')
 store.enqueue('T-10','a'*64,[]);action_token=store.claim('T-10','action-owner',100)
 store.transition('T-10','action-owner',action_token,'implementing',action=('pending-effect',{'kind':'fixture'}));store.transition('T-10','action-owner',action_token,'blocked')
 action_dir=attempts/(f'T-10-{action_token}-'+('e'*32));action_dir.mkdir(mode=0o700);(action_dir/'outcome.json').write_text(json.dumps({'task':'T-10','fence':action_token}));(action_dir/'guardian.json').write_text(json.dumps({'worker_cleanup_confirmed':True}))
 old=time.time()-3*86400
 for directory in attempts.iterdir():
  if (directory/'outcome.json').exists():os.utime(directory/'outcome.json',(old,old))
 # Uncertain effects/actions, active task locks and unsafe directory contents stay retained.
 unknown=attempts/identity['namespace'];unknown.mkdir(mode=0o700);(unknown/'outcome.json').write_text(json.dumps({'task':'T-9','fence':token}));(unknown/'guardian.json').write_text(json.dumps({'worker_cleanup_confirmed':True}));os.utime(unknown/'outcome.json',(old,old));store.recover_worker('T-9','owner',token,requeue=False)
 protected=private/'keep-secret';protected.write_text('PRIVATE CANARY');protected.chmod(0o600);(attempts/('T-77-1-'+('d'*32))).symlink_to(private,target_is_directory=True)
 first=next(attempts.glob('T-1-*'));lock=database.parent/('worker-'+hashlib.sha256(b'T-1').hexdigest()+'.lock')
 with lock.open('a+b') as holder:
  fcntl.flock(holder.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB);dry=artifacts.retain(store,'fixture/artifacts',attempts,1);assert dry['eligible_attempts']==1 and dry['deleted_attempts']==0 and first.exists()
 (first/'unsafe').symlink_to(protected);assert artifacts.retain(store,'fixture/artifacts',attempts,1,apply=True)['deleted_attempts']==1 and first.exists();(first/'unsafe').unlink()
 os.link(protected,first/'hardlinked-secret');assert artifacts.retain(store,'fixture/artifacts',attempts,1,apply=True)['deleted_attempts']==0 and first.exists();(first/'hardlinked-secret').unlink()
 assert artifacts.retain(store,'fixture/artifacts',attempts,1,apply=True)['deleted_attempts']==1 and not first.exists()
 assert artifacts.retain(store,'fixture/artifacts',attempts,1,apply=True)['deleted_attempts']==0 and unknown.exists() and action_dir.exists() and next(attempts.glob('T-2-*')).exists() and protected.read_text()=='PRIVATE CANARY' and database.exists()
 assert artifacts.metrics(store,'fixture/artifacts')['unresolved_worker_effects']==1
 print('RETENTION-PASS: real dry-run/apply retention preserves locks, active tasks, uncertainty, symlinks, secrets and SQLite while deleting only old clean terminal namespaces; replay is idempotent')
PYTEST
