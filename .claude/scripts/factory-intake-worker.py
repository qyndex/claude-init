#!/usr/bin/env python3
"""Protected contract and guarded worker transport; mandatory routing stays gated."""
import hashlib
import math
import types
import json
import os
from pathlib import Path
import re
import stat
import pwd
import signal
import shlex
import time
import subprocess
import select
import sys

CAPABILITIES = ['foreground', 'model-selection', 'structured-output', 'config-isolation',
                'hook-failure-block', 'guarded-read-write-edit',
                'unmanaged-instructions-excluded', 'auto-memory-disabled',
                'managed-policy-compatible']
CLOSURE = ('factory-intake-worker.py', 'factory-intake.py', 'factory-runtime.py',
           'factory-routing.py', 'factory-supervisor.py', 'factory-bounded-process.py',
           'factory-worker-guard.py')
GUARD_FIELDS = {'native_executable', 'interpreter', 'version', 'capabilities', 'observation'}


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


def load_worker_contract(contract_path, task_id):
    """Read owner-controlled configuration and validate exact primary; never probe.

    The caller must obtain the contract binding from the protected installation
    registry. This pure validator does not authenticate a caller-selected path,
    authorize a task claim, or certify actual native hook capabilities.
    """
    raw = read_artifact(str(contract_path), private=True)
    contract = decode(raw)
    require(isinstance(contract, dict) and type(contract.get('enabled')) is bool,
            'worker intake contract invalid')
    if not contract['enabled']:
        fields = {'schema_version', 'enabled', 'repository', 'candidate_root', 'authority_root',
                  'database', 'profile', 'policy', 'trusted_files', 'limits'}
        require(set(contract) == fields and type(contract['schema_version']) is int
                and contract['schema_version'] == 1 and contract['trusted_files'] == {}
                and all(contract[key] is None for key in fields -
                        {'schema_version', 'enabled', 'trusted_files', 'limits'}),
                'disabled worker contract must remain neutral')
        limits = contract['limits']
        ceilings = {'request_chars': 20000, 'context_bytes': 500000, 'output_bytes': 65536, 'assessment_seconds': 60}
        require(isinstance(limits, dict) and set(limits) == set(ceilings), 'worker neutral budgets invalid')
        for key, maximum in ceilings.items():
            require(type(limits[key]) is int and (1024 if key == 'output_bytes' else 1) <= limits[key] <= maximum,
                    'worker neutral budget invalid')
        return None
    roots = tuple(path_value(contract.get(key)) for key in ('candidate_root', 'authority_root'))
    pins = contract.get('trusted_files')
    require(isinstance(pins, dict) and pins, 'worker protected closure missing')
    required = {str(Path(__file__).resolve().with_name(name)) for name in CLOSURE}
    required.update(contract.get(key) for key in ('profile', 'policy'))
    require(required <= set(pins), 'worker recursive closure must be pinned before imports')
    artifacts = {}
    for name, expected in pins.items():
        require(isinstance(expected, str) and re.fullmatch('[a-f0-9]{64}', expected),
                'worker protected pin invalid')
        artifacts[name] = read_artifact(name, roots=roots)
        require(digest(artifacts[name]) == expected, 'worker protected pin changed')
    # No repository-local import occurs before the complete declared closure is checked.
    def imported(name):
        path = Path(__file__).with_name(name)
        module = types.ModuleType('protected_worker_' + name.replace('-', '_'))
        module.__file__ = str(path)
        exec(compile(artifacts[str(path)], str(path), 'exec'), module.__dict__)
        return module
    core = imported('factory-intake.py')
    core.load_contract(contract_path)
    routing = imported('factory-routing.py')
    profile = decode(read_artifact(contract['profile'], private=True, roots=roots))
    policy = decode(read_artifact(contract['policy'], private=True, roots=roots))
    routing.validate(profile)
    require(profile['enabled'] is True and profile['repository'] == contract['repository']
            and policy.get('repository') == contract['repository'], 'worker repository differs')
    control = policy.get('runtime')
    require(isinstance(control, dict) and control.get('routing_profile_sha256') ==
            digest(canonical(profile).encode()), 'worker profile binding differs')
    require(isinstance(task_id, str) and re.fullmatch(r'T-[1-9][0-9]*', task_id)
            and isinstance(control.get('roles_by_task'), dict)
            and control['roles_by_task'].get(task_id) == 'implementation',
            'worker requires protected implementation task role')
    primary = profile['roles']['implementation']['primary']
    runtime = profile['runtimes'][primary]
    require(runtime['kind'] == 'claude-cli' and runtime['billing'] == 'subscription'
            and runtime['location'] == 'local', 'worker primary runtime unsupported')
    guard = control.get('worker_guard')
    require(isinstance(guard, dict) and set(guard) == GUARD_FIELDS,
            'worker guard declaration missing or invalid')
    version = guard['version']
    require(isinstance(version, str) and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version)
            and tuple(map(int, version.split('.'))) >= (2, 1, 295),
            'worker requires observed fail-closed native version')
    require(isinstance(guard['capabilities'], list) and guard['capabilities'] == CAPABILITIES,
            'worker observed capability contract differs')
    observation = guard['observation']
    require(isinstance(observation, dict) and set(observation) == {'path', 'sha256'},
            'worker observation binding invalid')
    native = str(path_value(guard['native_executable']))
    interpreter = str(path_value(guard['interpreter']))
    proof_path = str(path_value(observation['path']))
    worker_pins = {str(Path(__file__).resolve().with_name(name)) for name in CLOSURE}
    worker_pins.add(proof_path)
    runtime_pins = runtime['probe']['trusted_files']
    require(worker_pins <= set(pins) and worker_pins | {native, interpreter} <= set(runtime_pins),
            'worker runtime and controller closure pins missing')
    # Large executables have an indirect protected pin chain: controller pins the
    # complete profile/policy and proof; profile pins the actual executable bytes.
    # JSON/source/proof artifacts remain directly pinned in both stores (8 MB).
    for name, expected in runtime_pins.items():
        if name in {native, interpreter}:
            observed_digest = read_artifact(name, executable=True, digest_only=True, roots=roots)
        else:
            require(name in pins and pins[name] == expected,
                    'worker primary pin lacks protected controller agreement')
            observed_digest = digest(read_artifact(name, roots=roots))
        require(observed_digest == expected, 'worker primary pin changed')
    observed = decode(read_artifact(proof_path, private=True, roots=roots))
    expected = {'schema_version': 1, 'runtime': primary, 'model': runtime['model'],
                'native_sha256': runtime_pins[native], 'interpreter_sha256': runtime_pins[interpreter],
                'version': version, 'capabilities': guard['capabilities']}
    require(isinstance(observed, dict) and type(observed.get('schema_version')) is int and observed == expected
            and observation['sha256'] == pins[proof_path], 'worker observed evidence differs')
    argv = [interpreter, '-I', '-S', str(Path(__file__).resolve()), '--safe-mode',
            '--model', '{model}', '--output-format', 'json', '--print']
    require(runtime['command'] == argv, 'worker wrapper argv must match exact clean contract')
    # Recheck the bootstrap closure after imports and dependent validation.
    require(read_artifact(str(contract_path), private=True) == raw, 'worker contract changed')
    for name, expected_pin in pins.items():
        require(digest(read_artifact(name, roots=roots)) == expected_pin,
                'worker closure changed during validation')
    for name in {native, interpreter}:
        require(read_artifact(name, executable=True, digest_only=True, roots=roots) == runtime_pins[name],
                'worker executable changed during validation')
    return {'runtime': primary, 'model': runtime['model'], 'repository': contract['repository'],
            'profile_sha256': control['routing_profile_sha256'],
            'worker_guard_sha256': digest(canonical(guard).encode()),
            'native_executable': native, 'interpreter': interpreter,
            'capability_evidence': 'protected-observation'}


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


