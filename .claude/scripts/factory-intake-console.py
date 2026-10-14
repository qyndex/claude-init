#!/usr/bin/env python3
"""Protected logical operator console; native delivery is explicitly unavailable."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import stat
import sqlite3
import sys
import types
import threading
import queue

def require(condition, message):
    if not condition:
        raise ValueError(message)

def decode(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate worker contract field')
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: require(False, 'nonfinite worker value'))

def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                      allow_nan=False)

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def path_value(value):
    require(isinstance(value, str), 'worker artifact path invalid')
    path = Path(value)
    require(path.is_absolute() and path.resolve() == path and not path.is_symlink(),
            'worker artifact path must be canonical')
    require(not any(part in {'.env', '.git', '.aws', '.ssh', 'credentials', 'secrets'}
                    or part.startswith('.env.') for part in path.parts),
            'worker artifact secret path forbidden')
    return path

def stable_identity(info):
    return tuple(getattr(info, name) for name in
                 ('st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_gid', 'st_nlink',
                  'st_size', 'st_mtime_ns', 'st_ctime_ns'))

def read_artifact(value, *, private=False, executable=False, roots=(), digest_only=False):
    path = path_value(value)
    require(all(path != root and root not in path.parents for root in roots),
            'worker artifact cannot be candidate/authority owned')
    before = path.stat()
    maximum = 512 * 1024 * 1024 if executable else 8000000
    require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
            and before.st_uid in {0, os.getuid()} and not before.st_mode & 0o022
            and before.st_size <= maximum, 'worker artifact ownership/type invalid')
    if private:
        parent = path.parent.stat()
        require(before.st_uid == os.getuid() and stat.S_IMODE(before.st_mode) == 0o600
                and parent.st_uid == os.getuid() and stat.S_IMODE(parent.st_mode) == 0o700,
                'worker private artifact permissions invalid')
    if executable:
        require(os.access(path, os.X_OK), 'worker executable unavailable')
    fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
                 | getattr(os, 'O_NONBLOCK', 0))
    try:
        opened = os.fstat(fd)
        require(stable_identity(opened) == stable_identity(before), 'worker artifact identity changed')
        hashed = hashlib.sha256()
        chunks = []
        size = 0
        with os.fdopen(fd, 'rb', closefd=False) as source:
            while True:
                chunk = source.read(min(1024 * 1024, maximum + 1 - size))
                if not chunk:
                    break
                size += len(chunk)
                require(size <= maximum, 'worker artifact bound exceeded')
                if digest_only:
                    hashed.update(chunk)
                else:
                    chunks.append(chunk)
        require(stable_identity(os.fstat(fd)) == stable_identity(opened)
                and not path.is_symlink() and stable_identity(path.stat()) == stable_identity(opened),
                'worker artifact changed while reading')
        return hashed.hexdigest() if digest_only else b''.join(chunks)
    finally:
        os.close(fd)

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
        stable=lambda value:(value.st_dev,value.st_ino,value.st_mode,value.st_uid,value.st_nlink,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
        require(len(raw)<=8000000 and len(raw)==info.st_size and stable(info)==stable(os.fstat(fd))==stable(path.lstat()),'start control bytes changed or exceeded');return raw
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


def controller(root):
    root=path_value(str(root))
    entry=start_installation(root)
    require(entry is not None,'console installation unavailable')
    contract=decode(start_bytes(entry['contract'],True))
    require(digest(canonical(contract).encode())==entry['contract_sha256'],
            'console installed contract changed')
    require(isinstance(contract,dict),'console installed contract malformed')
    require(contract.get('enabled') is True and contract.get('repository')==entry['repository']
            and all(contract.get(key)==entry[key] for key in
                    ('candidate_root','authority_root','database','profile','policy')),
            'console installation bindings differ')
    pins=contract.get('trusted_files');require(isinstance(pins,dict) and 0<len(pins)<=1000,'console source closure unavailable')
    captured={}
    roots=[Path(contract[key]) for key in ('candidate_root','authority_root')]
    for name,expected in pins.items():
        raw=read_artifact(name,roots=roots)
        require(isinstance(expected,str) and digest(raw)==expected,'console source pin changed')
        captured[name]=raw
    own=str(Path(__file__).resolve());require(own in captured,'console source not pinned')
    core_path=str(Path(__file__).with_name('factory-intake.py').resolve())
    require(core_path in captured,'console controller source unavailable')
    core=types.ModuleType('protected_console_controller');core.__file__=core_path
    exec(compile(captured[core_path],core_path,'exec'),core.__dict__)
    result=core.Intake(entry['contract'])
    require(result.binding==entry['contract_sha256'],'console controller binding changed')
    result.ready()
    return result


def head(store):
    scout,_=store.assessment_modules()
    root=store.config['candidate_root']
    environment={'PATH':'/usr/bin:/bin','HOME':'/nonexistent','GIT_CONFIG_NOSYSTEM':'1',
                 'GIT_CONFIG_SYSTEM':'/dev/null','GIT_CONFIG_GLOBAL':'/dev/null',
                 'GIT_CONFIG_COUNT':'0','GIT_TERMINAL_PROMPT':'0','GIT_OPTIONAL_LOCKS':'0','LC_ALL':'C'}
    command=['/usr/bin/git','--no-optional-locks','-c','core.fsmonitor=false',
             '-c','core.hooksPath=/dev/null','-C',root,'rev-parse','--verify','HEAD']
    observed=scout._bounded.run(command,env=environment,cwd=root,timeout=5,limit=8192)
    require(observed.returncode==0,'console current ref unavailable')
    value=observed.stdout.decode('ascii').strip()
    require(re.fullmatch(r'[a-f0-9]{40,64}',value) is not None,'console current ref invalid')
    return value


def emit(value):
    print(canonical(value),flush=True)


class OwnedOperation:
    """Only processes explicitly registered by this console may be cancelled."""
    def __init__(self):
        self.cancelled=threading.Event()
        self.lock=threading.RLock()
        self.processes=[]
        self.cleanup_states={}

    def check(self):
        require(not self.cancelled.is_set(),'console operation cancelled')

    def spawned(self, process, bounded):
        with self.lock:
            if self.cancelled.is_set():
                bounded.terminate_group(process)
                raise ValueError('console operation cancelled')
            self.processes.append((process,bounded))

    def finished(self, process):
        with self.lock:
            self.processes=[item for item in self.processes if item[0] is not process]

    def cleanup(self, process, terminate, *args, **kwargs):
        with self.lock:
            if process in self.cleanup_states:
                require(self.cleanup_states[process],'owned process cleanup uncertain')
                return
            # Retain the process object, never just a recyclable numeric PID.
            self.cleanup_states[process]=False
            try:
                result=terminate(process,*args,**kwargs)
                self.cleanup_states[process]=True
                return result
            finally:self.finished(process)

    def cancel(self):
        self.cancelled.set()
        with self.lock:
            uncertain=False
            for process,bounded in list(self.processes):
                try:bounded.terminate_group(process)
                except Exception:uncertain=True
            require(not uncertain and all(self.cleanup_states.values()),
                    'owned process cleanup uncertain')


def urgent(text):
    return text.strip().lower() in {'stop','pause','/stop','revoke'}


def pinned_module(store, name):
    path=str(Path(__file__).with_name(name).resolve())
    require(path in store.config['trusted_files'],'console dispatch helper not pinned')
    raw=read_artifact(path,roots=tuple(Path(store.config[key]) for key in ('candidate_root','authority_root')))
    require(digest(raw)==store.config['trusted_files'][path],'console dispatch helper changed')
    module=types.ModuleType('protected_console_'+name.replace('-','_'));module.__file__=path
    exec(compile(raw,path,'exec'),module.__dict__)
    return module


def dispatch(store, request_id, operation):
    operation.check()
    decision=store.fresh_decision(request_id)
    action=decision['next_action']
    if action=='draft':
        return store.publish_proposal(request_id)
    if action in {'answer','question','inspect','none','stop'}:
        result={'kind':action,'intents':decision['intents'],'blocked_reason':decision['blocked_reason'],
                'evidence':decision['evidence']}
        if action=='answer':
            result['response']='Requests are stored privately before assessment. New scope produces a private draft for human review. Only current eligible approved tasks may continue through the guarded worker; runtime completion still requires engineering verification.'
        elif action=='question':
            result['response']='Clarify the intended observable behavior, approved scope and acceptance criteria before continuing.'
        elif action=='inspect':
            with store.transaction() as db:
                rows=db.execute('SELECT id,state FROM tasks ORDER BY id LIMIT 1001').fetchall()
            require(len(rows)<=1000,'console status inventory exceeds bound')
            result['tasks']=[{'task':row['id'],'state':row['state']} for row in rows]
            result['eligible_tasks']=[item['task'] for item in store.eligible()]
            result['response']='Current private task state; completion receipts do not establish engineering verification.'
        else:result['response']=decision['blocked_reason'] or 'No governed action is authorized.'
        return result
    require(action=='resume','console action unsupported')
    worker=pinned_module(store,'factory-intake-worker.py')
    selected=worker.load_worker_contract(store.path,decision['task'])
    token=os.environ.get('FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN')
    require(isinstance(token,str) and 0<len(token)<=20000 and '\0' not in token,
            'console implementation credential unavailable')
    operation.check()
    store.enqueue_task(request_id)
    operation.check()
    start_id,_=store.start_intent(request_id,decision['task'])
    supervisor=pinned_module(store,'factory-supervisor.py')
    operation.check()
    supervisor.claim_intake(store,start_id,max(90,store.config['limits']['assessment_seconds']+30))
    operation.check()
    descriptor=supervisor.prepare_intake_worker(store,start_id)
    operation.check()
    bounded=pinned_module(store,'factory-bounded-process.py')
    terminate=bounded.terminate_group
    # SIGTERM lets the wrapper close its watch pipe and its guardian clean up.
    def cleanup(process,*args,**kwargs):
        return operation.cleanup(process,terminate,grace=12)
    bounded.terminate_group=cleanup
    env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C','HOME':'/nonexistent',
         'FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN':token}
    owned=[]
    def spawned(process):
        owned.append(process);operation.spawned(process,bounded)
    try:
        result=bounded.run([selected['interpreter'],'-I','-S',worker.__file__,'--descriptor',str(descriptor)],
                           env=env,cwd=str(Path(descriptor).parent),timeout=90,max_timeout=90,
                           limit=store.config['limits']['output_bytes'],aggregate_limit=store.config['limits']['output_bytes'],
                           on_spawn=spawned,termination_grace=12)
    finally:
        for process in owned:operation.finished(process)
    operation.check()
    require(result.returncode==0,'console protected worker failed')
    # Ignore subprocess narrative; independently read and validate its receipt.
    return worker.validate_outcome(descriptor)


def controlled_turn(root, session, text, options, operation):
    operation.check()
    store=controller(root)
    store.owned_operation=operation
    execution_ready=store.execution_ready
    def guarded_ready():
        operation.check()
        result=execution_ready()
        operation.check()
        return result
    store.execution_ready=guarded_ready
    operation.check()
    receipt=store.submit_console(session,text,head(store),parent=options.parent,
                                 delivery_token=options.retry_token)
    operation.check()
    result=store.assess(receipt['request_id'])
    operation.check()
    try:
        action=dispatch(store,receipt['request_id'],operation)
    except (ValueError,OSError,KeyError,TypeError,UnicodeError,sqlite3.Error):
        operation.check()
        # Keep the original approved decision intact; failure grants no fallback.
        return {'event':'blocked','receipt':receipt,'disposition':result['disposition'],
                'next_action':'none','blocked_reason':'protected-action-unavailable',
                'native_delivery':'unavailable','action':{'kind':'none',
                'response':'Protected action prerequisites or outcome validation are unavailable. No alternate worker or automatic retry is authorized.'}}
    operation.check()
    return {'event':'decision','receipt':receipt,'action':action,'disposition':result['disposition'],
            'next_action':result['next_action'],'blocked_reason':result['blocked_reason'],
            'native_delivery':'unavailable'}


def urgent_pause(store, operation):
    # Cancellation acknowledgement is independent of the durable pause attempt.
    cancelled=True
    try:operation.cancel()
    except (ValueError,OSError):cancelled=False
    acknowledged=threading.Event()
    def persist():
        try:store.pause();acknowledged.set()
        except (ValueError,OSError,sqlite3.Error):pass
    threading.Thread(target=persist,daemon=True).start()
    acknowledged.wait(.15)
    emit({'event':'control','next_action':'stop','cancelled':cancelled,
          'durable':acknowledged.is_set(),'native_delivery':'unavailable'})
    return 0 if cancelled and acknowledged.is_set() else 2


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--root',default=os.getcwd())
    parser.add_argument('--session')
    parser.add_argument('--parent')
    parser.add_argument('--retry-token')
    options=parser.parse_args()
    operation=None
    try:
        store=controller(options.root)
        session=options.session or store.new_session()
        with store.transaction() as db:
            require(db.execute('SELECT 1 FROM intake_sessions WHERE id=?',(session,)).fetchone() is not None,
                    'console session unknown')
        emit({'event':'session','session':session,'native_delivery':'unavailable'})
        incoming=queue.Queue(maxsize=16)
        def read_input():
            try:
                while True:
                    line=sys.stdin.readline(store.config['limits']['request_chars']+2)
                    incoming.put(line)
                    if not line:break
            except Exception:incoming.put(None)
        threading.Thread(target=read_input,daemon=True).start()
        count=0;pending=[];ended=False;queued_chars=0
        while True:
            line=pending.pop(0) if pending else incoming.get()
            require(line is not None,'console input read failed')
            if not line:break
            queued_chars=max(0,queued_chars-len(line))
            text=line[:-1] if line.endswith('\n') else line
            require(len(text)<=store.config['limits']['request_chars'],'console input exceeds bound')
            operation=OwnedOperation()
            if urgent(text):return urgent_pause(store,operation)
            require(not count or not (options.parent or options.retry_token),'linked console input must be one turn')
            completed=queue.Queue()
            def run_turn():
                try:completed.put((True,controlled_turn(options.root,session,text,options,operation)))
                except Exception:completed.put((False,None))
            threading.Thread(target=run_turn,daemon=True).start()
            while completed.empty():
                try:next_line=incoming.get(timeout=.01)
                except queue.Empty:continue
                require(next_line is not None,'console input read failed')
                if not next_line:ended=True;continue
                control=next_line[:-1] if next_line.endswith('\n') else next_line
                require(len(control)<=store.config['limits']['request_chars'],'console input exceeds bound')
                if urgent(control):return urgent_pause(store,operation)
                queued_chars+=len(next_line)
                if len(pending)>=16 or queued_chars>store.config['limits']['request_chars']:
                    operation.cancel()
                    raise ValueError('console queued input exceeds bound')
                pending.append(next_line)
            ok,value=completed.get()
            require(ok,'console owned operation failed')
            emit(value);count+=1
            if ended and not pending:break
        return 0
    except (ValueError,OSError,KeyError,TypeError,UnicodeError,sqlite3.Error):
        print('Console blocked by protected ingress checks.',file=sys.stderr)
        return 2
    finally:
        if operation is not None:
            try:operation.cancel()
            except (ValueError,OSError):pass


if __name__=='__main__':sys.exit(main())
