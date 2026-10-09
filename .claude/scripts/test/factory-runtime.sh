#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "${RUNTIME_TEST_ROOT:-$ROOT}" <<'PY'
import concurrent.futures
import importlib.util
import multiprocessing
from pathlib import Path
import sys
import tempfile

path=Path(sys.argv[1])/'.claude/scripts/factory-runtime.py'
assert path.is_file(), 'transactional runtime store not implemented'
spec=importlib.util.spec_from_file_location('runtime',path)
runtime=importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)

def rejects(fn):
    try: fn()
    except (ValueError, TypeError, runtime.Blocked): return
    raise AssertionError('expected rejection')

def race(args):
    db, owner=args
    try: return runtime.Store(db).claim('T-2',owner,10,now=100)
    except runtime.Blocked: return None

with tempfile.TemporaryDirectory() as tmp:
    db=str(Path(tmp)/'runtime.sqlite')
    s=runtime.Store(db)
    revision='a'*64
    s.enqueue('T-1',revision,[]); s.enqueue('T-2',revision,['T-1'])
    rejects(lambda:s.claim('T-2','early',10,now=100))
    a=s.claim('T-1','first',10,now=100)
    rejects(lambda:s.heartbeat('T-1','other',a,10,now=101))
    rejects(lambda:s.transition('T-1','first',a,'merged',now=101))
    for state in ('implementing','verifying','merge-ready','merging','merged'):
        s.transition('T-1','first',a,state,now=101)
    with concurrent.futures.ProcessPoolExecutor(max_workers=4, mp_context=multiprocessing.get_context("fork")) as pool:
        tokens=list(pool.map(race,[(db,str(i)) for i in range(8)]))
    assert len([x for x in tokens if x is not None])==1
    task=s.get('T-2'); old=task['fence']; owner=task['owner']
    rejects(lambda:s.heartbeat('T-2',owner,old,10,now=110))
    s=runtime.Store(db); new=s.claim('T-2','recovered',10,now=111)
    assert new>old
    rejects(lambda:s.transition('T-2',owner,old,'implementing',now=112))
    s.pause(True); rejects(lambda:s.claim('T-2','paused',10,now=122)); s.pause(False)
    s.transition('T-2','recovered',new,'implementing',now=112)
    rejects(lambda:s.enqueue('T-2','b'*64,[]))
    rejects(lambda:s.enqueue('T-3','bad',[]))
    rejects(lambda:s.enqueue('T-3',revision,['unknown']))
    rejects(lambda:s.transition('T-2','recovered',new,'verifying',action=('k',{'x':object()}),now=112))
    assert s.get('T-2')['state']=='implementing'
    s.transition('T-2','recovered',new,'verifying',action=('pr:T-2:1',{'operation':'create-pr'}),now=112)
    s.transition('T-2','recovered',new,'repairing',now=112)
    s.transition('T-2','recovered',new,'verifying',action=('pr:T-2:1',{'operation':'create-pr'}),now=112)
    rejects(lambda:s.transition('T-2','recovered',new,'repairing',action=('pr:T-2:1',{'operation':'different'}),now=112))
    assert s.get('T-2')['state']=='verifying'
    assert len(s.actions())==1
    action=s.dispatch('pr:T-2:1','sender',5,now=112)
    assert action['status']=='dispatching'
    rejects(lambda:s.dispatch('pr:T-2:1','duplicate',5,now=113))
    s=runtime.Store(db); s.recover_actions(now=117)
    assert s.actions()[0]['status']=='uncertain'
    rejects(lambda:s.dispatch('pr:T-2:1','duplicate',5,now=118))
    rejects(lambda:s.confirm('pr:T-2:1','sender',{'pr':52},now=118))
    s.reconcile('pr:T-2:1',{'pr':52},remote_absent=False)
    s=runtime.Store(db); assert s.actions()[0]['status']=='confirmed'
    rejects(lambda:s.reconcile('pr:T-2:1',{'pr':53},remote_absent=False))
    s.transition('T-2','recovered',new,'repairing',now=113)
    s.transition('T-2','recovered',new,'verifying',now=113)
    rejects(lambda:s.transition('T-2','recovered',new,'repairing',now=113))
    s.cancel('T-2'); rejects(lambda:s.heartbeat('T-2','recovered',new,10,now=113))
    s.enqueue('T-4',revision,[])
    for i in range(3): s.claim('T-4','retry',1,now=200+i*2)
    rejects(lambda:s.claim('T-4','retry',1,now=206))
    assert s.get('T-4')['attempt']==3
    s.enqueue('T-5',revision,[]); token=s.claim('T-5','owner',20,now=300)
    s.transition('T-5','owner',token,'implementing',action=('effect',{'operation':'test'}),now=301)
    s.dispatch('effect','sender',2,now=301); s.recover_actions(now=303)
    rejects(lambda:s.reconcile('effect',None,remote_absent=False))
    s.reconcile('effect',None,remote_absent=True)
    assert s.dispatch('effect','sender2',5,now=304)['status']=='dispatching'
    s.confirm('effect','sender2',{'receipt':'ok'},now=305)
    assert runtime.Store(db).actions()[1]['result']=={'receipt':'ok'}
print('factory-runtime: AC-1 through AC-4 passed (race, fencing, recovery, outbox and rollback)')
PY
