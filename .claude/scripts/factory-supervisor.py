#!/usr/bin/env python3
"""Own a foreground worker for its lifetime; exit zero means ready for verification."""
import argparse
import fcntl
import hashlib
import importlib.util
import json
import os
import pwd
import re
import stat
from pathlib import Path
import signal
import shutil
import socket
import subprocess
import sys
import time
import uuid

class LazyRuntime:
    def __init__(self):self.module=None
    def __getattr__(self,name):
        if self.module is None:
            spec=importlib.util.spec_from_file_location('runtime',Path(__file__).with_name('factory-runtime.py'))
            self.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.module)
        return getattr(self.module,name)
runtime=LazyRuntime()


def require(condition,message):
    if not condition:raise ValueError(message)

def decode(raw):
    def pairs(items):
        result={}
        for key,value in items:
            require(key not in result,'duplicate supervisor registry field');result[key]=value
        return result
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda value:(_ for _ in ()).throw(ValueError('nonfinite registry JSON')))

def start_bytes(path,private_file=False):
    path=Path(path)
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink(),'start control path not canonical')
    if private_file:
        require(path.parent.stat().st_uid==os.getuid() and stat.S_IMODE(path.parent.stat().st_mode)==0o700,'start control parent not private')
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        info=os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink==1 and info.st_size<=8000000,'start control file invalid')
        if private_file:require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'start control file not private')
        with os.fdopen(fd,'rb',closefd=False) as stream:raw=stream.read(8000001)
        require(len(raw)<=8000000,'start control bytes exceeded');return raw
    finally:os.close(fd)