def bootstrap(descriptor):
    document=decode(start_bytes(descriptor,True));require(isinstance(document,dict),'worker descriptor malformed')
    entry=start_installation(Path(document['authority_root']))
    require(entry is not None and entry['contract']==document['contract']
            and entry['contract_sha256']==document['contract_sha256'],'worker launch installation differs')
    contract=decode(start_bytes(entry['contract'],True))
    require(digest(canonical(contract).encode())==entry['contract_sha256'],'worker launch installed contract changed')
    sources={}
    for name,expected in contract['trusted_files'].items():
        sources[name]=read_artifact(name,roots=[Path(contract[key]) for key in ('candidate_root','authority_root')])
        require(digest(sources[name])==expected,'worker launch source pin changed')
    require(str(Path('/bin/bash').resolve()) in sources,'worker hook shell interpreter not pinned')
    path=str(Path(__file__).with_name('factory-intake-hooks.py').resolve())
    require(path in sources,'worker launch hook bootstrap not pinned')
    hooks=types.ModuleType('protected_launch_hooks');hooks.__file__=path
    exec(compile(sources[path],path,'exec'),hooks.__dict__)
    controller=hooks.bound_controller(descriptor)
    document=hooks.validate_descriptor(controller,descriptor)
    hooks.mutation_shim_closure(controller)
    selected=load_worker_contract(controller.path,document['task'])
    return controller,document,hooks,selected,sources


