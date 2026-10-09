#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "${LEDGER_TEST_ROOT:-$ROOT}" <<'PY'
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root=Path(sys.argv[1]); scripts=root/'.claude/scripts'
assert (scripts/'factory-ledger.py').is_file(), 'approved ledger adapter not implemented'
spec=importlib.util.spec_from_file_location('ledger',scripts/'factory-ledger.py')
ledger=importlib.util.module_from_spec(spec);spec.loader.exec_module(ledger)

def rejects(fn):
    try: fn()
    except (ValueError,ledger.runtime.Blocked): return
    raise AssertionError('expected rejected authority')

with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp); (tmp/'tasks/archive').mkdir(parents=True); (tmp/'specs/active').mkdir(parents=True)
    content='---\nid: 001\nstatus: approved\n---\n\n1. **AC-1**: fixture\n'
    path=tmp/'specs/active/001-fixture.md';path.write_text(content)
    revision=hashlib.sha256(path.read_bytes()).hexdigest()
    policy={'specs':{'001':{'path':'specs/active/001-fixture.md','sha256':revision,'ac_ids':['AC-1'],'allowed_paths':['src/*']}},'runtime':{'services':[]}}
    (tmp/'factory.json').write_text(json.dumps(policy))
    archive=tmp/'tasks/archive/TASKS-2020-01.md';archive.write_text('- [x] T-1 | spec:001 | deps: | priority: normal\n')
    active=tmp/'tasks/TASKS.md';active.write_text('## Active\n- [ ] T-2 | spec:001 | deps: T-1 | priority: normal\n')
    db=tmp/'runtime.sqlite';store=ledger.runtime.Store(db)
    ledger.import_task(tmp,db,'T-2',tmp/'factory.json')
    assert store.get('T-2')['deps']==['T-1']
    assert store.get('T-1')['state']=='queued'
    rejects(lambda:store.claim('T-2','worker',30))
    ledger.import_task(tmp,db,'T-2',tmp/'factory.json')
    assert store.get('T-2')['attempt']==0
    rejects(lambda:ledger.confirm_merge(db,'T-1','b'*64,{'repository':'org/repo','pr':1,'merge_sha':'c'*40}))
    ledger.confirm_merge(db,'T-1',revision,{'repository':'org/repo','pr':1,'merge_sha':'c'*40})
    ledger.confirm_merge(db,'T-1',revision,{'repository':'org/repo','pr':1,'merge_sha':'c'*40})
    rejects(lambda:ledger.confirm_merge(db,'T-1',revision,{'repository':'org/repo','pr':2,'merge_sha':'d'*40}))
    assert store.claim('T-2','worker',30)>0
    # Each invalid import leaves the runtime DB unchanged.
    active.write_text('## Active\n- [ ] T-3 | spec:001 | deps: T-4\n- [ ] T-4 | spec:001 | deps: T-3\n')
    rejects(lambda:ledger.import_task(tmp,db,'T-3',tmp/'factory.json'))
    rejects(lambda:store.get('T-3'))
    active.write_text('## Active\n- [ ] T-3 | spec:001 | deps: T-99\n')
    rejects(lambda:ledger.import_task(tmp,db,'T-3',tmp/'factory.json'))
    rejects(lambda:store.get('T-3'))
    active.write_text('## Active\n- [ ] T-1 | spec:001 | deps:\n')
    rejects(lambda:ledger.import_task(tmp,db,'T-1',tmp/'factory.json'))
    active.write_text('## Active\n- [ ] T-3 | spec:001 | deps:\n')
    path.write_text(content+'changed\n');rejects(lambda:ledger.import_task(tmp,db,'T-3',tmp/'factory.json'));path.write_text(content)
    policy['specs']['001']['sha256']='b'*64;(tmp/'factory.json').write_text(json.dumps(policy));rejects(lambda:ledger.import_task(tmp,db,'T-3',tmp/'factory.json'))
    policy['specs']['001']['sha256']=revision;(tmp/'factory.json').write_text(json.dumps(policy))
    ledger.import_task(tmp,db,'T-3',tmp/'factory.json')
    active.write_text('## Active\n- [ ] T-3 | spec:001 | deps: T-1\n')
    rejects(lambda:ledger.import_task(tmp,db,'T-3',tmp/'factory.json'))
    active.write_text('## Active\n- [ ] T-3 | spec:001 | deps: T-4\n- [ ] T-4 | spec:001 | deps:\n')
    rejects(lambda:ledger.import_task(tmp,db,'T-3',tmp/'factory.json'))
    rejects(lambda:store.get('T-4'))
    # Lock helpers retain caller variables and task minting sees archived IDs.
    shell='source "$1/lib/tasks-lib.sh"; TASKS_FILE="$2/tasks/TASKS.md"; TASKS_ARCHIVE_DIR="$2/tasks/archive"; LOCK_STATE_DIR="$2/locks"; result=""; inner() { result=kept; }; outer() { with_tasks_lock inner; }; with_tasks_lock outer; [ "$result" = kept ] || exit 9; tasks_next_id'
    archive.write_text('- [x] T-900 | spec:001 | deps:\n')
    result=subprocess.run(['bash','-c',shell,'fixture',str(scripts),str(tmp)],capture_output=True,text=True,check=True)
    assert result.stdout.strip()=='901',result.stdout
    assert ledger.resource_contract({'services':[]},'run-a')['namespace']!='run-b'
    rejects(lambda:ledger.resource_contract({'services':['database']},'run-a'))
    resources=ledger.resource_contract({'services':[{'name':'database','kind':'directory'}]},'run-a')
    assert resources['namespace']=='run-a'
    policy['runtime']={'services':[{'name':'http','kind':'tcp'},{'name':'sqlite','kind':'directory'}]}
    (tmp/'factory.json').write_text(json.dumps(policy))
    active.write_text('## Active\n- [ ] T-10 | spec:001 | deps:\n- [ ] T-11 | spec:001 | deps:\n')
    archive.write_text('- [x] T-900 | spec:001 | deps:\n')
    worker=tmp/'worker.py'
    worker.write_text('import json,os,socket,sys;from pathlib import Path;services=json.loads(os.environ["FACTORY_SERVICES"]);listener=socket.socket(fileno=services["http"]["fd"]);assert listener.getsockname()[1]==services["http"]["port"];Path(services["sqlite"]["directory"]).joinpath("db.sqlite").write_text("isolated");Path(sys.argv[1]).write_text(json.dumps({"namespace":os.environ["FACTORY_RESOURCE_NAMESPACE"],"services":services}));import time;deadline=time.monotonic()+8\nwhile not Path(sys.argv[2]).exists():\n if time.monotonic()>deadline: raise RuntimeError("barrier expired")\n time.sleep(.05)')
    prefix=[sys.executable,str(scripts/'factory-ledger.py'),'--authority-root',str(tmp),'--policy',str(tmp/'factory.json'),'--db',str(db),'--cwd',str(tmp),'--attempts',str(tmp/'attempts')]
    workers=[subprocess.Popen([*prefix,'--task',f'T-{i}','--',sys.executable,str(worker),str(tmp/f'resource-{i}.json'),str(tmp/'release-workers')]) for i in (10,11)]
    deadline=time.monotonic()+8
    while not all((tmp/f'resource-{i}.json').exists() for i in (10,11)):
        assert time.monotonic()<deadline
        time.sleep(.05)
    (tmp/'release-workers').write_text('go')
    assert all(p.wait(timeout=10)==0 for p in workers)
    first,second=[json.loads((tmp/f'resource-{i}.json').read_text()) for i in (10,11)]
    assert first['namespace']!=second['namespace']
    assert first['services']['http']['port']!=second['services']['http']['port']
    assert first['services']['sqlite']['directory']!=second['services']['sqlite']['directory']
    assert store.get('T-10')['state']=='verifying'
    assert store.get('T-11')['state']=='verifying'

print('factory-ledger: approved closure, receipts, archive IDs, nested lock returns and resource contracts passed')
PY