def start_installation(root):
    """Stdlib-only OS registry read; no candidate environment/config selection."""
    home=Path(pwd.getpwuid(os.getuid()).pw_dir)
    require(home.is_absolute() and home.resolve()==home and home.is_dir(),'start OS home not canonical')
    directory=home/'.local/state/factory-required-intake';latch=home/'.factory-intake-required'
    if not directory.exists() and not latch.exists():return None
    require(directory.resolve()==directory and directory.is_dir() and directory.stat().st_uid==os.getuid()
            and stat.S_IMODE(directory.stat().st_mode)==0o700 and latch.exists(),'start registry missing or unsafe')
    latched=decode(start_bytes(latch));info=latch.stat()
    require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'start latch not private')
    records=decode(start_bytes(directory/'registry.json',True))
    require(isinstance(latched,dict) and set(latched)=={'schema_version','bindings'} and type(latched['schema_version']) is int
            and latched['schema_version']==1 and isinstance(latched['bindings'],dict)
            and isinstance(records,dict) and set(records)=={'schema_version','roots'} and type(records['schema_version']) is int
            and records['schema_version']==1 and isinstance(records['roots'],dict)
            and set(records['roots'])==set(latched['bindings']) and 0<len(records['roots'])<=1000,'start registry schema differs')
    fields={'repository','authority_root','candidate_root','contract','database','profile','policy','contract_sha256'}
    matched=[]
    for key,entry in records['roots'].items():
        require(isinstance(entry,dict) and set(entry)==fields and entry['authority_root']==key
                and isinstance(entry['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',entry['repository'])
                and isinstance(entry['contract_sha256'],str) and re.fullmatch(r'[a-f0-9]{64}',entry['contract_sha256'])
                and latched['bindings'][key]==entry['contract_sha256'],'start registry entry differs')
        for name in fields-{'repository','contract_sha256'}:
            require(isinstance(entry[name],str) and Path(entry[name]).is_absolute() and Path(entry[name]).resolve()==Path(entry[name]),'start registry path malformed')
        if str(root) in {entry['candidate_root'],entry['authority_root']}:matched.append(entry)
    require(len(matched)<=1,'start registry selection ambiguous')
    return matched[0] if matched else None


def registered_boundary(db, cwd):
    """Refuse direct installed supervision before helpers, locks or effects.

    The guarded wrapper protocol is not assembled yet; no input enables it.
    """
    import sqlite3
    if start_installation(Path(cwd).resolve()) is not None:
        raise ValueError('mandatory guarded supervisor unavailable until wrapper assembly')
    database=Path(db).resolve()
    if database.exists():
        with sqlite3.connect(database.as_uri()+'?mode=ro',uri=True) as connection:
            names={row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if 'intake_identity' in names or 'runtime_intake_required' in names:
            raise ValueError('required intake supervisor installation missing')


def claim_intake(controller, action_id, lease=30):
    """Mint an owner internally; Store.claim alone supplies its actual fence.

    This is claim-only, never launch permission. Lost acknowledgements reconcile
    the recorded exact owner/fence and never repeat an uncertain claim.
    """
    entry=start_installation(Path(controller.config['candidate_root']))
    expected_installation={'repository':controller.config['repository'],'authority_root':controller.config['authority_root'],
                          'candidate_root':controller.config['candidate_root'],'contract':str(controller.path),
                          'database':str(controller.database),'profile':controller.config['profile'],
                          'policy':controller.config['policy'],'contract_sha256':controller.binding}
    require(entry==expected_installation,'owned claim protected installation differs')
    require(hashlib.sha256(json.dumps(decode(start_bytes(entry['contract'],True)),sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode()).hexdigest()==entry['contract_sha256'],
            'owned claim installed contract bytes changed')
    if type(lease) not in {int,float} or not 3<=lease<=3600:
        raise ValueError('invalid owned claim lease')
    controller.execution_ready()
    with controller.transaction() as db:
        start=db.execute('SELECT * FROM intake_task_starts WHERE action_id=?',(action_id,)).fetchone()
        effect=db.execute('SELECT request_id FROM intake_actions WHERE id=?',(action_id,)).fetchone()
        if start is None or effect is None:raise ValueError('start intent missing')
    if start['state'] in {'claiming','claimed'}:
        return controller.reconcile_start(action_id)
    if start['state']!='intent':raise ValueError('start intent unresolved')
    controller.start_scope(effect['request_id'],start['task'],action_id)
    snapshot=decode(start['snapshot'])
    expected={'state':'queued','owner':None,'revision':start['revision'],'fence':snapshot['fence'],
              'authority':snapshot['authority'],'deps':snapshot['deps']}
    owner='supervisor:'+uuid.uuid4().hex
    with controller.transaction() as db:
        row=db.execute('SELECT * FROM tasks WHERE id=?',(start['task'],)).fetchone()
        if row is None or not all(row[name]==value for name,value in expected.items()):
            raise ValueError('queued task changed before claim reservation')
        changed=db.execute("UPDATE intake_task_starts SET state='claiming',owner=?,fence=? WHERE action_id=? AND state='intent'",(owner,expected['fence']+1,action_id)).rowcount
        if changed!=1:raise ValueError('start claim already reserved')
    # No SQLite transaction is held over claim. Even a pre-effect exception
    # leaves uncertainty explicit; callers cannot silently retry.
    token=controller.store.claim(start['task'],owner,lease,expected=expected)
    if token!=expected['fence']+1:raise ValueError('actual claim fence differs')
    return controller.reconcile_start(action_id)



def sync_worker_directory(value):
    """Persist private entries using the exact no-follow directory descriptor."""
    path=Path(value);before=path.stat()
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink()
            and stat.S_ISDIR(before.st_mode) and before.st_uid==os.getuid()
            and stat.S_IMODE(before.st_mode)==0o700,'worker sync directory not private')
    fd=os.open(path,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:
        opened=os.fstat(fd)
        identity=lambda info:(info.st_dev,info.st_ino,info.st_mode,info.st_uid)
        require(identity(opened)==identity(before),'worker directory changed before sync')
        os.fsync(fd)
        require(not path.is_symlink() and identity(os.fstat(fd))==identity(opened)
                and identity(path.stat())==identity(opened),'worker directory changed during sync')
    finally:os.close(fd)


def prepare_intake_worker(controller, start_id):
    """Issue one private descriptor from an actual live claim; no launch permit."""
    import types
    entry=start_installation(Path(controller.config['candidate_root']))
    expected={'repository':controller.config['repository'],'authority_root':controller.config['authority_root'],
              'candidate_root':controller.config['candidate_root'],'contract':str(controller.path),
              'database':str(controller.database),'profile':controller.config['profile'],
              'policy':controller.config['policy'],'contract_sha256':controller.binding}
    require(entry==expected,'descriptor protected installation differs')
    controller.execution_ready()
    sources={}
    for name in ('factory-intake-worker.py','factory-intake-hooks.py'):
        path=str(Path(__file__).with_name(name).resolve())
        require(path in controller.config['trusted_files'],'descriptor helper must be pinned before import')
        sources[path]=start_bytes(path)
        require(hashlib.sha256(sources[path]).hexdigest()==controller.config['trusted_files'][path],
                'descriptor helper pin changed')
    worker_path=str(Path(__file__).with_name('factory-intake-worker.py').resolve())
    worker=types.ModuleType('protected_descriptor_worker');worker.__file__=worker_path
    exec(compile(sources[worker_path],worker_path,'exec'),worker.__dict__)
    with controller.transaction() as db:
        start=db.execute('SELECT * FROM intake_task_starts WHERE action_id=?',(start_id,)).fetchone()
        effect=db.execute('SELECT request_id FROM intake_actions WHERE id=?',(start_id,)).fetchone()
    require(start is not None and effect is not None,'descriptor actual start missing')
    actual=controller.owned_start(start_id,start['owner'],start['fence'])
    selected=worker.load_worker_contract(controller.path,actual['task'])
    profile=decode(start_bytes(controller.config['profile'],True))
    hook_path=str(Path(__file__).with_name('factory-intake-hooks.py').resolve())
    require(profile['runtimes'][selected['runtime']]['probe']['trusted_files'].get(hook_path)==
            controller.config['trusted_files'][hook_path],'descriptor hook lacks runtime closure pin')
    snapshot=decode(start['snapshot'])
    prompt=json.dumps({'schema_version':1,'task':actual['task'],'context':snapshot['context']},
                      sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)
    require(len(prompt.encode())<=controller.config['limits']['context_bytes'],'descriptor complete prompt budget exceeded')
    reserved=False
    with controller.transaction() as db:
        row=db.execute('SELECT * FROM intake_worker_descriptors WHERE start_id=?',(start_id,)).fetchone()
        current=db.execute('SELECT owner,fence,revision,state FROM intake_task_starts WHERE action_id=?',(start_id,)).fetchone()
        require(current is not None and tuple(current)==(start['owner'],start['fence'],start['revision'],start['state']),
                'descriptor start changed before reservation')
        if row is None:
            nonce=uuid.uuid4().hex;directory=controller.path.parent/('worker-'+nonce)
            document={'schema_version':1,'nonce':nonce,'start_id':start_id,'request_id':effect['request_id'],
                      'request_revision':snapshot['request'][1],
                      'task':actual['task'],'task_revision':actual['revision'],'owner':actual['owner'],'fence':actual['fence'],
                      'contract':str(controller.path),'contract_sha256':controller.binding,
                      'authority_root':controller.config['authority_root'],'candidate_root':controller.config['candidate_root'],
                      'native_session':str(uuid.uuid4()),'cwd':str(directory/'cwd'),'home':str(directory/'home'),
                      'prompt':prompt,'prompt_sha256':hashlib.sha256(prompt.encode()).hexdigest(),
                      'worker_guard_sha256':selected['worker_guard_sha256']}
            encoded=json.dumps(document,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)
            path=directory/'descriptor.json';sha=hashlib.sha256(encoded.encode()).hexdigest()
            db.execute("INSERT INTO intake_worker_descriptors VALUES(?,?,?,?,?,'reserved')",(start_id,nonce,str(path),encoded,sha))
            reserved=True
            row={'path':str(path),'document':encoded,'sha256':sha,'state':'reserved'}
    if reserved:
        try:
            directory=Path(row['path']).parent;directory.mkdir(mode=0o700)
            sync_worker_directory(directory.parent)
            for name in ('cwd','home'):(directory/name).mkdir(mode=0o700)
            fd=os.open(row['path'],os.O_CREAT|os.O_EXCL|os.O_WRONLY|os.O_NOFOLLOW,0o600)
            try:
                with os.fdopen(fd,'wb',closefd=False) as output:output.write(row['document'].encode());output.flush();os.fsync(fd)
            finally:os.close(fd)
        except BaseException:
            with controller.transaction() as db:db.execute("UPDATE intake_worker_descriptors SET state='unknown' WHERE start_id=?",(start_id,))
            raise
    # A prior reserved effect may only reconcile exact observed bytes; never mkdir/rewrite it.
    helper=types.ModuleType('protected_descriptor_hook');helper.__file__=hook_path
    exec(compile(sources[hook_path],hook_path,'exec'),helper.__dict__)
    try:
        helper.validate_descriptor(controller,row['path'])
        sync_worker_directory(Path(row['path']).parent.parent)
        sync_worker_directory(Path(row['path']).parent)
        with controller.transaction() as db:
            db.execute("UPDATE intake_worker_descriptors SET state='issued' WHERE start_id=? AND state='reserved'",(start_id,))
        return row['path']
    except BaseException:
        with controller.transaction() as db:
            db.execute("UPDATE intake_worker_descriptors SET state='unknown' WHERE start_id=?",(start_id,))
        raise


def worker_environment(source):
    """Do not inherit coordinator authority or interpreter/proxy injection."""
    ordinary = {'PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'LANG', 'LC_ALL',
                'LC_CTYPE', 'TERM', 'TZ', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'PATHEXT'}
    environment = {name: value for name, value in source.items() if name in ordinary}
    implementation = source.get('FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN')
    if implementation:
        environment['CLAUDE_CODE_OAUTH_TOKEN'] = implementation
    return environment


def group_exists(pgid):
    result = subprocess.run(['/bin/ps', '-axo', 'pgid=,stat='], capture_output=True, text=True, check=True,timeout=2,
                            env={'PATH':'/usr/bin:/bin','HOME':'/nonexistent','LANG':'C','LC_ALL':'C'})
    return any(fields[0] == str(pgid) and not fields[1].startswith('Z')
               for line in result.stdout.splitlines() if len(fields := line.split()) == 2)


def terminate(worker, grace=2):
    # macOS may return EPERM rather than ESRCH for a vanished process group.
    try:alive=group_exists(worker.pid)
    except (OSError,subprocess.SubprocessError):
        try:os.killpg(worker.pid,signal.SIGKILL)
        except ProcessLookupError:pass
        worker.wait(timeout=5)
        raise ValueError('worker cleanup status uncertain')
    if not alive:
        worker.wait(timeout=5)
        return
    try:
        os.killpg(worker.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        if group_exists(worker.pid):
            raise
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline and group_exists(worker.pid):
        worker.poll()
        time.sleep(.05)
    if group_exists(worker.pid):
        try:
            os.killpg(worker.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            if group_exists(worker.pid):
                raise
    worker.wait(timeout=5)
    deadline = time.monotonic() + 5
    while group_exists(worker.pid) and time.monotonic() < deadline:
        time.sleep(.05)
    if group_exists(worker.pid):
        raise RuntimeError('worker descendants survived cleanup')


def supervise(db, task, command, cwd, attempts, timeout=1800, lease=30, resources=None):
    registered_boundary(db,cwd)
    lock = Path(db).resolve().parent / ("worker-" + hashlib.sha256(task.encode()).hexdigest() + ".lock")
    lock.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise runtime.Blocked("worker still holds task lock") from error
        return supervised(db, task, command, cwd, attempts, timeout, lease, fd, resources)
    finally:
        os.close(fd)


def supervised(db, task, command, cwd, attempts, timeout, lease, lock_fd, resources):
    registered_boundary(db,cwd)
    if not command or '--bg' in command or '--background' in command:
        raise ValueError('foreground command required')
    if not 1 <= timeout <= 21600 or not 3 <= lease <= 3600:
        raise ValueError('invalid supervision bounds')
    output_limit=(resources or {}).get('output_limit_bytes',1000000)
    if type(output_limit) is not int or not 1024<=output_limit<=8000000:
        raise ValueError('worker output bound invalid')
    execution = (resources or {}).get('execution')
    if execution is not None:
        module = importlib.util.spec_from_file_location('container_adapter', Path(__file__).with_name('factory-container.py'))
        adapter = importlib.util.module_from_spec(module); module.loader.exec_module(adapter)
        adapter.validate(execution)
        if (resources or {}).get('services'):
            raise ValueError('offline container cannot consume host service descriptors')
    db = Path(db).resolve()
    owner = 'supervisor:' + uuid.uuid4().hex
    store = runtime.Store(db)
    token = store.claim(task, owner, lease)
    directory = Path(attempts) / f'{task}-{token}-{uuid.uuid4().hex}'
    directory.mkdir(parents=True, mode=0o700)
    stopped = []
    previous = {}
    worker = None
    allocated = []
    alive_write = None
    reason = 'startup-failure'
    code = 1
    started = time.monotonic()
    try:
        for sig in (signal.SIGTERM, signal.SIGINT):
            previous[sig] = signal.signal(sig, lambda signum, frame: stopped.append(signum))
        store.transition(task, owner, token, 'implementing')
        executable = str(Path(cwd) / command[0]) if '/' in command[0] and not Path(command[0]).is_absolute() else command[0]
        if execution is None and shutil.which(executable) is None:
            raise FileNotFoundError(command[0])
        namespace = directory.name
        endpoints = {}
        for service in (resources or {}).get('services', []):
            if service['kind'] == 'tcp':
                channel = socket.socket()
                channel.bind(('127.0.0.1', 0))
                channel.listen(8)
                allocated.append(channel)
                endpoints[service['name']] = {'fd': channel.fileno(), 'port': channel.getsockname()[1]}
            elif service['kind'] == 'directory':
                private = directory / service['name']
                private.mkdir(mode=0o700)
                endpoints[service['name']] = {'directory': str(private.resolve())}
            else:
                raise ValueError('unsupported resource isolation adapter')
        env = dict(worker_environment(os.environ), FACTORY_RUN_DIR=str(directory.resolve()),
                   FACTORY_RESOURCE_NAMESPACE=namespace, FACTORY_SERVICES=json.dumps(endpoints),
                   TMPDIR=str(directory.resolve()))
        with (directory / 'worker.log').open('wb') as log:
            os.chmod(directory/'worker.log',0o600)
            alive_read, alive_write = os.pipe()
            inherited = (lock_fd, *(channel.fileno() for channel in allocated))
            guard = [sys.executable, str(Path(__file__).resolve().with_name('factory-worker-guard.py')),
                     '--watch-fd', str(alive_read), '--inherit-fds', json.dumps(inherited),
                     '--db', str(db), '--task', task, '--owner', owner, '--token', str(token),
                     '--outcome', str(directory.resolve() / 'guardian.json'), '--output-limit', str(output_limit)]
            if execution is not None:
                guard += ['--execution', json.dumps(execution)]
            guard += ['--', *command]
            try:
                worker = subprocess.Popen(guard, cwd=cwd, env=env, stdout=log,
                                          stderr=subprocess.STDOUT, start_new_session=True,
                                          pass_fds=(*inherited, alive_read))
            finally:
                os.close(alive_read)
            next_heartbeat = time.monotonic()
            while True:
                if stopped:
                    reason = 'cancelled'; break
                if time.monotonic() - started >= timeout:
                    reason = 'timeout'; break
                if time.monotonic() >= next_heartbeat:
                    try:
                        store.heartbeat(task, owner, token, lease)
                    except runtime.Blocked:
                        reason = 'lease-lost'; break
                    next_heartbeat = time.monotonic() + lease / 3
                result = worker.poll()
                if result is not None:
                    code = 0 if result == 0 else 1
                    reason = 'worker-success' if result == 0 else 'worker-failure'
                    break
                time.sleep(.05)
        terminate(worker)
        try:
            store.transition(task, owner, token, 'verifying' if code == 0 else 'blocked')
        except runtime.Blocked:
            code = 1; reason = 'lease-lost'
        return code
    except Exception:
        try:
            store.transition(task, owner, token, 'blocked')
        except runtime.Blocked:
            reason = 'lease-lost'
        raise
    finally:
        if worker is not None:
            terminate(worker)
        if alive_write is not None:
            os.close(alive_write)
        for channel in allocated:
            channel.close()
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        (directory / 'outcome.json').write_text(json.dumps({
            'task': task, 'owner': owner, 'fence': token, 'argv': command,
            'reason': reason, 'exit_code': code, 'engineering_verified': False,
            'elapsed_seconds': time.monotonic() - started,
        }, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True)
    parser.add_argument('--task', required=True)
    parser.add_argument('--cwd', required=True)
    parser.add_argument('--attempts', required=True)
    parser.add_argument('--timeout', type=float, default=1800)
    parser.add_argument('--lease', type=float, default=30)
    parser.add_argument('--detach', action='store_true')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    registered_boundary(args.db,args.cwd)
    if args.detach:
        if not command or '--bg' in command or '--background' in command:
            parser.error('foreground command required')
        logs = Path(args.attempts); logs.mkdir(parents=True, exist_ok=True)
        with (logs / ('launcher-' + uuid.uuid4().hex + '.log')).open('wb') as log:
            argv = list(sys.argv[1:])
            argv.remove('--detach')
            child = subprocess.Popen([sys.executable, __file__, *argv], stdin=subprocess.DEVNULL,
                                     stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        print(json.dumps({'supervisor_pid': child.pid, 'claimed': False}))
        return 0
    return supervise(args.db, args.task, command, args.cwd, args.attempts, args.timeout, args.lease)


if __name__ == '__main__':
    sys.exit(main())