def launch_material(document,selected):
    directory=Path(document['cwd']).parent
    hooks_directory=Path(__file__).parent.parent/'hooks'
    settings_path=directory/'native-settings.json';mcp_path=directory/'native-mcp.json'
    settings={'minimumVersion':selected.get('version','2.1.295'),'autoMemoryEnabled':False,
              'pluginConfigs':{'cc-plugin-agents-md@builtin':{'options':{'instructionFiles':'managed-only'}}},
              'claudeMdExcludes':[document['candidate_root']+'/**',document['authority_root']+'/**',str(directory)+'/**',
                                 '/**/CLAUDE.md','/**/CLAUDE.local.md','/**/AGENTS.md','/**/.claude/rules/**'],
              'hooks':{}}
    for event,shim in [('UserPromptSubmit','request-intake.sh'),('PreToolUse','pre-intake-action.sh'),
                       ('PostToolUse','post-intake-action.sh'),('PostToolUseFailure','post-intake-action.sh')]:
        args=[str(Path('/bin/bash').resolve()),str(hooks_directory/shim),selected['interpreter'],str(Path(__file__).with_name('factory-intake-hooks.py').resolve()),document['contract']]
        args[-1]=str(directory/'descriptor.json')
        if event=='PostToolUseFailure':args.append(event)
        settings['hooks'][event]=[{'matcher':'' if event=='UserPromptSubmit' else 'Read|Write|Edit' if event=='PreToolUse' else 'Write|Edit',
                                  'hooks':[{'type':'command','command':shlex.join(args),'timeout':90,'onFailure':'block'}]}]
    argv=[selected['native_executable'],'--print','--model',selected['model'],'--output-format','json',
          '--tools','Read,Write,Edit','--disallowedTools','mcp__*','--strict-mcp-config','--mcp-config',str(mcp_path),
          '--setting-sources','','--settings',str(settings_path),'--no-session-persistence','--session-id',document['native_session']]
    return settings_path,mcp_path,canonical(settings).encode(),canonical({'mcpServers':{}}).encode(),argv


def private_write(path,raw):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    try:
        with os.fdopen(fd,'wb',closefd=False) as stream:stream.write(raw);stream.flush();os.fsync(fd)
    finally:os.close(fd)


def launch_stage(controller,db,document):
    task=db.execute('SELECT owner,fence,state,expires,revision FROM tasks WHERE id=?',(document['task'],)).fetchone()
    identity=db.execute('SELECT version,repository,contract_sha256,contract_path,paused FROM intake_identity WHERE id=1').fetchone()
    control=db.execute('SELECT paused FROM control WHERE id=1').fetchone()
    descriptor=db.execute('SELECT state FROM intake_worker_descriptors WHERE start_id=?',(document['start_id'],)).fetchone()
    require(task is not None and tuple(task)[:3]==(document['owner'],document['fence'],'implementing')
            and task['expires'] is not None and task['expires']>controller.clock(None)
            and task['revision']==document['task_revision'] and control is not None and control['paused']==0
            and identity is not None and tuple(identity)==(1,controller.config['repository'],controller.binding,str(controller.path),0)
            and descriptor is not None and descriptor['state']=='issued','worker issued launch stage unavailable')


def launch_record(controller,document,selected,descriptor):
    settings,mcp,settings_raw,mcp_raw,argv=launch_material(document,selected)
    directory=Path(document['cwd']).parent
    return {'schema_version':1,'descriptor_sha256':digest(start_bytes(descriptor,True)),
            'settings':str(settings),'settings_sha256':digest(settings_raw),'mcp':str(mcp),'mcp_sha256':digest(mcp_raw),
            'stdin':str(directory/'native-stdin'),'stdin_sha256':document['prompt_sha256'],'argv':argv,
            'outcome':str(directory/'guardian-outcome.json'),'seconds':controller.config['limits']['assessment_seconds'],
            'output_bytes':controller.config['limits']['output_bytes']}


