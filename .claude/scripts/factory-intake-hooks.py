#!/usr/bin/env python3
"""Private bound worker submit gate only; no tools or human ingress authority."""
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import stat
import sys
import types


def require(condition,message):
    if not condition:raise ValueError(message)


def decode(raw):
    def pairs(items):
        result={}
        for key,value in items:
            require(key not in result,'duplicate worker field');result[key]=value
        return result
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda _:require(False,'invalid worker value'))


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)


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


FIELDS={'schema_version','nonce','start_id','request_id','request_revision','task','task_revision','owner','fence',
        'contract','contract_sha256','authority_root','candidate_root','native_session','cwd','home',
        'prompt','prompt_sha256','worker_guard_sha256'}


def private_directory(value):
    path=Path(value);info=path.stat()
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink()
            and stat.S_ISDIR(info.st_mode) and info.st_uid==os.getuid()
            and stat.S_IMODE(info.st_mode)==0o700,'worker directory not private')
    return path


def validate_descriptor(controller,path):
    """Check immutable private effect and actual current claim; grant no tool permit."""
    with controller.transaction() as db:
        row=db.execute('SELECT * FROM intake_worker_descriptors WHERE path=?',(str(path),)).fetchone()
    require(row is not None,'worker descriptor not reserved')
    effect_checked=False
    try:
        require(row['state'] in {'reserved','issued','consumed'},'worker descriptor unresolved')
        raw=start_bytes(path,True)
        require(raw==row['document'].encode() and hashlib.sha256(raw).hexdigest()==row['sha256'],
                'worker descriptor effect differs')
        document=decode(raw)
        require(isinstance(document,dict) and set(document)==FIELDS and type(document['schema_version']) is int
                and document['schema_version']==1 and document['nonce']==row['nonce']
                and document['start_id']==row['start_id'] and type(document['fence']) is int,
                'worker descriptor fields differ')
        directory=private_directory(Path(path).parent)
        require(directory==controller.path.parent/('worker-'+document['nonce'])
                and Path(path)==directory/'descriptor.json'
                and document['cwd']==str(directory/'cwd') and document['home']==str(directory/'home'),
                'worker descriptor assigned paths differ')
        for key in ('cwd','home'):private_directory(document[key])
        require(document['contract']==str(controller.path) and document['contract_sha256']==controller.binding
                and document['authority_root']==controller.config['authority_root']
                and document['candidate_root']==controller.config['candidate_root'], 'worker descriptor installation differs')
        with controller.transaction() as db:
            start=db.execute('SELECT snapshot,task,revision,owner,fence FROM intake_task_starts WHERE action_id=?',(document['start_id'],)).fetchone()
            action=db.execute('SELECT request_id FROM intake_actions WHERE id=?',(document['start_id'],)).fetchone()
        require(start is not None and action is not None,'worker immutable start binding missing')
        snapshot=decode(start['snapshot'])
        expected_prompt=canonical({'schema_version':1,'task':start['task'],'context':snapshot['context']})
        require(document['task']==start['task'] and document['task_revision']==start['revision']
                and document['owner']==start['owner'] and document['fence']==start['fence']
                and document['request_id']==action['request_id'] and document['request_revision']==snapshot['request'][1]
                and document['prompt']==expected_prompt
                and len(expected_prompt.encode())<=controller.config['limits']['context_bytes']
                and document['prompt_sha256']==hashlib.sha256(expected_prompt.encode()).hexdigest(),
                'worker descriptor approved scope differs')
        worker_path=str(Path(__file__).with_name('factory-intake-worker.py').resolve())
        require(worker_path in controller.config['trusted_files'],'worker contract helper pin absent')
        worker_raw=start_bytes(worker_path)
        require(hashlib.sha256(worker_raw).hexdigest()==controller.config['trusted_files'][worker_path],
                'worker contract helper changed')
        worker=types.ModuleType('protected_submit_worker');worker.__file__=worker_path
        exec(compile(worker_raw,worker_path,'exec'),worker.__dict__)
        selected=worker.load_worker_contract(controller.path,start['task'])
        require(selected['worker_guard_sha256']==document['worker_guard_sha256'],'worker declaration differs')
        # Only current live claim/pause/pending denials are temporary. All immutable
        # request/task/prompt/worker bindings above remain structural uncertainty.
        effect_checked=True
        controller.execution_ready()
        controller.owned_start(document['start_id'],document['owner'],document['fence'])
        try:
            require(start_bytes(path,True)==raw,'worker descriptor changed during validation')
        except BaseException:
            effect_checked=False
            raise
        return document
    except BaseException:
        if not effect_checked:
            with controller.transaction() as db:
                db.execute("UPDATE intake_worker_descriptors SET state='unknown' WHERE start_id=?",(row['start_id'],))
        raise


