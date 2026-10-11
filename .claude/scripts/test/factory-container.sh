#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import hashlib,importlib.util,json,os,sqlite3,sys,tempfile
from pathlib import Path
from unittest.mock import patch
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-container.py';assert path.exists(),'offline daemon-owned worker adapter absent'
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
m=module('container',path);runtime=module('runtime',root/'.claude/scripts/factory-runtime.py')
def rejects(fn):
    try:fn()
    except (ValueError,OSError,KeyError,TypeError,runtime.Blocked):return
    raise AssertionError('unsafe container operation accepted')
with tempfile.TemporaryDirectory() as temporary:
    base=Path(temporary).resolve();private=base/'private';private.mkdir(mode=0o700);candidate=base/'candidate';candidate.mkdir();(candidate/'source.txt').write_text('candidate only')
    binary=private/'docker';binary.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
args=sys.argv[5:];state=Path(__file__).with_name('daemon.json');mode_path=Path(__file__).with_name('mode');mode=mode_path.read_text() if mode_path.exists() else 'normal';value=json.loads(state.read_text()) if state.exists() else None
if mode=='unavailable':sys.exit(1)
if args[:2]==['image','inspect']:print(json.dumps([{'Id':args[2],'Config':{'Volumes':None,'Env':[]}}]))
elif args[:2]==['container','create']:
    if mode=='unknown-create':sys.exit(1)
    labels=dict(args[i+1].split('=',1) for i,item in enumerate(args) if item=='--label');name=args[args.index('--name')+1];image=next(arg for arg in args if arg.startswith('sha256:'))
    value={'Name':'/'+name,'Id':'d'*64,'Image':image,'Config':{'Labels':labels},'State':{'Status':'created'}}
    state.write_text(json.dumps(value));Path(__file__).with_name('create-argv.json').write_text(json.dumps({'argv':args,'environment':dict(os.environ)}))
    if mode=='lost-create-ack':sys.exit(1)
    print(value['Id'])
elif args[:2]==['container','inspect']:
    if value is None:sys.exit(1)
    if mode=='foreign':value['Config']['Labels']['factory.task']='T-999'
    print(json.dumps([value]))
elif args[:2]==['container','ls']:
    if value is not None:print(json.dumps({'Names':value['Name'][1:],'ID':value['Id']}))
elif args[:2]==['container','rm']:
    if mode=='remove-fails':sys.exit(1)
    state.unlink(missing_ok=True)
else:sys.exit(1)
''');binary.chmod(0o755)
    config={'kind':'docker-offline','binary':str(binary),'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'image':'sha256:'+'a'*64,'repository':'org/repo','memory_mb':128,'cpus':1,'pids_limit':64}
    store=runtime.Store(private/'state.sqlite');Path(store.path).chmod(0o600)
    def fixture(number):
        task=f'T-{number}';store.enqueue(task,'b'*64,[]);token=store.claim(task,'guardian',30);store.transition(task,'guardian',token,'implementing');directory=private/(f'{task}-{token}-'+'c'*32);directory.mkdir(mode=0o700);return m.Container(config,store,task,'guardian',token,directory,candidate,['/bin/busybox','true'])
    with patch.object(m.sys,'platform','linux'),patch.dict(os.environ,{'GH_TOKEN':'coordinator-only','FACTORY_SLACK_BOT_TOKEN':'private-token'}):
        worker=fixture(1)
        try:
            command=worker.create();assert command[-4:]==['container','start','--attach',worker.name]
            observed=json.loads((private/'create-argv.json').read_text());assert 'coordinator-only' not in json.dumps(observed) and 'private-token' not in json.dumps(observed)
            args=observed['argv'];assert args[args.index('--network')+1]=='none' and '--read-only' in args and args[args.index('--cap-drop')+1]=='ALL'
            assert args[args.index('--user')+1]==f'{os.getuid()}:{os.getgid()}' and args.count('--mount')==1 and str(private) not in args[args.index('--mount')+1]
            assert store.worker_effects('T-1')[0]['presence'] is not None
            rejects(lambda:store.recover_worker('T-1','guardian',1,requeue=True))
            worker.cleanup();assert store.worker_effects('T-1')[0]['status']=='clean';assert not (private/'daemon.json').exists()
        finally:worker.close()
        print('AC-1: actual fake-daemon client enforces pinned image/executable, nonroot read-only offline resource bounds, candidate-only mount and no inherited coordinator credentials; intent/presence precede launch')
        (private/'mode').write_text('lost-create-ack');worker=fixture(2)
        try:rejects(worker.create);worker.cleanup();assert store.worker_effects('T-2')[0]['status']=='clean'
        finally:worker.close()
        (private/'mode').write_text('unknown-create');worker=fixture(3)
        try:rejects(worker.create);rejects(worker.cleanup);assert store.worker_effects('T-3')[0]['status']=='uncertain'
        finally:worker.close()
        print('AC-2: lost creation acknowledgement reconciles exact created daemon identity; absent unacknowledged creation remains uncertain and cannot release replay')
        (private/'mode').write_text('normal');worker=fixture(4)
        try:
            worker.create();(private/'mode').write_text('foreign');rejects(worker.cleanup);assert (private/'daemon.json').exists()
            (private/'mode').write_text('remove-fails');rejects(worker.cleanup);assert store.worker_effects('T-4')[0]['status']=='uncertain'
            (private/'mode').write_text('normal');worker.cleanup()
            recovery=m.Container.for_cleanup(config,store,store.worker_effects('T-4')[0])
            try:recovery.cleanup()
            finally:recovery.close()
        finally:worker.close()
        hardlink=candidate/'linked';os.link(private/'state.sqlite',hardlink);rejects(lambda:fixture(5));hardlink.unlink()
        (private/'mode').write_text('unavailable');uncertain=m.Container.for_cleanup(config,store,store.worker_effects('T-3')[0])
        try:rejects(uncertain.cleanup)
        finally:uncertain.close()
        print('AC-3: foreign daemon labels, failed removal/contact and candidate hardlinks block; durable presence permits idempotent absent cleanup without reviving task authority')
PYTEST

bash "$ROOT/.claude/scripts/test/factory-container-live.sh"