def validate_launch_record(controller,document,selected,descriptor,material):
    require(canonical(material)==canonical(launch_record(controller,document,selected,descriptor)),'guardian immutable launch record differs')


def run(descriptor):
    controller,document,hooks,selected,sources=bootstrap(descriptor)
    token=os.environ.get('FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN')
    require(isinstance(token,str) and 0<len(token)<=20000 and '\0' not in token,'dedicated implementation credential unavailable')
    settings,mcp,settings_raw,mcp_raw,argv=launch_material(document,selected)
    directory=Path(document['cwd']).parent;stdin_path=directory/'native-stdin';outcome=directory/'guardian-outcome.json'
    # This initial guarded adapter intentionally shares the stricter <=60s bound.
    # It does not claim the longer capacity of legacy advisory workers.
    limit=controller.config['limits']['output_bytes'];seconds=controller.config['limits']['assessment_seconds']
    material=launch_record(controller,document,selected,descriptor)
    encoded=canonical(material)
    with controller.transaction() as db:
        require(db.execute('SELECT 1 FROM intake_worker_launches WHERE start_id=?',(document['start_id'],)).fetchone() is None,'worker launch already reserved; replay fenced')
        db.execute("INSERT INTO intake_worker_launches VALUES(?,?,?,'reserved',?,NULL,NULL)",(document['start_id'],encoded,digest(encoded.encode()),os.getpid()))
    watch_read=watch_write=None;previous={};stopped=[];spawned_pids=[]
    try:
        for path,raw in [(settings,settings_raw),(mcp,mcp_raw),(stdin_path,document['prompt'].encode())]:private_write(path,raw)
        sync_path=str(Path(__file__).with_name('factory-supervisor.py').resolve());supervisor=types.ModuleType('protected_launch_supervisor');supervisor.__file__=sync_path
        exec(compile(sources[sync_path],sync_path,'exec'),supervisor.__dict__);supervisor.sync_worker_directory(directory)
        receipt=controller.owned_start(document['start_id'],document['owner'],document['fence'])
        if receipt['state']=='claimed':controller.begin_implementation(document['start_id'],document['owner'],document['fence'])
        controller.store.heartbeat(document['task'],document['owner'],document['fence'],max(90,seconds+30))
        bootstrap(descriptor)
        for key in ('cwd','home'):require(not list(Path(document[key]).iterdir()),'worker clean directory contains unmanaged data')
        env={'PATH':'/usr/bin:/bin','LANG':'C','LC_ALL':'C','HOME':document['home'],'CLAUDE_CONFIG_DIR':document['home'],
             'TMPDIR':document['home'],'CLAUDE_CODE_OAUTH_TOKEN':token,'CLAUDE_CODE_DISABLE_AUTO_MEMORY':'1'}
        watch_read,watch_write=os.pipe()
        def interrupted(signum,frame):
            stopped.append(signum)
            nonlocal watch_write
            if watch_write is not None:os.close(watch_write);watch_write=None
        for sig in (signal.SIGTERM,signal.SIGINT):previous[sig]=signal.signal(sig,interrupted)
        def spawned(process):
            spawned_pids.append(process.pid)
            with controller.transaction() as db:
                launch_stage(controller,db,document)
                require(db.execute("UPDATE intake_worker_launches SET state='running',guardian_pid=? WHERE start_id=? AND state='reserved' AND wrapper_pid=?",(process.pid,document['start_id'],os.getpid())).rowcount==1,'worker launch reservation changed')
            os.write(watch_write,b'1')
        bounded_path=str(Path(__file__).with_name('factory-bounded-process.py').resolve());bounded=types.ModuleType('protected_launch_bounded');bounded.__file__=bounded_path
        exec(compile(sources[bounded_path],bounded_path,'exec'),bounded.__dict__)
        command=[selected['interpreter'],'-I','-S',str(Path(__file__).with_name('factory-worker-guard.py').resolve()),'--intake-descriptor',str(descriptor),'--watch-fd',str(watch_read)]
        with stdin_path.open('rb') as stdin:
            result=bounded.run(command,env=env,cwd=document['cwd'],timeout=min(90,seconds+10),max_timeout=90,limit=limit,aggregate_limit=limit,stdin=stdin,pass_fds=(watch_read,),on_spawn=spawned,termination_grace=12)
        guardian_raw=start_bytes(outcome,True);guardian=decode(guardian_raw)
        require(not stopped and result.returncode==0 and guardian.get('cleanup_confirmed') is True and guardian.get('reason')=='native-exited','worker launch failed or cleanup uncertain')
        transport={'transport_status':'exited','exit_code':result.returncode,'stdout':result.stdout.decode('utf-8'),'stderr':result.stderr.decode('utf-8'),'guardian_sha256':digest(guardian_raw)}
        transport_raw=canonical(transport)
        with controller.transaction() as db:
            require(len(spawned_pids)==1,'worker launch principal missing')
            changed=db.execute("UPDATE intake_worker_launches SET state='exited',result=? WHERE start_id=? AND state='running' AND document=? AND sha256=? AND wrapper_pid=? AND guardian_pid=?",
                               (transport_raw,document['start_id'],encoded,digest(encoded.encode()),os.getpid(),spawned_pids[0])).rowcount
            require(changed==1,'worker transport commit binding changed')
            db.execute("INSERT INTO intake_worker_outcomes VALUES(?,?,NULL,NULL,'captured')",(document['start_id'],digest(transport_raw.encode())))
    except BaseException:
        with controller.transaction() as db:db.execute("UPDATE intake_worker_launches SET state='unknown' WHERE start_id=?",(document['start_id'],))
        raise
    finally:
        for sig,handler in previous.items():signal.signal(sig,handler)
        for fd in (watch_read,watch_write):
            if fd is not None:os.close(fd)
    # Captured transport is known even if current semantic authority is paused.
    return {'transport_status':'exited','exit_code':result.returncode,**validate_outcome(descriptor)}