def bound_controller(path):
    """Resolve fixed OS registry and verify closure before executing helper bytes."""
    document=decode(start_bytes(path,True))
    require(isinstance(document,dict) and set(document)==FIELDS,'worker descriptor schema invalid')
    entry=start_installation(Path(document['authority_root']))
    require(entry is not None and entry['contract']==document['contract']
            and entry['contract_sha256']==document['contract_sha256']
            and entry['candidate_root']==document['candidate_root'],'worker required installation differs')
    contract=decode(start_bytes(entry['contract'],True))
    require(hashlib.sha256(canonical(contract).encode()).hexdigest()==entry['contract_sha256'],
            'worker installed contract changed')
    pins=contract.get('trusted_files');require(isinstance(pins,dict),'worker source closure missing')
    names=('factory-intake.py','factory-runtime.py','factory-ledger.py','factory-routing.py',
           'factory-supervisor.py','factory-bounded-process.py','factory-intake-scout.py',
           'factory-intake-worker.py','factory-worker-guard.py','factory-intake-hooks.py')
    paths={str(Path(__file__).with_name(name).resolve()) for name in names}
    require(paths<=set(pins),'worker recursive source closure incomplete')
    sources={}
    roots=[Path(contract[name]) for name in ('candidate_root','authority_root')]
    for name,expected in pins.items():
        source=Path(name)
        require(all(root!=source and root not in source.parents for root in roots),'worker source cannot be candidate owned')
        sources[name]=start_bytes(name)
        require(hashlib.sha256(sources[name]).hexdigest()==expected,'worker source closure changed')
    core_path=str(Path(__file__).with_name('factory-intake.py').resolve())
    core=types.ModuleType('protected_worker_controller');core.__file__=core_path
    exec(compile(sources[core_path],core_path,'exec'),core.__dict__)
    return core.Intake(entry['contract'])


def consume_submit(path,payload):
    controller=bound_controller(path)
    document=validate_descriptor(controller,path)
    require(isinstance(payload,dict) and payload.get('hook_event_name')=='UserPromptSubmit'
            and payload.get('session_id')==document['native_session'] and payload.get('cwd')==document['cwd']
            and payload.get('prompt')==document['prompt'],'worker submit does not match reserved input')
    with controller.transaction() as db:
        actual=db.execute('SELECT owner,fence,state,expires,revision FROM tasks WHERE id=?',(document['task'],)).fetchone()
        paused=db.execute('SELECT paused FROM control WHERE id=1').fetchone()
        identity=db.execute('SELECT version,repository,contract_sha256,contract_path,paused FROM intake_identity WHERE id=1').fetchone()
        require(identity is not None and tuple(identity)==(1,controller.config['repository'],controller.binding,str(controller.path),0),
                'worker intake identity changed or paused before submit consumption')
        require(actual is not None and actual['owner']==document['owner'] and actual['fence']==document['fence']
                and actual['revision']==document['task_revision'] and actual['state'] in {'claimed','implementing'}
                and actual['expires'] is not None and actual['expires']>controller.clock(None)
                and paused is not None and paused['paused']==0,'worker claim changed before submit consumption')
        changed=db.execute("UPDATE intake_worker_descriptors SET state='consumed' WHERE start_id=? AND state='issued' AND sha256=?",
                           (document['start_id'],hashlib.sha256(canonical(document).encode()).hexdigest())).rowcount
        require(changed==1,'worker initial submit already consumed or unresolved')
    return {'continue':True}


