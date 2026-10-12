#!/usr/bin/env python3
"""Import approved ledger projections; worker success is never merge evidence."""
import argparse
from contextlib import closing
import fcntl
import hashlib
import importlib.util
import json
import os
import pwd
import tempfile
import stat
import sqlite3
from pathlib import Path
import re
import sys

class LazyRuntime:
    def __init__(self):self.module=None
    def __getattr__(self,name):
        if self.module is None:
            spec=importlib.util.spec_from_file_location('runtime',Path(__file__).with_name('factory-runtime.py'))
            self.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.module)
        return getattr(self.module,name)


runtime=LazyRuntime()


def intake_require(condition,message):
    if not condition:raise ValueError(message)


def intake_decode(raw):
    def pairs(items):
        result={}
        for key,value in items:
            intake_require(key not in result,'duplicate protected intake field');result[key]=value
        return result
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda value:(_ for _ in ()).throw(ValueError('nonfinite protected intake field')))


def intake_bytes(path,protected=False,check_only=False):
    path=Path(path)
    intake_require(path.is_absolute() and path.resolve()==path and not path.is_symlink(),'canonical intake file required')
    if protected:
        info=path.parent.stat()
        intake_require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o700,'private intake parent required')
    descriptor=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        info=os.fstat(descriptor)
        intake_require(stat.S_ISREG(info.st_mode) and info.st_nlink==1 and (check_only or info.st_size<=8000000),'intake file type/link/bound invalid')
        if protected:intake_require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'private intake file required')
        if check_only:return b''
        with os.fdopen(descriptor,'rb',closefd=False) as source:raw=source.read(8000001)
        intake_require(len(raw)<=8000000,'intake file bound exceeded');return raw
    finally:os.close(descriptor)


def installation_entry(config,sha):
    return {'repository':config['repository'],'authority_root':config['authority_root'],
            'candidate_root':config['candidate_root'],'contract':config['_contract_path'],
            'database':config['database'],'profile':config['profile'],'policy':config['policy'],'contract_sha256':sha}


def registry_paths():
    home=Path(pwd.getpwuid(os.getuid()).pw_dir)
    intake_require(home.is_absolute() and home.resolve()==home and home.is_dir(),'OS account home must be canonical')
    return home,home/'.local/state/factory-required-intake',home/'.factory-intake-required'