def native_usage(raw, document, selected, limit):
    require(isinstance(raw,str) and len(raw.encode())<=limit,'native result missing or over bound')
    try:result=decode(raw)
    except RecursionError:raise ValueError('native JSON nesting exceeded')
    pending=[(result,0)];visited=0
    while pending:
        value,depth=pending.pop();visited+=1
        require(depth<=64 and visited<=10000,'native JSON structure bound exceeded')
        if type(value) is float:require(math.isfinite(value),'native numeric metadata nonfinite')
        if isinstance(value,dict):pending.extend((item,depth+1) for item in value.values())
        elif isinstance(value,list):pending.extend((item,depth+1) for item in value)
    required={'type','subtype','is_error','session_id','modelUsage','result'}
    optional={'total_cost_usd','duration_ms','duration_api_ms','num_turns','usage','uuid','stop_reason','permission_denials'}
    require(isinstance(result,dict) and required<=set(result)<=required|optional
            and result['type']=='result' and result['subtype']=='success' and result['is_error'] is False
            and result['session_id']==document['native_session'] and isinstance(result['result'],str),
            'native success envelope differs')
    models=result['modelUsage']
    require(isinstance(models,dict) and set(models)=={selected['model']} and isinstance(models[selected['model']],dict),
            'native usage must identify exact protected primary model')
    tokens={}
    for field in ('inputTokens','outputTokens','cacheReadInputTokens','cacheCreationInputTokens'):
        value=models[selected['model']].get(field)
        require((field not in models[selected['model']] and field.startswith('cache'))
                or (type(value) is int and 0<=value<=1000000000),'native token count invalid')
        tokens[field]=value
    estimate=result.get('total_cost_usd')
    require(estimate is None or (type(estimate) in (int,float) and math.isfinite(estimate) and 0<=estimate<=1000000),'native client estimate invalid')
    for field in ('duration_ms','duration_api_ms','num_turns'):
        if field in result:require(type(result[field]) is int and 0<=result[field]<=1000000000000,'native metadata count invalid')
    if 'usage' in result:require(isinstance(result['usage'],dict),'native aggregate usage invalid')
    if 'uuid' in result:require(isinstance(result['uuid'],str),'native message identity invalid')
    if 'stop_reason' in result:require(result['stop_reason'] is None or isinstance(result['stop_reason'],str),'native stop metadata invalid')
    if 'permission_denials' in result:require(isinstance(result['permission_denials'],list),'native denial metadata invalid')
    return {'model':selected['model'],'tokens':tokens,'estimated_api_usd':estimate,'actual_spend_usd':None}


