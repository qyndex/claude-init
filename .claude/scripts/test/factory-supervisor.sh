#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "${SUPERVISOR_TEST_ROOT:-$ROOT}" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

root=Path(sys.argv[1]); scripts=root/'.claude/scripts'
assert (scripts/'factory-supervisor.py').is_file(), 'worker supervisor not implemented'
spec=importlib.util.spec_from_file_location('sup',scripts/'factory-supervisor.py')
sup=importlib.util.module_from_spec(spec); spec.loader.exec_module(sup)

def wait_for(fn):
    end=time.monotonic()+8
    while time.monotonic()<end:
        if fn(): return
        time.sleep(.05)
    raise AssertionError('condition not reached')

def rejects(fn):
    try: fn()
    except (ValueError,sup.runtime.Blocked): return
    raise AssertionError('expected fail-closed outcome')

with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp); db=tmp/'runtime.sqlite'; attempts=tmp/'attempts'
    store=sup.runtime.Store(db)
    for i in range(1,8): store.enqueue(f'T-{i}','a'*64,[])
    assert sup.supervise(db,'T-1',[sys.executable,'-c','print("finished")'],tmp,attempts)==0
    assert store.get('T-1')['state']=='verifying'
    assert sup.supervise(db,'T-2',[sys.executable,'-c','raise SystemExit(42)'],tmp,attempts)==1
    assert store.get('T-2')['state']=='blocked'
    rejects(lambda:sup.supervise(db,'T-3',['claude','--bg'],tmp,attempts))
    assert store.get('T-3')['state']=='queued'
    child_pid=tmp/'grandchild.pid'
    tree=[sys.executable,'-c','import subprocess,sys,time;from pathlib import Path;p=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"]);Path(sys.argv[1]).write_text(str(p.pid));time.sleep(30)',str(child_pid)]
    assert sup.supervise(db,'T-3',tree,tmp,attempts,timeout=1,lease=3)==1
    assert json.loads(next(attempts.glob('T-3-*/outcome.json')).read_text())['reason']=='timeout'
    status=subprocess.run(['ps','-p',child_pid.read_text(),'-o','stat='],capture_output=True,text=True)
    assert not status.stdout.strip() or status.stdout.strip().startswith('Z')
    prefix=[sys.executable,str(scripts/'factory-supervisor.py'),'--db',str(db),'--cwd',str(tmp),'--attempts',str(attempts),'--lease','3']
    worker=[sys.executable,'-c','import time;time.sleep(30)']
    p=subprocess.Popen([*prefix,'--task','T-4','--',*worker],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    wait_for(lambda:store.get('T-4')['state']=='implementing')
    first=store.get('T-4');time.sleep(1.2)
    assert store.get('T-4')['expires']>first['expires']
    rejects(lambda:sup.supervise(db,'T-4',worker,tmp,attempts,lease=3))
    store.cancel('T-4'); assert p.wait(timeout=8)!=0
    assert json.loads(next(attempts.glob('T-4-*/outcome.json')).read_text())['reason']=='lease-lost'
    p=subprocess.Popen([*prefix,'--task','T-5','--',*worker],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    wait_for(lambda:store.get('T-5')['state']=='implementing')
    p.send_signal(signal.SIGTERM); assert p.wait(timeout=8)!=0
    assert store.get('T-5')['state']=='blocked'
    assert json.loads(next(attempts.glob('T-5-*/outcome.json')).read_text())['reason']=='cancelled'
    launched=subprocess.run([*prefix,'--task','T-6','--detach','--',sys.executable,'-c','import time;time.sleep(.4)'],capture_output=True,text=True,check=True)
    assert json.loads(launched.stdout)['claimed'] is False
    wait_for(lambda:store.get('T-6')['state']=='verifying')
    assert all(not json.loads(p.read_text())['engineering_verified'] for p in attempts.glob('*/outcome.json'))
    try:
        sup.supervise(db,'T-7',[str(tmp/'missing-command')],tmp,attempts)
    except FileNotFoundError:
        pass
    else:
        raise AssertionError('missing command accepted')
    assert store.get('T-7')['state']=='blocked'
    # Independent processes increment shared state; nested wrappers inherit the same lock.
    lock=tmp/'writers.lock'; counter=tmp/'counter'; counter.write_text('0')
    cmd=[sys.executable,str(scripts/'state-lock.py'),'--lock',str(lock),'--']
    update=[sys.executable,'-c','from pathlib import Path;import sys,time;p=Path(sys.argv[1]);v=int(p.read_text());time.sleep(.03);p.write_text(str(v+1))',str(counter)]
    processes=[subprocess.Popen([*cmd,*cmd,*update]) for _ in range(8)]
    assert all(p.wait(timeout=10)==0 for p in processes)
    assert counter.read_text()=='8'
    # Shell-function ledger writers and command wrappers share the same lock inode.
    function_call=['bash','-c','''source "$1"; LOCK_STATE_DIR="$2"; COUNTER="$3"; update() { python3 -c 'from pathlib import Path;import sys,time;p=Path(sys.argv[1]);v=int(p.read_text());time.sleep(.03);p.write_text(str(v+1))' "$COUNTER"; }; with_lock memory-plane update''','fixture',str(scripts/'lib/with-lock.sh'),str(tmp),str(counter)]
    ledger_cmd=[sys.executable,str(scripts/'state-lock.py'),'--lock',str(tmp/'memory-plane.oslock'),'--']
    processes=[subprocess.Popen(function_call if i%2 else [*ledger_cmd,*update]) for i in range(8)]
    assert all(p.wait(timeout=10)==0 for p in processes)
    assert counter.read_text()=='16'
    watchdog=[sys.executable,str(scripts/'foreground-watchdog.py'),'--timeout','1','--',sys.executable,'-c','import time;time.sleep(30)']
    assert subprocess.run(watchdog).returncode==124
    # Exercise the actual nightly launcher with fake git/Claude, no network or paid model.
    import shutil
    fixture=tmp/'nightly'; (fixture/'.claude/scripts').mkdir(parents=True)
    for name in ('local-overnight-build.sh','state-lock.py','foreground-watchdog.py','factory-supervisor.py','factory-runtime.py'):
        shutil.copy2(scripts/name,fixture/'.claude/scripts'/name)
    bins=fixture/'bin'; bins.mkdir()
    (bins/'git').write_text('#!/bin/sh\ncase "$1" in ls-remote) exit 2 ;; status|switch) exit 0 ;; *) exit 1 ;; esac\n')
    (bins/'claude').write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$FACTORY_NIGHTLY_ARGS"\nsleep 30\n')
    for path in bins.iterdir(): path.chmod(0o755)
    env=dict(os.environ,PATH=str(bins)+os.pathsep+os.environ['PATH'],CLAUDE_OVERNIGHT_TIMEOUT_SECONDS='1',FACTORY_NIGHTLY_ARGS=str(tmp/'nightly-args'))
    result=subprocess.run(['bash',str(fixture/'.claude/scripts/local-overnight-build.sh')],env=env,capture_output=True,text=True,timeout=8)
    assert result.returncode==124, result.stdout+result.stderr
    assert '--bg' not in (tmp/'nightly-args').read_text()
    for name in ('fleet-reconcile.sh','swarm-respawn.sh'):
        shutil.copy2(scripts/name,fixture/'.claude/scripts'/name)
    coordinator=fixture/'.swarms/coordinator';coordinator.mkdir(parents=True)
    for name in ('a','b'): (fixture/'.swarms/streams'/name).mkdir(parents=True)
    fleet=coordinator/'fleet.json'
    fleet.write_text(json.dumps({'fleet':{'a':{'status':'running','sessionId':'gone'},'b':{'status':'crashed'}}}))
    (bins/'claude').write_text('#!/bin/sh\ncase "$1" in agents) printf "[]\\n" ;; respawn) sleep .1; exit 0 ;; *) exit 1 ;; esac\n')
    processes=[subprocess.Popen(['bash',str(fixture/'.claude/scripts/fleet-reconcile.sh'),'--respawn'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE),subprocess.Popen(['bash',str(fixture/'.claude/scripts/swarm-respawn.sh'),'b'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)]
    for process in processes:
        out,err=process.communicate(timeout=8)
        assert process.returncode==0,(out,err)
    assert all(entry['status']=='respawned' for entry in json.loads(fleet.read_text())['fleet'].values())


    # Killing a launcher cannot release the lock while its worker is still running.
    marker=tmp/'started'
    p=subprocess.Popen([*cmd,sys.executable,'-c','from pathlib import Path;import sys,time;Path(sys.argv[1]).write_text("yes");time.sleep(.8)',str(marker)])
    wait_for(marker.exists); p.kill(); p.wait()
    start=time.monotonic(); subprocess.run([*cmd,*update],check=True)
    assert time.monotonic()-start>.3
print('factory-supervisor: foreground ownership, heartbeat, cancellation, timeout, detached launch and writer races passed')
PY
