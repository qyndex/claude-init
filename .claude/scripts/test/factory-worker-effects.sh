#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import concurrent.futures,importlib.util,tempfile,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('runtime',Path(sys.argv[1])/'.claude/scripts/factory-runtime.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
assert callable(getattr(m.Store,'register_worker_effect',None)), 'durable external worker-effect fence absent'
def rejects(fn):
    try:fn()
    except (ValueError,TypeError,m.Blocked):return
    raise AssertionError('unsafe external effect accepted')
with tempfile.TemporaryDirectory() as temporary:
    path=Path(temporary)/'state.sqlite';store=m.Store(path);store.enqueue('T-1','a'*64,[]);fence=store.claim('T-1','guardian',10,now=100);store.transition('T-1','guardian',fence,'implementing',now=101)
    identity={'repository':'org/repo','namespace':'T-1-1-'+'a'*32,'name':'factory-'+'b'*32,'image':'sha256:'+'c'*64}
    store.register_worker_effect('T-1','guardian',fence,'effect-1',identity,now=102)
    store.register_worker_effect('T-1','guardian',fence,'effect-1',identity,now=102)
    reopened=m.Store(path);assert len(reopened.worker_effects('T-1'))==1
    changed={**identity,'name':'factory-'+'d'*32};rejects(lambda:store.register_worker_effect('T-1','guardian',fence,'effect-1',changed,now=102))
    rejects(lambda:store.register_worker_effect('T-1','foreign',fence,'effect-2',identity,now=102))
    print('AC-1: external effect intent is durable before dispatch, immutable and idempotent, and registration requires exact current task owner/fence')
    rejects(lambda:reopened.claim('T-1','new',10,now=111))
    rejects(lambda:reopened.recover_worker('T-1','guardian',fence,requeue=True))
    rejects(lambda:store.transition('T-1','guardian',fence,'verifying',now=103))
    assert store.get('T-1')['fence']==fence
    print('AC-2: unresolved daemon effects block expired-lease reclaim, successful worker verification and guardian requeue; unknown cleanup cannot grant another attempt')
    receipt={'schema_version':1,'adapter':'docker-offline','effect_id':'effect-1','identity':identity,'observed_absent':True}
    for invalid in [{**receipt,'observed_absent':False},{**receipt,'identity':changed},{**receipt,'adapter':'unknown'},{**receipt,'schema_version':True}]:rejects(lambda invalid=invalid:store.confirm_worker_effect_cleanup('T-1','guardian',fence,invalid))
    store.confirm_worker_effect_cleanup('T-1','guardian',fence,receipt)
    store.confirm_worker_effect_cleanup('T-1','guardian',fence,receipt)
    def race(index):
        try:return m.Store(path).claim('T-1',f'new-{index}',10,now=111)
        except m.Blocked:return None
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:tokens=list(pool.map(race,range(8)))
    assert len([token for token in tokens if token is not None])==1 and max(token for token in tokens if token is not None)>fence
    rejects(lambda:store.register_worker_effect('T-1','guardian',fence,'effect-2',identity,now=112))
    print('AC-3: only exact adapter/identity absent receipts release the fence; cleanup confirmation is idempotent and stale owners cannot create effects after reclaim')
    store.enqueue('T-2','a'*64,[]);f2=store.claim('T-2','second',10,now=200);store.transition('T-2','second',f2,'implementing',now=201)
    store.register_worker_effect('T-2','second',f2,'effect-2',{**identity,'namespace':'T-2-1-'+'e'*32},now=202)
    assert store.recover_worker('T-2','second',f2,requeue=False) is True
    rejects(lambda:store.claim('T-2','retry',10,now=220))
    assert store.get('T-2')['state']=='blocked' and store.worker_effects('T-2')[0]['status']=='uncertain'
    blocked_receipt={**receipt,'effect_id':'effect-2','identity':{**identity,'namespace':'T-2-1-'+'e'*32}}
    store.confirm_worker_effect_cleanup('T-2','second',f2,blocked_receipt)
    assert store.get('T-2')['state']=='blocked' and store.worker_effects('T-2')[0]['status']=='clean'
    rejects(lambda:store.claim('T-2','retry',10,now=221))
    store.enqueue('T-3','a'*64,[]);assert store.claim('T-3','unrelated',10,now=220)>0
    rejects(lambda:store.register_worker_effect('T-3','unrelated',1,'foreign-effect',{**identity,'repository':'foreign/repo','namespace':'T-3-1-'+'f'*32},now=221))
    store.transition('T-3','unrelated',1,'implementing',now=221)
    third={**identity,'namespace':'T-3-1-'+'f'*32}
    store.register_worker_effect('T-3','unrelated',1,'third-effect',third,now=222)
    store.cancel('T-3')
    store.confirm_worker_effect_cleanup('T-3','unrelated',1,{**receipt,'effect_id':'third-effect','identity':third})
    assert store.get('T-3')['state']=='cancelled'
    print('AC-4: unknown effects remain durably visible after blocked recovery, unrelated tasks retain native semantics, and no synthetic receipt claims live daemon cleanup or independent verification')
PY