def validate_outcome(descriptor):
    """Revalidate recorded transport/current authority; narrative is never evidence."""
    controller,document,hooks,selected,sources=bootstrap(descriptor)
    with controller.transaction() as db:
        launch=db.execute('SELECT * FROM intake_worker_launches WHERE start_id=?',(document['start_id'],)).fetchone()
        captured=db.execute('SELECT * FROM intake_worker_outcomes WHERE start_id=?',(document['start_id'],)).fetchone()
        descriptor_row=db.execute('SELECT * FROM intake_worker_descriptors WHERE start_id=?',(document['start_id'],)).fetchone()
        start=db.execute('SELECT * FROM intake_task_starts WHERE action_id=?',(document['start_id'],)).fetchone()
        task=db.execute('SELECT * FROM tasks WHERE id=?',(document['task'],)).fetchone()
        request_row=db.execute('SELECT * FROM intake_requests WHERE id=?',(document['request_id'],)).fetchone()
        decision_row=db.execute('SELECT * FROM intake_decision_bindings WHERE request_id=?',(document['request_id'],)).fetchone()
        dependencies=[db.execute('SELECT * FROM tasks WHERE id=?',(dep,)).fetchone() for dep in decode(task['deps'])]
        require(all(dep is not None and dep['state']=='merged' for dep in dependencies),'worker dependency unavailable')
        writes=db.execute('SELECT m.*,a.document AS action_document,a.status AS action_status,a.result AS action_result FROM intake_mutations m JOIN intake_actions a ON a.id=m.id WHERE m.start_id=? ORDER BY m.number',(document['start_id'],)).fetchall()
        native_writes=db.execute('SELECT * FROM intake_native_tool_writes WHERE start_id=? ORDER BY tool_use_id',(document['start_id'],)).fetchall()
    require(all(row['status']=='completed' and row['action_status']=='completed' for row in writes)
            and all(row['state']=='completed' for row in native_writes),'worker effects unresolved')
    effects=[list(row) for row in writes];acknowledgements=[list(row) for row in native_writes]
    require(launch is not None and launch['state']=='exited' and captured is not None
            and captured['state'] in {'captured','validated'} and descriptor_row['state']=='consumed'
            and start['state']=='implementing' and task['state']=='implementing','worker outcome not terminal/current/consumed')
    require(type(launch['wrapper_pid']) is int and launch['wrapper_pid']>0
            and type(launch['guardian_pid']) is int and launch['guardian_pid']>0,'worker launch principal missing')
    require(digest(launch['document'].encode())==launch['sha256'],'worker launch document changed')
    material=decode(launch['document']);validate_launch_record(controller,document,selected,descriptor,material)
    settings,mcp,settings_raw,mcp_raw,_=launch_material(document,selected)
    require(start_bytes(settings,True)==settings_raw and start_bytes(mcp,True)==mcp_raw
            and start_bytes(material['stdin'],True)==document['prompt'].encode(),'worker launch artifacts changed')
    raw=launch['result'];require(isinstance(raw,str) and digest(raw.encode())==captured['transport_sha256'],'private worker transport changed')
    transport=decode(raw)
    require(isinstance(transport,dict) and set(transport)=={'transport_status','exit_code','stdout','stderr','guardian_sha256'}
            and transport['transport_status']=='exited' and type(transport['exit_code']) is int and transport['exit_code']==0
            and isinstance(transport['stdout'],str) and isinstance(transport['stderr'],str)
            and len(transport['stdout'].encode())+len(transport['stderr'].encode())<=material['output_bytes'],'worker transport unsuccessful or over bound')
    guardian_raw=start_bytes(material['outcome'],True)
    require(digest(guardian_raw)==transport['guardian_sha256']
            and decode(guardian_raw)=={'reason':'native-exited','cleanup_confirmed':True},'worker cleanup proof differs')
    usage=native_usage(transport['stdout'],document,selected,material['output_bytes'])
    receipt={'schema_version':1,'start_id':document['start_id'],'descriptor_sha256':material['descriptor_sha256'],
             'launch_sha256':launch['sha256'],'transport_sha256':captured['transport_sha256'],
             'task':document['task'],'task_revision':document['task_revision'],'request_id':document['request_id'],
             'request_revision':document['request_revision'],'owner':document['owner'],'fence':document['fence'],
             'runtime_completed':True,'engineering_verified':False,'usage':usage,
             'effects_sha256':digest(canonical([effects,acknowledgements]).encode())}
    encoded=canonical(receipt);receipt_sha=digest(encoded.encode())
    # No transaction is held while checking current pins/HEAD/approval/owned bytes.
    current,current_doc,_,current_selected,_=bootstrap(descriptor)
    require(current.binding==controller.binding and current_doc==document and current_selected==selected,'worker outcome authority changed')
    with current.transaction() as db:
        actual=db.execute('SELECT * FROM intake_worker_launches WHERE start_id=?',(document['start_id'],)).fetchone()
        actual_descriptor=db.execute('SELECT * FROM intake_worker_descriptors WHERE start_id=?',(document['start_id'],)).fetchone()
        actual_start=db.execute('SELECT * FROM intake_task_starts WHERE action_id=?',(document['start_id'],)).fetchone()
        actual_task=db.execute('SELECT * FROM tasks WHERE id=?',(document['task'],)).fetchone()
        actual_request=db.execute('SELECT * FROM intake_requests WHERE id=?',(document['request_id'],)).fetchone()
        actual_decision=db.execute('SELECT * FROM intake_decision_bindings WHERE request_id=?',(document['request_id'],)).fetchone()
        actual_dependencies=[db.execute('SELECT * FROM tasks WHERE id=?',(dep['id'],)).fetchone() for dep in dependencies]
        require(all(actual is not None and actual['state']=='merged' and tuple(actual)==tuple(expected)
                    for actual,expected in zip(actual_dependencies,dependencies)),'worker dependency changed during validation')
        require(actual_request is not None and actual_decision is not None and tuple(actual_request)==tuple(request_row)
                and tuple(actual_decision)==tuple(decision_row),'worker bound request/decision changed during validation')
        identity=db.execute('SELECT version,repository,contract_sha256,contract_path,paused FROM intake_identity WHERE id=1').fetchone()
        control=db.execute('SELECT paused FROM control WHERE id=1').fetchone()
        actual_capture=db.execute('SELECT * FROM intake_worker_outcomes WHERE start_id=?',(document['start_id'],)).fetchone()
        current_writes=db.execute('SELECT m.*,a.document AS action_document,a.status AS action_status,a.result AS action_result FROM intake_mutations m JOIN intake_actions a ON a.id=m.id WHERE m.start_id=? ORDER BY m.number',(document['start_id'],)).fetchall()
        current_native=db.execute('SELECT * FROM intake_native_tool_writes WHERE start_id=? ORDER BY tool_use_id',(document['start_id'],)).fetchall()
        require([list(row) for row in current_writes]==effects and [list(row) for row in current_native]==acknowledgements,
                'worker effects changed during semantic validation')
        require(actual is not None and tuple(actual)==tuple(launch) and tuple(actual_descriptor)==tuple(descriptor_row)
                and tuple(actual_start)==tuple(start),'worker terminal bindings changed during validation')
        require(actual_task is not None and all(actual_task[key]==task[key] for key in ('id','owner','fence','state','revision','authority','deps'))
                and actual_task['expires'] is not None and actual_task['expires']>=task['expires']
                and actual_task['expires']>current.clock(None),'worker current lease/principal/stage changed')
        require(identity is not None and tuple(identity)==(1,current.config['repository'],current.binding,str(current.path),0)
                and control is not None and control['paused']==0,'worker outcome paused or identity changed')
        require(actual_capture is not None and tuple(actual_capture)==tuple(captured),'worker capture changed during validation')
        if captured['state']=='validated':
            require(captured['document']==encoded and captured['sha256']==receipt_sha,'worker semantic replay differs')
        else:
            require(captured['document'] is None and captured['sha256'] is None,'worker semantic receipt partially issued')
            require(db.execute("UPDATE intake_worker_outcomes SET document=?,sha256=?,state='validated' WHERE start_id=? AND state='captured' AND transport_sha256=? AND document IS NULL AND sha256 IS NULL",
                               (encoded,receipt_sha,document['start_id'],captured['transport_sha256'])).rowcount==1,'worker semantic commit changed')
    return {'runtime_completed':True,'engineering_verified':False,'usage':'reported','actual_spend_usd':None}