def read_installations():
    home,directory,latch=registry_paths();index=directory/'registry.json'
    if not directory.exists() and not latch.exists():return {}
    intake_require(directory.resolve()==directory and directory.is_dir() and directory.stat().st_uid==os.getuid()
                   and stat.S_IMODE(directory.stat().st_mode)==0o700 and latch.exists() and index.exists(),
                   'required installation registry lost; explicit recovery required')
    latch_raw=intake_bytes(latch);info=latch.stat()
    intake_require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'required installation latch not private')
    latched=intake_decode(latch_raw);records=intake_decode(intake_bytes(index,True))
    intake_require(isinstance(latched,dict) and set(latched)=={'schema_version','bindings'} and type(latched['schema_version']) is int
                   and latched['schema_version']==1 and isinstance(latched['bindings'],dict)
                   and isinstance(records,dict) and set(records)=={'schema_version','roots'} and type(records['schema_version']) is int
                   and records['schema_version']==1 and isinstance(records['roots'],dict)
                   and set(records['roots'])==set(latched['bindings']) and 0<len(records['roots'])<=1000,'required installation registry malformed')
    fields={'repository','authority_root','candidate_root','contract','database','profile','policy','contract_sha256'}
    for root,entry in records['roots'].items():
        intake_require(isinstance(entry,dict) and set(entry)==fields and entry['authority_root']==root
                       and isinstance(entry['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',entry['repository'])
                       and isinstance(entry['contract_sha256'],str) and re.fullmatch(r'[a-f0-9]{64}',entry['contract_sha256'])
                       and latched['bindings'][root]==entry['contract_sha256'],'required installation binding malformed')
        for name in fields-{'repository','contract_sha256'}:
            intake_require(isinstance(entry[name],str) and Path(entry[name]).is_absolute() and Path(entry[name]).resolve()==Path(entry[name]),'required installation path malformed')
    return records['roots']


def required_installation(root):
    return read_installations().get(str(Path(root).resolve()))


def register_installation(config,sha):
    home,directory,latch=registry_paths();index=directory/'registry.json';entry=installation_entry(config,sha)
    intake_require(home.stat().st_uid==os.getuid() and not stat.S_IMODE(home.stat().st_mode)&0o022,'OS account home ownership unsafe')
    for protected in (directory,latch):
        intake_require(all(Path(config[name])!=protected and Path(config[name]) not in protected.parents
                           for name in ('authority_root','candidate_root')),'required installation metadata overlaps candidate/authority')
    existing=read_installations()
    if entry['authority_root'] in existing:
        intake_require(existing[entry['authority_root']]==entry,'required installation binding cannot be rebound');return
    for parent in [home/'.local',home/'.local/state',directory]:
        intake_require(parent.resolve()==parent,'required installation parent linked')
        try:parent.mkdir(mode=0o700)
        except FileExistsError:pass
        else:
            owner=os.open(parent.parent,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
            try:os.fsync(owner)
            finally:os.close(owner)
        info=parent.stat();intake_require(info.st_uid==os.getuid() and not stat.S_IMODE(info.st_mode)&0o022,'required installation parent unsafe')
    intake_require(stat.S_IMODE(directory.stat().st_mode)==0o700,'required installation directory not private')
    descriptor=os.open(directory/'registry.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
    try:
        info=os.fstat(descriptor)
        intake_require(stat.S_ISREG(info.st_mode) and info.st_nlink==1 and info.st_uid==os.getuid()
                       and stat.S_IMODE(info.st_mode)==0o600,'required installation lock unsafe')
        fcntl.flock(descriptor,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if index.exists() or latch.exists():existing=read_installations()
        intake_require(entry['authority_root'] not in existing or existing[entry['authority_root']]==entry,'required installation binding cannot be rebound')
        existing={**existing,entry['authority_root']:entry}
        def atomic(path,value):
            fd,name=tempfile.mkstemp(prefix='.factory-required-',dir=path.parent)
            try:
                with os.fdopen(fd,'wb') as output:
                    output.write(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode());output.flush();os.fsync(output.fileno())
                os.replace(name,path)
                parent=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
                try:os.fsync(parent)
                finally:os.close(parent)
            finally:
                if os.path.exists(name):os.unlink(name)
        # Latch first: a lost/partial index update fences all affected entries.
        atomic(latch,{'schema_version':1,'bindings':{root:row['contract_sha256'] for root,row in existing.items()}})
        atomic(index,{'schema_version':1,'roots':existing})
    finally:os.close(descriptor)


def intake_boundary(root,database,policy_path,task,request_id=None,profile_path=None):
    """Stdlib-only bootstrap: no controller/helper execution before exact closure pins."""
    root=Path(root).resolve();database=Path(database);policy_path=Path(policy_path)
    installation=required_installation(root)
    if installation is not None:
        intake_require(str(database)==installation['database'] and str(policy_path)==installation['policy']
                       and (profile_path is None or str(profile_path)==installation['profile']),'required installation selection differs')
        profile_path=installation['profile']
    policy=intake_decode(intake_bytes(policy_path.resolve()))
    intake=policy.get('intake')
    if intake is not None:
        intake_require(isinstance(intake,dict) and set(intake)=={'enabled','dataflow','context_paths'}
                       and type(intake['enabled']) is bool,'intake policy enablement invalid')
    required=installation is not None or bool(intake and intake['enabled']);profile=None;descriptor=None
    if profile_path is not None:
        profile_path=Path(profile_path);profile=intake_decode(intake_bytes(profile_path,True))
        descriptor=profile.get('mandatory_intake')
        if descriptor is not None:
            intake_require(isinstance(descriptor,dict) and set(descriptor)=={'required','contract','database'}
                           and descriptor['required'] is True,'mandatory intake descriptor invalid')
            expected=policy.get('runtime',{}).get('routing_profile_sha256')
            intake_require(hashlib.sha256(json.dumps(profile,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode()).hexdigest()==expected
                           and profile.get('repository')==policy.get('repository'),'mandatory profile policy binding differs')
            intake_require(str(database)==descriptor['database'],'mandatory intake database differs');required=True
    if required:
        intake_require(database.exists(),'required intake store absent')
        intake_bytes(database,True,True)
    tables=set();binding=None;identity=None
    if database.exists():
        intake_require(database.is_file(),'runtime store is not a file')
        with closing(sqlite3.connect(database.resolve().as_uri()+'?mode=ro',uri=True)) as db:
            db.execute('PRAGMA trusted_schema=OFF')
            tables={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            detected='runtime_intake_required' in tables or any(name.startswith('intake_') for name in tables)
            required=required or detected
            if required:
                intake_require(not db.execute("SELECT name FROM sqlite_master WHERE type IN ('trigger','view')").fetchall(),'executable required intake schema rejected')
                intake_require({'runtime_intake_required','intake_identity'}<=tables,'required intake registry absent')
                rows=db.execute('SELECT repository,database_path,contract_path,contract_sha256,authority_root,candidate_root,profile_path,required FROM runtime_intake_required WHERE id=1').fetchall()
                intake_require(len(rows)==1,'required intake registry invalid');binding=rows[0]
                rows=db.execute('SELECT version,repository,contract_sha256,contract_path,paused FROM intake_identity WHERE id=1').fetchall()
                intake_require(len(rows)==1,'required intake identity absent');identity=rows[0]
    if not required:
        intake_require(request_id is None,'intake reference has no required store');return None
    intake_bytes(database,True,True)
    intake_require(isinstance(request_id,str) and re.fullmatch(r'[a-f0-9]{32}',request_id),'current intake request required')
    contract_path=Path(binding[2]);config=intake_decode(intake_bytes(contract_path,True))
    canonical=lambda value:json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)
    config_sha=hashlib.sha256(canonical(config).encode()).hexdigest()
    if installation is not None:
        selected={**config,'_contract_path':str(contract_path)}
        intake_require(installation==installation_entry(selected,config_sha),'required installation contract digest differs')
    expected=(config['repository'],config['database'],str(contract_path),config_sha,config['authority_root'],config['candidate_root'],config['profile'],1)
    intake_require(config['enabled'] is True and binding==expected and identity==(1,config['repository'],config_sha,str(contract_path),0),'required intake binding changed or paused')
    intake_require(str(database)==config['database'] and str(root)==config['authority_root'] and str(policy_path)==config['policy']
                   and config['repository']==policy.get('repository'),'foreign required intake selection')
    if profile_path is not None:intake_require(str(profile_path)==config['profile'],'required intake profile differs')
    if descriptor is not None:intake_require(descriptor['contract']==str(contract_path),'mandatory intake contract differs')
    roots=[Path(config[name]) for name in ('candidate_root','authority_root')]
    directory=Path(__file__).resolve().parent
    closure={str(directory/name) for name in ('factory-ledger.py','factory-intake.py','factory-runtime.py','factory-routing.py','factory-intake-scout.py','factory-bounded-process.py','factory-supervisor.py')}
    if policy.get('runtime',{}).get('execution') is not None:closure.add(str(directory/'factory-container.py'))
    files=config.get('trusted_files')
    intake_require(isinstance(files,dict) and closure|{config['profile'],config['policy']}<=set(files),'required controller closure pins missing')
    for name,sha in files.items():
        path=Path(name)
        intake_require(isinstance(sha,str) and re.fullmatch(r'[a-f0-9]{64}',sha)
                       and all(path!=base and base not in path.parents for base in roots),'required intake pin invalid or candidate-owned')
        intake_require(hashlib.sha256(intake_bytes(path,path==Path(config['profile']) or path==Path(config['policy']))).hexdigest()==sha,'required intake trusted bytes changed')
    # The exact controller/recursive helper bytes are now verified before loading.
    spec=importlib.util.spec_from_file_location('ledger_intake',directory/'factory-intake.py')
    controller=importlib.util.module_from_spec(spec);spec.loader.exec_module(controller)
    intake_controller=controller.Intake(contract_path);intake_controller.enqueue_scope(request_id,task)
    return intake_controller


def resource_contract(config, namespace, repository=None):
    services = config.get('services', [])
    if not isinstance(services, list):
        raise ValueError('service list required')
    names = set()
    for service in services:
        if (not isinstance(service, dict) or set(service) != {'name', 'kind'}
                or re.fullmatch(r'[a-z][a-z0-9_-]{0,31}', service['name']) is None
                or service['name'] in names or service['kind'] not in {'tcp', 'directory'}):
            raise ValueError('unsupported isolation declaration; use inherited TCP socket or private directory')
        names.add(service['name'])
    result = {'namespace': namespace, 'services': services}
    if 'output_limit_bytes' in config:
        limit=config['output_limit_bytes']
        if type(limit) is not int or not 1024<=limit<=8000000:
            raise ValueError('worker output bound invalid')
        result['output_limit_bytes']=limit
    if config.get('execution') is not None:
        module = importlib.util.spec_from_file_location('container_adapter', Path(__file__).with_name('factory-container.py'))
        adapter = importlib.util.module_from_spec(module); module.loader.exec_module(adapter)
        execution = adapter.validate(config['execution'])
        if services or execution['repository'] != repository:
            raise ValueError('offline containers require matching repository and no host service adapters')
        result['execution'] = execution
    return result


def parse_ledgers(root):
    tasks = {}
    paths = [root / 'tasks/TASKS.md', *sorted((root / 'tasks/archive').glob('TASKS-*.md'))]
    for path in paths:
        for line in path.read_text().splitlines():
            match = re.match(r'^- \[([ ~x!bs])\] (T-[1-9][0-9]*)\s*\|\s*(.*)$', line)
            if match is None:
                if re.match(r'^- \[.\] T-', line):
                    raise ValueError('malformed task marker')
                continue
            marker, task, rest = match.groups()
            if task in tasks:
                raise ValueError('duplicate ledger task ID')
            fields = {}
            for item in rest.split('|'):
                key, separator, value = item.strip().partition(':')
                if not separator or key in fields:
                    raise ValueError('malformed task fields')
                fields[key] = value.strip()
            deps = [dep.strip() for dep in fields.get('deps', '').split(',') if dep.strip()]
            if len(set(deps)) != len(deps) or any(re.fullmatch(r'T-[1-9][0-9]*', d) is None for d in deps):
                raise ValueError('invalid dependencies')
            tasks[task] = {'spec': fields.get('spec'), 'deps': sorted(deps), 'marker': marker}
    return tasks


def import_task(root, db_path, task, policy_path, *, intake_request=None, intake_profile=None):
    controller=intake_boundary(root,db_path,policy_path,task,intake_request,intake_profile)
    root = Path(root).resolve()
    lock = root / '.claude/state/locks/memory-plane.oslock'
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open('a') as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        policy = json.loads(Path(policy_path).read_text())
        records = parse_ledgers(root)
        selected = {}
        visiting = set()

        def visit(tid):
            if tid in visiting:
                raise ValueError('cyclic task dependencies')
            if tid in selected:
                return
            if tid not in records:
                raise ValueError('unknown dependency')
            row = records[tid]
            approved = policy.get('specs', {}).get(row['spec'])
            if not isinstance(approved, dict):
                raise ValueError('unapproved task specification')
            source = (root / approved['path']).resolve()
            if not source.is_relative_to(root) or not source.is_file():
                raise ValueError('spec source outside authority repository')
            content = source.read_bytes()
            digest = hashlib.sha256(content).hexdigest()
            if digest != approved.get('sha256') or re.search(rb'^status:\s*approved\s*$', content, re.M) is None:
                raise ValueError('approved spec bytes/status differ')
            acs = re.findall(r'\*\*(AC-\d+)\*\*', content.decode())
            scope = approved.get('allowed_paths')
            if not isinstance(scope, list) or not scope or any(not isinstance(p, str) or not p for p in scope):
                raise ValueError('invalid approved path scope')
            if not acs or len(set(acs)) != len(acs) or set(acs) != set(approved.get('ac_ids', [])) or not approved.get('allowed_paths'):
                raise ValueError('incomplete approved scope/ACs')
            visiting.add(tid)
            for dep in row['deps']:
                visit(dep)
            visiting.remove(tid)
            authority = {'spec': row['spec'], 'revision': digest, 'deps': row['deps'],
                         'ac_ids': sorted(acs), 'allowed_paths': approved['allowed_paths']}
            selected[tid] = authority

        visit(task)
        intent=None if controller is None else controller.enqueue_intent(intake_request,task)
        store = runtime.Store(db_path) if controller is None else controller.store
        if controller is not None:controller.enqueue_scope(intake_request,task)
        with store.transaction() as db:
            columns = {row['name'] for row in db.execute('PRAGMA table_info(tasks)')}
            if 'authority' not in columns:
                db.execute('ALTER TABLE tasks ADD COLUMN authority TEXT')
            for tid, authority in selected.items():
                if controller is not None and tid!=task:
                    dependency=db.execute('SELECT state FROM tasks WHERE id=?',(tid,)).fetchone()
                    intake_require(dependency is not None and dependency['state']=='merged','intake cannot enqueue unselected dependency')
                deps = json.dumps(authority['deps'])
                encoded = json.dumps(authority, sort_keys=True)
                existing = db.execute('SELECT * FROM tasks WHERE id=?', (tid,)).fetchone()
                if existing:
                    if (existing['revision'] != authority['revision'] or existing['deps'] != deps
                            or existing['authority'] != encoded):
                        raise ValueError('immutable task authority changed or unapproved legacy registration')
                else:
                    db.execute('INSERT INTO tasks(id,revision,deps,state,authority) VALUES(?,?,?,?,?)',
                               (tid, authority['revision'], deps, 'queued', encoded))
        if controller is not None:controller.complete_enqueue(*intent)
        return selected


def confirm_merge(db_path, task, revision, receipt):
    """Trusted receipt-adapter API; never called from a ledger marker or worker output."""
    if (set(receipt) != {'repository', 'pr', 'merge_sha'}
            or re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', receipt['repository']) is None
            or type(receipt['pr']) is not int or receipt['pr'] <= 0
            or re.fullmatch(r'[0-9a-f]{40}', receipt['merge_sha']) is None):
        raise ValueError('invalid merge receipt')
    store = runtime.Store(db_path)
    encoded = json.dumps(receipt, sort_keys=True)
    with store.transaction() as db:
        db.execute('CREATE TABLE IF NOT EXISTS delivery_receipts(task TEXT PRIMARY KEY, revision TEXT NOT NULL, receipt TEXT NOT NULL)')
        row = store.row(db, task)
        if row['revision'] != revision or row['owner'] is not None or row['state'] not in {'queued', 'merged'}:
            raise ValueError('receipt does not match an unclaimed dependency projection')
        existing = db.execute('SELECT * FROM delivery_receipts WHERE task=?', (task,)).fetchone()
        if existing and (existing['revision'] != revision or existing['receipt'] != encoded):
            raise ValueError('conflicting immutable delivery receipt')
        db.execute('INSERT OR IGNORE INTO delivery_receipts VALUES(?,?,?)', (task, revision, encoded))
        db.execute("UPDATE tasks SET state='merged' WHERE id=?", (task,))


def routing_contract(config, path, authority, candidate, database, task, requested_role=None):
    module = importlib.util.spec_from_file_location('routing', Path(__file__).with_name('factory-routing.py'))
    routing = importlib.util.module_from_spec(module); module.loader.exec_module(routing)
    profile = routing.protected(Path(path), [Path(authority), Path(candidate)])
    runtime_config = config.get('runtime', {})
    expected = runtime_config.get('routing_profile_sha256')
    if not isinstance(expected, str) or re.fullmatch(r'[a-f0-9]{64}', expected) is None:
        raise ValueError('protected routing profile approval required')
    if hashlib.sha256(routing.canonical(profile).encode()).hexdigest() != expected or profile['repository'] != config.get('repository'):
        raise ValueError('routing profile/repository differs from approved policy')
    roles = runtime_config.get('roles_by_task', {})
    role = roles.get(task)
    if role not in {'planning', 'implementation'} or requested_role not in {None, role}:
        raise ValueError('task role differs from approved routing')
    database = Path(database)
    if (not database.is_absolute() or database.resolve() != database or not database.parent.is_dir()
            or database.parent.stat().st_uid != os.getuid() or stat.S_IMODE(database.parent.stat().st_mode) != 0o700
            or any(root.resolve() == database.parent or root.resolve() in database.parents for root in (Path(authority), Path(candidate)))):
        raise ValueError('routed runtime database must be private outside authority/candidate')
    if database.exists():
        if not database.is_file() or database.stat().st_uid != os.getuid() or stat.S_IMODE(database.stat().st_mode) != 0o600:
            raise ValueError('routed runtime database owner/mode differs')
        with closing(sqlite3.connect(database)) as db:
            names = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if 'runtime_route_repository' in names:
                if db.execute('SELECT repository FROM runtime_route_repository WHERE id=1').fetchall() != [(profile['repository'],)]:
                    raise ValueError('foreign routed runtime store')
            elif 'tasks' in names and db.execute('SELECT COUNT(*) FROM tasks').fetchone()[0]:
                raise ValueError('legacy nonempty store needs an explicit namespace migration')
    return routing, profile, role


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--authority-root', required=True)
    parser.add_argument('--policy', required=True)
    parser.add_argument('--db', required=True)
    parser.add_argument('--task', required=True)
    parser.add_argument('--cwd')
    parser.add_argument('--attempts')
    parser.add_argument('--timeout', type=float, default=1800)
    parser.add_argument('--routing-config')
    parser.add_argument('--intake-request')
    parser.add_argument('--intake-profile')
    parser.add_argument('--role', choices=['planning', 'implementation'])
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    intake_boundary(args.authority_root,args.db,args.policy,args.task,args.intake_request,args.intake_profile or args.routing_config)
    config = json.loads(Path(args.policy).read_text())
    resources = resource_contract(config.get('runtime', {}), 'assigned-at-claim', config.get('repository'))
    if args.routing_config:
        if command or not args.cwd or not args.attempts:
            parser.error('routed worker requires cwd/attempts and forbids caller command override')
        routing, profile, role = routing_contract(config, args.routing_config, args.authority_root, args.cwd, args.db, args.task, args.role)
        previous_umask = os.umask(0o077)
        try:
            imported = import_task(args.authority_root, args.db, args.task, args.policy,intake_request=args.intake_request,intake_profile=args.intake_profile or args.routing_config)
            result = routing.run(profile, role, 'local', Path(args.cwd), Path(args.db), args.task, Path(args.attempts), timeout=args.timeout, resources=resources)
        finally:
            os.umask(previous_umask)
        print(json.dumps({'imported': list(imported), 'delivery_inferred': False, **result}))
        return result.get('exit_code', 2)
    if args.role or (command and config.get('runtime', {}).get('routing_profile_sha256')):
        parser.error('approved routed task requires its protected profile; command bypass forbidden')
    imported = import_task(args.authority_root, args.db, args.task, args.policy,intake_request=args.intake_request,intake_profile=args.intake_profile or args.routing_config)
    if not command:
        print(json.dumps({'imported': list(imported), 'delivery_inferred': False}))
        return 0
    if not args.cwd or not args.attempts:
        parser.error('worker cwd and attempts directory required')
    module = importlib.util.spec_from_file_location('supervisor', Path(__file__).with_name('factory-supervisor.py'))
    supervisor = importlib.util.module_from_spec(module); module.loader.exec_module(supervisor)
    return supervisor.supervise(args.db, args.task, command, args.cwd, args.attempts,
                                timeout=args.timeout, resources=resources)


if __name__ == '__main__':
    sys.exit(main())