def authorize_read(path,payload):
    """Authorize one exact native Read against explicit protected disclosure data."""
    allowed_fields={'hook_event_name','session_id','cwd','tool_name','tool_use_id','tool_input',
                    'transcript_path','permission_mode','run_in_background'}
    require(isinstance(payload,dict) and set(payload)<=allowed_fields and payload.get('hook_event_name')=='PreToolUse'
            and payload.get('tool_name')=='Read' and payload.get('run_in_background',False) is False
            and isinstance(payload.get('tool_use_id'),str) and 0<len(payload['tool_use_id'])<=256,
            'worker tool unsupported or malformed')
    arguments=payload.get('tool_input')
    require(isinstance(arguments,dict) and set(arguments)<={'file_path','offset','limit'}
            and isinstance(arguments.get('file_path'),str),'worker Read payload invalid')
    for key in ('offset','limit'):
        if key in arguments:require(type(arguments[key]) is int and 0<arguments[key]<=500000,'worker Read bounds invalid')
    controller=bound_controller(path);document=validate_descriptor(controller,path)
    require(payload.get('session_id')==document['native_session'] and payload.get('cwd')==document['cwd'],
            'worker Read native binding differs')
    receipt=controller.owned_start(document['start_id'],document['owner'],document['fence'])
    require(receipt['state']=='implementing','worker Read requires implementing stage')
    with controller.transaction() as db:
        descriptor=db.execute('SELECT state FROM intake_worker_descriptors WHERE start_id=?',(document['start_id'],)).fetchone()
        start=db.execute('SELECT snapshot FROM intake_task_starts WHERE action_id=?',(document['start_id'],)).fetchone()
        writes=db.execute('SELECT path,after_sha256,status FROM intake_mutations WHERE start_id=? ORDER BY number',(document['start_id'],)).fetchall()
    require(descriptor is not None and descriptor['state']=='consumed','worker initial submit not consumed')
    snapshot=decode(start['snapshot'])
    policy=decode(start_bytes(controller.config['policy'],True))
    selected=set(policy['intake']['context_paths'])
    disclosure={item['path']:item['sha256'] for item in snapshot['context']['sources'] if item['path'] in selected}
    for write in writes:
        require(write['status']=='completed','worker uncertain writes fence Read')
        disclosure[write['path']]=write['after_sha256']
    root=Path(controller.config['candidate_root']);target=Path(arguments['file_path'])
    require(target.is_absolute() and str(target)==arguments['file_path'] and target.resolve()==target,
            'worker Read must use canonical absolute file')
    name=str(target.relative_to(root))
    require(name in disclosure,'worker file lacks explicit disclosure approval')
    scout,routing=controller.assessment_modules();relative=scout.relative(name);scout.permitted(relative)
    excluded={'.claude','.codex','.agents','.github','factory','specs','plans','tasks','initiatives','verify'}
    require(relative.parts[0].lower() not in excluded
            and not any(part.lower() in {'.venv','venv','__pycache__','.cache'} for part in relative.parts),
            'worker protected/control Read rejected')
    protected=policy.get('protected_paths',[])
    require(isinstance(protected,list) and all(isinstance(value,str) for value in protected)
            and not controller_scope_match(name,protected),'worker protected policy Read rejected')
    profile=decode(start_bytes(controller.config['profile'],True))
    roots=[scout.source_root(value) for value in profile['source_roots']]
    require(any(relative==base or base in relative.parents for base in roots),'worker Read outside source roots')
    for shim in ('request-intake.sh','pre-intake-action.sh'):
        shim_path=str(Path(__file__).parent.parent/'hooks'/shim)
        require(shim_path in controller.config['trusted_files']
                and profile['runtimes'][profile['roles']['implementation']['primary']]['probe']['trusted_files'].get(shim_path)
                ==controller.config['trusted_files'][shim_path],'worker hook shim closure missing')
    fd=os.open(root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:
        for component in relative.parts[:-1]:
            child=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd)
            os.close(fd);fd=child
        raw,metadata=controller.mutation_bytes(fd,target)
        require(raw is not None and hashlib.sha256(raw).hexdigest()==disclosure[name],
                'worker Read approved bytes changed')
        # Recheck scope/claim/unknown effects after byte validation, without disclosing bytes.
        validate_descriptor(controller,path)
        controller.owned_start(document['start_id'],document['owner'],document['fence'])
        require(controller.mutation_parent(fd,target) is not None
                and controller.file_metadata(os.stat(target.name,dir_fd=fd,follow_symlinks=False))==metadata,
                'worker Read file changed before admission')
    finally:os.close(fd)
    return {'hookSpecificOutput':{'hookEventName':'PreToolUse','permissionDecision':'allow',
                                 'permissionDecisionReason':'Exact protected disclosure and owned stage validated.'}}


def controller_scope_match(path,patterns):
    return any(path.startswith(pattern[:-1]) if pattern.endswith('*') else path==pattern for pattern in patterns)


def main():
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--descriptor',required=True);parser.add_argument('--event',required=True)
    args=parser.parse_args()
    try:
        require(args.event in {'UserPromptSubmit','PreToolUse'},'worker tool guards not assembled')
        raw=sys.stdin.buffer.read(2000001);require(len(raw)<=2000000,'worker submit input bound exceeded')
        payload=decode(raw)
        result=consume_submit(args.descriptor,payload) if args.event=='UserPromptSubmit' else authorize_read(args.descriptor,payload)
        print(canonical(result));return 0
    except (ValueError,OSError,KeyError,TypeError):
        print('Worker submit blocked by protected binding checks.',file=sys.stderr);return 2


if __name__=='__main__':sys.exit(main())