def guarded_native(descriptor,watch_fd):
    controller,document,hooks,selected,sources=bootstrap(descriptor)
    ready,_,_=select.select([watch_fd],[],[],5)
    require(ready and os.read(watch_fd,1)==b'1','guardian launcher handshake missing')
    with controller.transaction() as db:row=db.execute('SELECT * FROM intake_worker_launches WHERE start_id=?',(document['start_id'],)).fetchone()
    require(row is not None and row['state']=='running' and row['guardian_pid']==os.getpid() and row['wrapper_pid']==os.getppid(),'guardian launch principal differs')
    material=decode(row['document']);settings,mcp,settings_raw,mcp_raw,argv=launch_material(document,selected)
    validate_launch_record(controller,document,selected,descriptor,material)
    require(digest(row['document'].encode())==row['sha256'] and material['argv']==argv
            and start_bytes(settings,True)==settings_raw and start_bytes(mcp,True)==mcp_raw
            and material['stdin_sha256']==document['prompt_sha256'],'guardian immutable launch material differs')
    stdin_raw=start_bytes(material['stdin'],True)
    require(stdin_raw==document['prompt'].encode() and digest(stdin_raw)==document['prompt_sha256'],'guardian private input differs')
    with controller.transaction() as db:launch_stage(controller,db,document)
    native=None;reason='native-failed';cleanup=False;deadline=time.monotonic()+material['seconds'];captured=0;stopped=[]
    for sig in (signal.SIGTERM,signal.SIGINT):signal.signal(sig,lambda signum,frame:stopped.append(signum))
    try:
        import tempfile
        with tempfile.TemporaryFile(dir=document['home']) as native_stdin:
            native_stdin.write(stdin_raw);native_stdin.seek(0)
            native=subprocess.Popen(argv,stdin=native_stdin,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True,env=dict(os.environ),cwd=document['cwd'])
        streams={native.stdout.fileno():sys.stdout.fileno(),native.stderr.fileno():sys.stderr.fileno()}
        pending={sink:bytearray() for sink in streams.values()}
        for fd in [*streams,*pending]:os.set_blocking(fd,False)
        while streams or native.poll() is None or any(pending.values()):
            require(not stopped and time.monotonic()<deadline,'native stopped or timed out')
            readable,writable,_=select.select([watch_fd,*streams],[fd for fd,data in pending.items() if data],[],.05)
            if watch_fd in readable:require(os.read(watch_fd,1)!=b'','native launcher lost')
            for fd in readable:
                if fd==watch_fd:continue
                data=os.read(fd,65536)
                if not data:streams.pop(fd);continue
                captured+=len(data);require(captured<=material['output_bytes'],'native aggregate output bound exceeded')
                pending[streams[fd]].extend(data)
            for fd in writable:
                try:written=os.write(fd,pending[fd])
                except BlockingIOError:continue
                except OSError:raise ValueError('native output transport unavailable')
                del pending[fd][:written]
        require(native.wait()==0,'native exit failed');reason='native-exited'
        return 0
    finally:
        try:
            if native is not None:
                bounded_path=str(Path(__file__).with_name('factory-bounded-process.py').resolve());bounded=types.ModuleType('protected_guard_cleanup');bounded.__file__=bounded_path
                exec(compile(sources[bounded_path],bounded_path,'exec'),bounded.__dict__);bounded.terminate_group(native)
                native.stdout.close();native.stderr.close()
            cleanup=True
        finally:
            private_write(Path(material['outcome']),canonical({'reason':reason,'cleanup_confirmed':cleanup}).encode())
            if reason!='native-exited':
                with controller.transaction() as db:db.execute("UPDATE intake_worker_launches SET state='unknown' WHERE start_id=?",(document['start_id'],))
            os.close(watch_fd)


def main():
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--descriptor',required=True);parser.add_argument('--safe-mode',action='store_true');parser.add_argument('--model');parser.add_argument('--output-format',choices=['json']);parser.add_argument('--print',action='store_true')
    args=parser.parse_args()
    try:
        if args.model is not None:
            _,document,_,selected,_=bootstrap(args.descriptor);require(args.model==selected['model'],'wrapper model override denied')
        print(canonical(run(args.descriptor)));return 0
    except (ValueError,OSError,KeyError,TypeError):print('Protected worker launch blocked.',file=sys.stderr);return 2


if __name__=='__main__':
    import sys
    sys.exit(main())
