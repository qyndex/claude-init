#!/usr/bin/env python3
"""Private request bindings. Routing assessments never grant task authority."""
import hashlib
import json
import os
import pwd
from pathlib import Path
import re
import stat


DEFAULT_LIMITS = {'request_chars':20000, 'context_bytes':500000,
                  'output_bytes':65536, 'assessment_seconds':60}
CONTRACT_FIELDS = {'schema_version','enabled','repository','candidate_root',
                   'authority_root','database','profile','policy','trusted_files','limits'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False, allow_nan=False)


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, 'duplicate intake field')
        result[key] = value
    return result


def decode(raw):
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda value: require(False, 'nonfinite intake value'))


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def private(path, directory=False):
    path = Path(path)
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink(),
            'canonical private intake path required')
    info = path.stat()
    require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==(0o700 if directory else 0o600)
            and (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode) and info.st_nlink==1),
            'private intake owner/mode/link invalid')
    return path


def read_file(path, maximum, protected=False):
    path = Path(path)
    if protected:
        private(path)
    descriptor = os.open(path, os.O_RDONLY|getattr(os, 'O_NOFOLLOW', 0)|getattr(os, 'O_NONBLOCK', 0))
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink==1 and info.st_size<=maximum,
                'intake file type/size invalid')
        if protected:
            require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,
                    'private intake file changed')
        with os.fdopen(descriptor, 'rb', closefd=False) as source:
            raw = source.read(maximum+1)
        require(len(raw)<=maximum, 'intake file bound exceeded')
        return raw
    finally:
        os.close(descriptor)


def validate_contract(value):
    require(isinstance(value, dict) and set(value)==CONTRACT_FIELDS
            and type(value['schema_version']) is int and value['schema_version']==1
            and type(value['enabled']) is bool, 'intake contract schema invalid')
    limits = value['limits']
    require(isinstance(limits, dict) and set(limits)==set(DEFAULT_LIMITS), 'intake budgets required')
    for name, maximum in DEFAULT_LIMITS.items():
        require(type(limits[name]) is int and (1024 if name=='output_bytes' else 1)<=limits[name]<=maximum,
                'intake finite budget invalid')
    if not value['enabled']:
        require(all(value[name] is None for name in CONTRACT_FIELDS-{'schema_version','enabled','limits','trusted_files'})
                and value['trusted_files']=={}, 'disabled intake template must be neutral')
        return
    require(isinstance(value['repository'], str)
            and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', value['repository']), 'intake repository invalid')
    for name in ('candidate_root','authority_root','database','profile','policy'):
        require(isinstance(value[name], str) and Path(value[name]).is_absolute()
                and Path(value[name]).resolve()==Path(value[name]), 'intake canonical binding invalid')
    require(isinstance(value['trusted_files'], dict) and bool(value['trusted_files']), 'intake pins missing')
    for name, sha in value['trusted_files'].items():
        require(isinstance(name, str) and Path(name).is_absolute() and Path(name).resolve()==Path(name)
                and isinstance(sha, str) and re.fullmatch(r'[a-f0-9]{64}', sha), 'intake pin invalid')
    require({value['profile'],value['policy'],str(Path(__file__).resolve()),str(Path(__file__).with_name('factory-runtime.py').resolve())}<=set(value['trusted_files']),
            'controller/runtime/profile/policy must be pinned')


def load_contract(path):
    path = private(path)
    private(path.parent, True)
    value = decode(read_file(path, 65536, True))
    validate_contract(value)
    if not value['enabled']:
        return value
    roots = [Path(value[name]) for name in ('candidate_root','authority_root')]
    for root in roots:
        require(root.is_dir() and root!=path.parent and root not in path.parents
                and path.parent not in root.parents, 'intake contract cannot overlap candidate/authority')
    database = Path(value['database'])
    require(database.parent==path.parent, 'intake database must share private contract directory')
    if database.exists():
        private(database)
    for name in ('profile','policy'):
        source = private(value[name]); private(source.parent, True)
        require(all(source!=root and root not in source.parents for root in roots),
                'protected intake authority cannot be candidate data')
    for name, expected in value['trusted_files'].items():
        source = Path(name)
        require(all(root not in source.parents and source!=root for root in roots),
                'intake executable/policy pin cannot be candidate-owned')
        require(digest(read_file(source, 8000000))==expected, 'intake trusted bytes changed')
    return value


def header_values(raw, field):
    """Parse the supported flat frontmatter; ambiguous/unsupported headers fail closed."""
    header=re.match(rb'\A---\r?\n(.*?)\r?\n---(?:\r?\n|\Z)',raw,re.S)
    if header is None:return []
    values={}
    for line in header[1].splitlines():
        if not line.strip() or line.startswith(b'#'):continue
        entry=re.fullmatch(rb'([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)',line)
        if entry is None or entry[1] in values:return []
        value=entry[2].strip()
        if value.startswith((b'"',b"'")):
            quoted=re.fullmatch(rb'([\'"])(.*?)\1(?:[ \t]+#[^\r\n]*)?',value)
            if quoted is None:return []
            if quoted[1]==b'"':
                try:value=json.loads(quoted[1]+quoted[2]+quoted[1]).encode('utf-8')
                except (ValueError,UnicodeError):return []
            else:
                if re.fullmatch(rb"(?:[^']|'')*",quoted[2]) is None:return []
                value=quoted[2].replace(b"''",b"'")
        else:
            value=re.split(rb'[ \t]+#',value,maxsplit=1)[0].strip()
            if (re.search(rb':[ \t]',value) or value.startswith((b'|',b'>',b'&',b'*'))
                    or (value.startswith(b'[') and not value.endswith(b']'))
                    or (value.startswith(b'{') and not value.endswith(b'}'))):return []
        values[entry[1]]=value
    return [] if field not in values else [values[field]]


def installation_lookup(root):
    """Read fixed OS-account metadata without executing an unpinned dependency."""
    home=Path(pwd.getpwuid(os.getuid()).pw_dir)
    require(home.is_absolute() and home.resolve()==home and home.is_dir(),'OS account home must be canonical')
    directory=home/'.local/state/factory-required-intake';latch=home/'.factory-intake-required'
    if not directory.exists() and not latch.exists():return None
    private(directory,True)
    require(latch.exists() and (directory/'registry.json').exists(),'required installation registry lost; explicit recovery required')
    latched=decode(read_file(latch,8000000,True));records=decode(read_file(directory/'registry.json',8000000,True))
    require(isinstance(latched,dict) and set(latched)=={'schema_version','bindings'} and type(latched['schema_version']) is int
            and latched['schema_version']==1 and isinstance(latched['bindings'],dict)
            and isinstance(records,dict) and set(records)=={'schema_version','roots'} and type(records['schema_version']) is int
            and records['schema_version']==1 and isinstance(records['roots'],dict)
            and set(records['roots'])==set(latched['bindings']) and 0<len(records['roots'])<=1000,'required installation registry malformed')
    fields={'repository','authority_root','candidate_root','contract','database','profile','policy','contract_sha256'}
    for name,entry in records['roots'].items():
        require(isinstance(entry,dict) and set(entry)==fields and entry['authority_root']==name
                and isinstance(entry['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',entry['repository'])
                and isinstance(entry['contract_sha256'],str) and re.fullmatch(r'[a-f0-9]{64}',entry['contract_sha256'])
                and latched['bindings'][name]==entry['contract_sha256'],'required installation binding malformed')
        for key in fields-{'repository','contract_sha256'}:
            require(isinstance(entry[key],str) and Path(entry[key]).is_absolute()
                    and Path(entry[key]).resolve()==Path(entry[key]),'required installation path malformed')
    return records['roots'].get(str(Path(root).resolve()))


class Intake:
    """Owner-only additive projection bound to exact protected contract bytes."""
    def __init__(self, path):
        from contextlib import closing
        import importlib.util
        import sqlite3
        self.path = private(path)
        self.config = load_contract(self.path)
        require(self.config['enabled'], 'intake entry disabled')
        self.database = Path(self.config['database'])
        self.binding = digest(canonical(self.config).encode())
        profile=decode(read_file(self.config['profile'],65536,True))
        mandatory=profile.get('mandatory_intake')
        selected=installation_lookup(self.config['authority_root'])
        installation_ledger=None
        if mandatory is not None or selected is not None:
            ledger_path=Path(__file__).with_name('factory-ledger.py').resolve()
            require(str(ledger_path) in self.config['trusted_files'],'required installation ledger pin missing')
            module=importlib.util.spec_from_file_location('intake_installation_ledger',ledger_path)
            installation_ledger=importlib.util.module_from_spec(module);module.loader.exec_module(installation_ledger)
            require(installation_ledger.required_installation(self.config['authority_root'])==selected,'required installation changed during bootstrap')
            if selected is not None:
                require(selected==installation_ledger.installation_entry({**self.config,'_contract_path':str(self.path)},self.binding)
                        and self.database.exists(),'known required installation lost or changed; explicit recovery required')
            if mandatory is not None:
                require(isinstance(mandatory,dict) and set(mandatory)=={'required','contract','database'} and mandatory['required'] is True
                        and mandatory['contract']==str(self.path) and mandatory['database']==str(self.database),'required installation descriptor differs')
        if mandatory is not None:
            installation_ledger.register_installation({**self.config,'_contract_path':str(self.path)},self.binding)

        if not self.database.exists():
            descriptor = os.open(self.database, os.O_RDWR|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0), 0o600)
            os.close(descriptor)
        private(self.database)
        with closing(sqlite3.connect(self.database)) as db:
            db.execute('PRAGMA trusted_schema=OFF')
            require(not db.execute("SELECT name FROM sqlite_master WHERE type IN ('trigger','view')").fetchall(),
                    'executable intake schema rejected')
            tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if any(name.startswith('intake_') for name in tables) or 'runtime_intake_required' in tables:
                require({'intake_identity','runtime_intake_required'}<=tables,'required intake registry missing; explicit recovery required')
                row=db.execute('SELECT repository,database_path,contract_path,contract_sha256,authority_root,candidate_root,profile_path,required FROM runtime_intake_required WHERE id=1').fetchall()
                require(row==[self.required_binding()], 'required intake store binding changed')
            bindings = []
            for table in ('runtime_route_repository','worker_effect_repository','feedback_checkpoint_identity','intake_identity'):
                if table in tables:
                    observed = db.execute(f'SELECT repository FROM {table} WHERE id=1').fetchall()
                    require(observed in ([],[(self.config['repository'],)]), 'foreign intake database namespace')
                    bindings.extend(observed)
            if tables and 'intake_identity' not in tables:
                require(bool(bindings),
                        'nonempty intake store requires bound namespace')
            if 'intake_identity' in tables:
                row = db.execute('SELECT version,contract_sha256,contract_path FROM intake_identity WHERE id=1').fetchall()
                require(row==[(1,self.binding,str(self.path))], 'intake version/contract binding changed')
        module = importlib.util.spec_from_file_location('intake_runtime',Path(__file__).with_name('factory-runtime.py'))
        runtime = importlib.util.module_from_spec(module); module.loader.exec_module(runtime)
        self.store = runtime.Store(self.database)
        with self.transaction() as db:
            schema = '''
                CREATE TABLE IF NOT EXISTS runtime_intake_required (
                    id INTEGER PRIMARY KEY CHECK(id=1),repository TEXT NOT NULL,database_path TEXT NOT NULL,
                    contract_path TEXT NOT NULL,contract_sha256 TEXT NOT NULL,authority_root TEXT NOT NULL,
                    candidate_root TEXT NOT NULL,profile_path TEXT NOT NULL,required INTEGER NOT NULL CHECK(required=1));
                CREATE TABLE IF NOT EXISTS intake_identity (
                    id INTEGER PRIMARY KEY CHECK(id=1),version INTEGER NOT NULL,
                    repository TEXT NOT NULL,contract_sha256 TEXT NOT NULL,
                    contract_path TEXT NOT NULL,paused INTEGER NOT NULL CHECK(paused IN (0,1)));
                CREATE TABLE IF NOT EXISTS intake_sessions (
                    id TEXT PRIMARY KEY,sequence INTEGER NOT NULL,native_session TEXT UNIQUE NOT NULL);
                CREATE TABLE IF NOT EXISTS intake_requests (
                    id TEXT PRIMARY KEY,source_key TEXT UNIQUE NOT NULL,document TEXT NOT NULL,
                    revision TEXT NOT NULL,status TEXT NOT NULL,decision TEXT,
                    assessment_count INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS intake_request_sessions (
                    request_id TEXT PRIMARY KEY REFERENCES intake_requests(id),session TEXT NOT NULL,
                    sequence INTEGER NOT NULL,UNIQUE(session,sequence));
                CREATE TABLE IF NOT EXISTS intake_delivery_tokens (
                    token TEXT PRIMARY KEY,request_id TEXT UNIQUE NOT NULL REFERENCES intake_requests(id));
                CREATE TABLE IF NOT EXISTS intake_pending_native (
                    request_id TEXT PRIMARY KEY REFERENCES intake_requests(id),
                    native_session TEXT NOT NULL,payload_sha256 TEXT NOT NULL,
                    launch_nonce TEXT NOT NULL,state TEXT NOT NULL,expires_at REAL NOT NULL);
                CREATE UNIQUE INDEX IF NOT EXISTS intake_one_pending
                    ON intake_pending_native(native_session) WHERE state='pending';
                CREATE TABLE IF NOT EXISTS intake_actions (
                    id TEXT PRIMARY KEY,request_id TEXT NOT NULL REFERENCES intake_requests(id),
                    document TEXT NOT NULL,status TEXT NOT NULL,result TEXT);
                CREATE TABLE IF NOT EXISTS intake_assessments (
                    request_id TEXT PRIMARY KEY REFERENCES intake_requests(id),
                    revision TEXT NOT NULL,status TEXT NOT NULL,result TEXT,reason TEXT);
                CREATE TABLE IF NOT EXISTS intake_proposals (
                    id TEXT PRIMARY KEY,head_request TEXT NOT NULL REFERENCES intake_requests(id),
                    number INTEGER NOT NULL,state TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS intake_proposal_revisions (
                    request_id TEXT PRIMARY KEY REFERENCES intake_requests(id),proposal_id TEXT NOT NULL REFERENCES intake_proposals(id),
                    number INTEGER NOT NULL,parent_request TEXT,request_revision TEXT NOT NULL,kind TEXT NOT NULL,
                    UNIQUE(proposal_id,number));
                CREATE TABLE IF NOT EXISTS intake_decision_bindings (
                    request_id TEXT PRIMARY KEY REFERENCES intake_requests(id),document TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS intake_events (
                    sequence INTEGER PRIMARY KEY,request_id TEXT,event TEXT NOT NULL);
            '''
            for statement in schema.split(';'):
                if statement.strip():
                    db.execute(statement)
            db.execute('INSERT OR IGNORE INTO runtime_intake_required VALUES(1,?,?,?,?,?,?,?,?)',self.required_binding())
            db.execute('INSERT OR IGNORE INTO intake_identity VALUES(1,1,?,?,?,0)',
                       (self.config['repository'],self.binding,str(self.path)))

    def required_binding(self):
        return (self.config['repository'],str(self.database),str(self.path),self.binding,
                self.config['authority_root'],self.config['candidate_root'],self.config['profile'],1)

    def transaction(self):
        return self.store.transaction()

    def ready(self):
        require(load_contract(self.path)==self.config, 'intake protected contract changed')
        private(self.database)
        with self.transaction() as db:
            require(not db.execute("SELECT name FROM sqlite_master WHERE type IN ('trigger','view')").fetchall(),
                    'executable intake schema rejected')
            required=db.execute('SELECT repository,database_path,contract_path,contract_sha256,authority_root,candidate_root,profile_path,required FROM runtime_intake_required WHERE id=1').fetchall()
            require([tuple(row) for row in required]==[self.required_binding()],'required intake registry changed')
            row = db.execute('SELECT version,repository,contract_sha256,contract_path,paused FROM intake_identity WHERE id=1').fetchall()
            require([tuple(value) for value in row]==[(1,self.config['repository'],self.binding,str(self.path),0)],
                    'intake unavailable or paused')

    def execution_enabled(self):
        self.ready()
        with self.transaction() as db:
            rows=db.execute('SELECT paused FROM control WHERE id=1').fetchall()
            require([tuple(row) for row in rows] in ([(0,)],[(1,)]),'intake runtime pause control invalid')
            return rows[0]['paused']==0

    def execution_ready(self):
        require(self.execution_enabled(),'intake runtime globally paused')

    def pause(self):
        with self.transaction() as db:
            db.execute('UPDATE intake_identity SET paused=1 WHERE id=1')


    def new_session(self):
        import uuid
        self.ready()
        identity = uuid.uuid4().hex
        with self.transaction() as db:
            db.execute('INSERT INTO intake_sessions VALUES(?,0,?)',(identity,str(uuid.uuid4())))
        return identity

    @staticmethod
    def receipt(identity, revision, token):
        return {'request_id':identity,'revision':revision,'delivery_token':token}

    def submit_console(self, session, text, ref, *, parent=None, delivery_token=None, _lineage_kind="clarification"):
        import uuid
        self.ready()
        require(hex_value(session,32), 'unknown console session')
        require(_lineage_kind in {'clarification','source_edit'} and (_lineage_kind!='source_edit' or parent is not None),'proposal revision kind invalid')
        request = {'schema_version':1,'source_kind':'claude','origin':'human','session':session,
                   'submission_key':None,'delivery_token':delivery_token,'source_revision':'pending',
                   'parent_request':parent,'actor':'local:'+str(os.getuid()),
                   'repository':self.config['repository'],'ref':ref,'text':text}
        validate_request(request,self.config['limits'])
        with self.transaction() as db:
            row = db.execute('SELECT sequence FROM intake_sessions WHERE id=?',(session,)).fetchone()
            require(row is not None, 'unknown console session')
            require(db.execute('SELECT paused FROM intake_identity WHERE id=1').fetchone()[0]==0,
                    'intake paused before submission')
            if delivery_token is not None:
                previous = db.execute('SELECT id,revision,document FROM intake_requests WHERE id=(SELECT request_id FROM intake_delivery_tokens WHERE token=?)',
                                      (delivery_token,)).fetchone()
                require(previous is not None, 'unissued delivery token')
                document = decode(previous['document'])
                require(all(document[name]==request[name] for name in REQUEST_FIELDS-{'source_revision','submission_key'}),
                        'conflicting intake delivery retry')
                if parent is not None:
                    linked=db.execute('SELECT kind FROM intake_proposal_revisions WHERE request_id=?',(previous['id'],)).fetchone()
                    require(linked is not None and linked['kind']==_lineage_kind,'conflicting proposal revision retry')
                return self.receipt(previous['id'],previous['revision'],delivery_token)
            lineage=None
            if parent is not None:
                previous = db.execute('SELECT document,revision,status,decision FROM intake_requests WHERE id=?',(parent,)).fetchone()
                require(previous is not None, 'unknown intake parent')
                document = decode(previous['document'])
                require(all(document[name]==request[name] for name in ('session','actor','repository','ref','source_kind')),
                        'foreign intake parent')
                require(digest(canonical(document).encode())==previous['revision'],'parent request bytes differ')
                lineage=db.execute('SELECT r.*,p.head_request,p.state,p.number AS head_number FROM intake_proposal_revisions r JOIN intake_proposals p ON p.id=r.proposal_id WHERE r.request_id=?',(parent,)).fetchone()
                require(lineage is not None and lineage['head_request']==parent and lineage['state']=='active'
                        and lineage['request_revision']==previous['revision'] and previous['decision'] is not None,'parent proposal unknown, unresolved, blocked or superseded')
                settled=decode(previous['decision']);validate_decision(settled)
                require(settled['request_id']==parent and settled['revision']==previous['revision']
                        and settled['disposition'] in {'new_feature','changed_requirement','defect','clarify'}
                        and settled['next_action'] in {'draft','question'},'parent is not a settled proposal or clarification')
            sequence = row['sequence']+1
            identity = uuid.uuid4().hex
            token = uuid.uuid4().hex
            key = 'claude:'+session+':'+str(sequence)
            request.update(submission_key=key,source_revision=str(sequence),delivery_token=token)
            revision = digest(canonical(request).encode())
            db.execute('UPDATE intake_sessions SET sequence=? WHERE id=?',(sequence,session))
            db.execute('INSERT INTO intake_requests(id,source_key,document,revision,status) VALUES(?,?,?,?,?)',
                       (identity,key,canonical(request),revision,'submitted'))
            db.execute('INSERT INTO intake_request_sessions VALUES(?,?,?)',(identity,session,sequence))
            if lineage is not None:
                number=lineage['head_number']+1
                db.execute('INSERT INTO intake_proposal_revisions VALUES(?,?,?,?,?,?)',(identity,lineage['proposal_id'],number,parent,revision,_lineage_kind))
                db.execute("UPDATE intake_proposals SET head_request=?,number=?,state='pending' WHERE id=?",(identity,number,lineage['proposal_id']))
                db.execute('INSERT INTO intake_events(request_id,event) VALUES(?,?)',(parent,'proposal_revision_superseded'))
            db.execute('INSERT INTO intake_delivery_tokens VALUES(?,?)',(token,identity))
            db.execute('INSERT INTO intake_events(request_id,event) VALUES(?,?)',(identity,'submitted'))
            return self.receipt(identity,revision,token)


    @staticmethod
    def clock(now):
        import math
        import time
        value = time.time() if now is None else now
        require(type(value) in {int,float} and math.isfinite(value) and value>=0, 'invalid intake clock')
        return value

    def bind_native(self, request_id, *, now=None):
        import uuid
        self.ready()
        now = self.clock(now)
        nonce = uuid.uuid4().hex
        with self.transaction() as db:
            request = db.execute('SELECT document FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(request is not None, 'unknown pending request')
            value = decode(request['document'])
            require(value['source_kind']=='claude', 'native binding requires console ingress')
            session = db.execute('SELECT native_session FROM intake_sessions WHERE id=?',(value['session'],)).fetchone()
            require(session is not None, 'unknown native session')
            require(not db.execute('SELECT 1 FROM intake_pending_native WHERE request_id=? OR (native_session=? AND state IN (\'pending\',\'unknown\'))',
                                   (request_id,session['native_session'])).fetchone(), 'native ingress unresolved or already issued')
            db.execute('INSERT INTO intake_pending_native VALUES(?,?,?,?,?,?)',
                       (request_id,session['native_session'],digest(value['text'].encode()),nonce,'pending',now+90))
            return {'native_session':session['native_session'],'launch_nonce':nonce}

    def consume_native(self, native_session, prompt, cwd, *, now=None):
        self.ready()
        now = self.clock(now)
        require(Path(cwd)==Path(self.config['candidate_root']) and Path(cwd).resolve()==Path(cwd),
                'native candidate binding mismatch')
        require(string(prompt,self.config['limits']['request_chars']), 'native prompt bound exceeded')
        with self.transaction() as db:
            row = db.execute("SELECT * FROM intake_pending_native WHERE native_session=? AND state='pending'",
                             (native_session,)).fetchone()
            require(row is not None and row['expires_at']>now and row['payload_sha256']==digest(prompt.encode()),
                    'unsupported or conflicting native callback')
            db.execute("UPDATE intake_pending_native SET state='consumed' WHERE request_id=?",(row['request_id'],))
            db.execute('INSERT INTO intake_events(request_id,event) VALUES(?,?)',(row['request_id'],'native_consumed'))
            return row['request_id']

    def native_unknown(self, request_id):
        with self.transaction() as db:
            db.execute("UPDATE intake_pending_native SET state='unknown' WHERE request_id=? AND state='pending'",(request_id,))


    def eligible(self):
        if not self.execution_enabled():return []
        policy = decode(read_file(self.config['policy'],65536,True))
        require(policy.get('repository')==self.config['repository'], 'foreign approved policy')
        root = Path(self.config['authority_root'])
        ledger = root/'tasks/TASKS.md'
        if not ledger.is_file():
            return []
        text = read_file(ledger,self.config['limits']['context_bytes']).decode()
        result = []
        for task,spec_id,tail in re.findall(r'^- \[ \] (T-[1-9][0-9]*)\s*\|\s*spec:(\d{3})\s*\|(.*)$',text,re.M):
            approved = policy.get('specs',{}).get(spec_id)
            if not isinstance(approved,dict) or not relative(approved.get('path')):
                continue
            if 'task_ids' in approved:
                allowed = approved['task_ids']
                require(isinstance(allowed,list) and all(isinstance(value,str) and re.fullmatch(r'T-[1-9][0-9]*',value) for value in allowed), 'approved task allowlist invalid')
                if task not in allowed:
                    continue
            source = root/approved['path']
            if source.resolve()!=source or not source.is_file():
                continue
            raw = read_file(source,self.config['limits']['context_bytes'])
            acs = re.findall(r'\*\*(AC-\d+)\*\*',raw.decode())
            if (digest(raw)!=approved.get('sha256') or header_values(raw,b'status')!=[b'approved']
                    or not acs or len(set(acs))!=len(acs) or set(acs)!=set(approved.get('ac_ids',[]))
                    or not approved.get('allowed_paths') or open_questions(raw.decode())):
                continue
            plan = root/'plans/active'/source.name
            if plan.resolve()!=plan or not plan.is_file():
                continue
            plan_raw = read_file(plan,self.config['limits']['context_bytes'])
            if header_values(plan_raw,b'status')!=[b'approved'] or header_values(plan_raw,b'spec')!=[approved['path'].encode()]:
                continue
            deps = re.search(r'(?:^|\|)\s*deps:\s*([^|]*)',tail)
            dependencies = [value.strip() for value in deps[1].split(',') if value.strip()] if deps else []
            with self.transaction() as db:
                rows = [db.execute('SELECT state FROM tasks WHERE id=?',(dep,)).fetchone() for dep in dependencies]
                current = db.execute('SELECT state FROM tasks WHERE id=?',(task,)).fetchone()
            if any(row is None or row['state']!='merged' for row in rows) or (current is not None and current['state']!='queued'):
                continue
            result.append({'task':task,'spec':approved['path'],'plan':str(plan.relative_to(root)),
                           'evidence':[{'kind':'spec','ref':approved['path'],'sha256':digest(raw)},
                                       {'kind':'plan','ref':str(plan.relative_to(root)),'sha256':digest(plan_raw)},
                                       {'kind':'repository','ref':'tasks/TASKS.md','sha256':digest(text.encode())}]})
        return result if self.execution_enabled() else []

    def proposal_revision(self, request_id):
        self.ready()
        with self.transaction() as db:
            row=db.execute('SELECT r.*,p.head_request,p.state FROM intake_proposal_revisions r JOIN intake_proposals p ON p.id=r.proposal_id WHERE r.request_id=?',(request_id,)).fetchone()
            require(row is not None,'unknown proposal lineage')
            source=db.execute('SELECT revision FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(source is not None and source['revision']==row['request_revision'],'proposal request revision differs')
            return {'proposal_id':row['proposal_id'],'number':row['number'],'parent_request':row['parent_request'],
                    'kind':row['kind'],'request_revision':row['request_revision'],'current':row['head_request']==request_id,'state':row['state']}

    @staticmethod
    def settle_proposal(db, request_id, request, result):
        wanted=result['disposition'] in {'new_feature','changed_requirement','defect','clarify'} and result['next_action'] in {'draft','question'}
        bound=db.execute('SELECT * FROM intake_proposal_revisions WHERE request_id=?',(request_id,)).fetchone()
        if bound is None:
            if not wanted:return
            require(request['parent_request'] is None,'proposal parent binding missing')
            db.execute("INSERT INTO intake_proposals VALUES(?,?,1,'active')",(request_id,request_id))
            db.execute("INSERT INTO intake_proposal_revisions VALUES(?,?,1,NULL,?,'initial')",(request_id,request_id,result['revision']))
        else:
            head=db.execute('SELECT head_request FROM intake_proposals WHERE id=?',(bound['proposal_id'],)).fetchone()
            require(head is not None and head['head_request']==request_id and bound['request_revision']==result['revision'],'proposal head changed before outcome')
            state='active' if wanted else 'blocked' if result['disposition'] in {'blocked','unsupported'} else 'resolved'
            db.execute('UPDATE intake_proposals SET state=? WHERE id=?',(state,bound['proposal_id']))

    def edit_console(self, session, source_request, text, ref, *, delivery_token=None):
        return self.submit_console(session,text,ref,parent=source_request,delivery_token=delivery_token,_lineage_kind='source_edit')

    def proposal_context(self, request_id, request):
        """Bounded minimal prior human text, without delivery/actor/session data."""
        with self.transaction() as db:
            current=db.execute('SELECT * FROM intake_proposal_revisions WHERE request_id=?',(request_id,)).fetchone()
            if current is None or current['number']==1:return None
            head=db.execute('SELECT head_request FROM intake_proposals WHERE id=?',(current['proposal_id'],)).fetchone()
            require(head is not None and head['head_request']==request_id,'proposal revision is superseded')
            require(current['kind'] in {'clarification','source_edit'} and current['parent_request']==request['parent_request']
                    and current['request_revision']==digest(canonical(request).encode()),'current proposal lineage differs')
            rows=db.execute('SELECT p.*,r.document,r.revision FROM intake_proposal_revisions p JOIN intake_requests r ON r.id=p.request_id WHERE p.proposal_id=? AND p.number<? ORDER BY p.number LIMIT 1001',(current['proposal_id'],current['number']))
            history=[]
            for index,row in enumerate(rows):
                require(index<1000 and row['number']==index+1,'proposal history incomplete or oversized')
                prior=decode(row['document']);validate_request(prior,self.config['limits'])
                require(row['revision']==row['request_revision']==digest(canonical(prior).encode())
                        and prior['parent_request']==row['parent_request']
                        and all(prior[name]==request[name] for name in ('session','actor','repository','ref','source_kind')),'proposal history binding differs')
                require((index==0 and row['kind']=='initial' and row['parent_request'] is None)
                        or (index>0 and row['kind'] in {'clarification','source_edit'} and row['parent_request']==history[-1]['request_id']),
                        'proposal revision graph is ambiguous')
                history.append({'request_id':row['request_id'],'revision':row['revision'],'text':prior['text'],
                                'kind':row['kind'],'parent_request':row['parent_request']})
                require(len(canonical(history).encode())<=self.config['limits']['context_bytes'],'proposal history byte budget exceeded')
            require(len(history)==current['number']-1,'proposal history missing')
            require(current['parent_request']==history[-1]['request_id'],'proposal current parent differs')
            return {'proposal_id':current['proposal_id'],'number':current['number'],'kind':current['kind'],
                    'parent_request':current['parent_request'],'history':history}

    def session_context(self, request_id, request):
        """Latest relevant earlier human request from this exact console session."""
        with self.transaction() as db:
            current=db.execute('SELECT session,sequence FROM intake_request_sessions WHERE request_id=?',(request_id,)).fetchone()
            if current is None:
                # Pre-projection/unsupported adapters cannot establish a binding.
                return None
            require(current['session']==request['session'],'continuation session projection differs')
            rows=db.execute('SELECT r.id,r.document,r.revision,r.status,r.decision,s.sequence FROM intake_request_sessions s '
                            'JOIN intake_requests r ON r.id=s.request_id WHERE s.session=? AND s.sequence<? '
                            'ORDER BY s.sequence DESC LIMIT 1001',(current['session'],current['sequence']))
            consumed=0
            for index,row in enumerate(rows):
                require(index<1000,'continuation history count exceeded')
                consumed+=len(row['document'].encode())+len((row['decision'] or '').encode())
                require(consumed<=self.config['limits']['context_bytes'],'continuation history byte bound exceeded')
                prior=decode(row['document']);validate_request(prior,self.config['limits'])
                require(digest(canonical(prior).encode())==row['revision'] and prior['source_revision']==str(row['sequence'])
                        and all(prior[name]==request[name] for name in ('session','actor','repository','source_kind')),
                        'continuation prior request binding differs')
                if prior['ref']!=request['ref']:
                    return {'request_id':row['id'],'revision':row['revision'],'decision':None,'status':'binding_changed'}
                decision=None if row['decision'] is None else decode(row['decision'])
                if decision is not None:
                    validate_decision(decision)
                    require(decision['request_id']==row['id'] and decision['revision']==row['revision'],'continuation decision binding differs')
                    if decision['disposition'] in {'answer','status'}:
                        continue
                elif prior['text'].strip().lower() in {'help','how does this work?','status','what is the status?'}:
                    continue
                return {'request_id':row['id'],'revision':row['revision'],'decision':decision,'status':row['status']}
        return None

    def candidate_identity(self, scout):
        root=Path(self.config['candidate_root'])
        environment={'PATH':'/usr/bin:/bin','HOME':'/nonexistent','GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_SYSTEM':'/dev/null',
                     'GIT_CONFIG_GLOBAL':'/dev/null','GIT_CONFIG_COUNT':'0','GIT_TERMINAL_PROMPT':'0','GIT_OPTIONAL_LOCKS':'0','LC_ALL':'C'}
        command=['/usr/bin/git','--no-optional-locks','-c','core.fsmonitor=false','-c','core.hooksPath=/dev/null','-C',str(root),
                 'rev-parse','--verify','HEAD']
        head=scout._bounded.run(command,env=environment,cwd=str(root),timeout=5,limit=8192)
        require(head.returncode==0,'fresh decision Git HEAD unavailable')
        branch=scout._bounded.run(command[:-3]+['symbolic-ref','-q','HEAD'],env=environment,cwd=str(root),timeout=5,limit=8192)
        require(branch.returncode in {0,1},'fresh decision Git ref unavailable')
        return {'head':head.stdout.decode('ascii').strip(),'ref':branch.stdout.decode('ascii').strip()}

    def decision_binding(self, request, result, scout, context=None):
        candidate=self.candidate_identity(scout)
        require(candidate['head']==request['ref'],'fresh decision request ref stale')
        return {'request_sha256':digest(canonical(request).encode()),'decision_sha256':digest(canonical(result).encode()),
                'candidate':candidate,'context_sha256':None if context is None else digest(context)}

    def fresh_decision(self, request_id):
        """Read-only pre-action guard. Cached outcomes grant no execution authority.

        Future governed effect paths must call this immediately before their own
        action/claim checks; this check neither reserves nor starts an action.
        """
        require(hex_value(request_id,32),'fresh decision request identity invalid')
        self.execution_ready()
        with self.transaction() as db:
            row=db.execute('SELECT * FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            binding=db.execute('SELECT document FROM intake_decision_bindings WHERE request_id=?',(request_id,)).fetchone()
            require(row is not None and row['decision'] is not None and binding is not None
                    and row['status'] in {'decided','clarify'},'fresh decision binding missing or blocked')
            request=decode(row['document']);result=decode(row['decision']);saved=decode(binding['document'])
        validate_request(request,self.config['limits']);validate_decision(result)
        require(request['repository']==self.config['repository'] and result['request_id']==request_id
                and row['revision']==result['revision']==digest(canonical(request).encode()),'fresh decision request binding differs')
        require(result['next_action'] not in {'none','stop'} and result['blocked_reason'] is None,'fresh decision has no permitted action')
        scout,routing=self.assessment_modules()
        raw,eligible,evidence,paths,catalog=self.assessment_context(request_id,request,row['revision'],scout,routing)
        current=self.decision_binding(request,result,scout,raw if saved['context_sha256'] is not None else None)
        require(current==saved,'fresh decision source/context binding changed')
        if request['text'].strip().lower() in {'continue','keep continuing','resume'}:
            context=self.session_context(request_id,request)
            if context is not None:
                evidence.add(('request',context['request_id'],context['revision']))
                if result['next_action']=='resume':
                    prior=context['decision']
                    require(prior is not None and prior['disposition']=='existing_approved'
                            and all(prior[name]==result[name] for name in ('spec','plan','task')),
                            'fresh decision session task binding changed')
        require(all((item['kind'],item['ref'],item['sha256']) in evidence for item in result['evidence']),
                'fresh decision evidence stale or unbound')
        for intent in result['intents']:
            for path in intent['scope']:
                if path not in paths:
                    require(result['next_action'] in {'draft','question'},'fresh decision source not collected')
                    self.proposed_source_path(path,scout,routing)
        references=tuple(result[name] for name in ('spec','plan','task'))
        choices=eligible
        if result['disposition'] in {'defect','changed_requirement'} and result['next_action'] in {'draft','question','inspect'}:
            choices=[*eligible,*catalog]
        require(references==(None,None,None) or any(references==tuple(item[name] for name in ('spec','plan','task')) for item in choices),
                'fresh decision approved scope no longer eligible')
        if references!=(None,None,None):
            selected=next(item for item in choices if references==tuple(item[name] for name in ('spec','plan','task')))
            cited={(item['kind'],item['ref'],item['sha256']) for item in result['evidence']}
            require(all((item['kind'],item['ref'],item['sha256']) in cited for item in selected['evidence']),
                    'fresh decision approved evidence changed')
        if result['next_action']=='resume':
            require(references!=(None,None,None),'fresh decision approval missing')
            import fnmatch
            policy=decode(read_file(self.config['policy'],65536,True))
            matches=[value for value in policy.get('specs',{}).values() if isinstance(value,dict) and value.get('path')==result['spec']]
            require(len(matches)==1,'fresh decision approved scope ambiguous')
            require(all(any(fnmatch.fnmatchcase(path,pattern) for pattern in matches[0]['allowed_paths'])
                        for intent in result['intents'] for path in intent['scope']),'fresh decision exceeds approved scope')
        if result['next_action'] in {'draft','question'}:
            with self.transaction() as db:
                lineage=db.execute('SELECT 1 FROM intake_proposal_revisions WHERE request_id=?',(request_id,)).fetchone()
            if lineage is not None:
                proposal=self.proposal_revision(request_id)
                require(proposal['current'] and proposal['state']=='active','fresh decision proposal superseded or blocked')
        self.execution_ready()
        with self.transaction() as db:
            current=db.execute('SELECT document,revision,decision,status FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(tuple(current)==(row['document'],row['revision'],row['decision'],row['status']), 'fresh decision changed during validation')
        return result

    def proposal_document(self, request_id, decision):
        with self.transaction() as db:
            row=db.execute('SELECT document,revision FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(row is not None and row['revision']==decision['revision'],'proposal source revision differs')
            request=decode(row['document'])
        validate_request(request,self.config['limits'])
        require(request['source_kind']=='claude','proposal source requires separate encrypted publication adapter')
        proposal=self.proposal_revision(request_id)
        require(proposal['current'] and proposal['state']=='active','proposal head not current')
        lineage=self.proposal_context(request_id,request)
        def literal_data(value):
            text=canonical(value)
            longest=max((len(match[0]) for match in re.finditer(r'`+',text)),default=0)
            fence='`'*max(3,longest+1)
            return [fence+'json',text,fence]
        lines=['---','status: draft','proposal_id: '+proposal['proposal_id'],'request_id: '+request_id,
               'request_revision: '+decision['revision'],'---','','# Proposed scope for human review','',
               'Approval is pending. This draft is not execution authority or verification evidence.','',
               '## Request','',*literal_data({'text':request['text']}),'','## Proposed behavior','']
        for intent in decision['intents']:lines+=literal_data(intent)
        lines+=['','## Proposed acceptance criteria','']
        for number,intent in enumerate(decision['intents'],1):
            lines.append(str(number)+'. **AC-'+str(number)+'**: Review and confirm the following proposed behavior.')
            lines+=literal_data({'summary':intent['summary']})
        lines+=['','## Open questions','',
                '- [OQ-1] Confirm intended observable behavior, scope and acceptance criteria before approval.',
                '- [OQ-2] Review the proposed change against existing approved contracts and delivery controls.',
                '','## Source bindings','',*literal_data({'request_id':request_id,'revision':decision['revision'],
                'repository':request['repository'],'ref':request['ref'],'proposal':proposal,
                'decision_sha256':digest(canonical(decision).encode()),'evidence':decision['evidence']}),
                '','## Clarification history','',*literal_data(lineage),'']
        raw='\n'.join(lines).encode('utf-8')
        require(len(raw)<=self.config['limits']['context_bytes'],'proposal document bound exceeded')
        target='proposals/'+proposal['proposal_id']+'/'+decision['revision']+'.md'
        action={'schema_version':1,'request_id':request_id,'revision':decision['revision'],
                'decision_sha256':digest(canonical(decision).encode()),'kind':'proposal_publish',
                'target':target,'target_revision':digest(raw),'stage':'draft','paths':[target],
                'principal':None,'fence':None}
        validate_action(action)
        return action,raw

    def proposal_directory(self, action):
        """Walk only controller-derived private directories using pinned descriptors."""
        require(relative(action['target']) and action['target']==
                'proposals/'+self.proposal_revision(action['request_id'])['proposal_id']+'/'+action['revision']+'.md',
                'proposal assigned target differs')
        root=private(self.path.parent,True)
        descriptor=os.open(root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:
            for component in Path(action['target']).parts[:-1]:
                try:os.mkdir(component,0o700,dir_fd=descriptor)
                except FileExistsError:pass
                else:os.fsync(descriptor)
                child=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=descriptor)
                info=os.fstat(child)
                if not (stat.S_ISDIR(info.st_mode) and info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o700):
                    os.close(child);require(False,'proposal private directory owner/mode invalid')
                os.close(descriptor);descriptor=child
            target=root/action['target']
            require(target.parent.resolve()==target.parent,'proposal directory moved or linked')
            return descriptor,target
        except BaseException:
            os.close(descriptor);raise

    def complete_proposal(self, action_id, action):
        result={'action_id':action_id,'path':str(self.path.parent/action['target']),
                'sha256':action['target_revision'],'request_id':action['request_id'],'revision':action['revision'],'status':'draft'}
        self.execution_ready()
        with self.transaction() as db:
            row=db.execute('SELECT document,status FROM intake_actions WHERE id=?',(action_id,)).fetchone()
            require(row is not None and row['document']==canonical(action)
                    and row['status'] in {'started','unknown','completed'},'proposal action binding changed')
            db.execute("UPDATE intake_actions SET status='completed',result=? WHERE id=?",(canonical(result),action_id))
        return result

    def publish_proposal(self, request_id):
        """Publish an assigned local private draft; retries only reconcile exact effects."""
        decision=self.fresh_decision(request_id)
        require(decision['next_action']=='draft','proposal publication requires current draft disposition')
        action,raw=self.proposal_document(request_id,decision)
        action_id=digest(canonical(action).encode())
        with self.transaction() as db:
            row=db.execute('SELECT * FROM intake_actions WHERE id=?',(action_id,)).fetchone()
            first=row is None
            if first:
                db.execute("INSERT INTO intake_actions VALUES(?,?,?,'started',NULL)",(action_id,request_id,canonical(action)))
            else:
                require(row['request_id']==request_id and row['document']==canonical(action)
                        and row['status'] in {'started','unknown','completed'},'proposal action is conflicting or blocked')
        descriptor=None;file_descriptor=None
        try:
            descriptor,target=self.proposal_directory(action)
            require(self.fresh_decision(request_id)==decision,'proposal decision changed before publication')
            parent=private(target.parent,True).stat();opened=os.fstat(descriptor)
            require((parent.st_dev,parent.st_ino)==(opened.st_dev,opened.st_ino),'proposal assigned directory changed')
            name=target.name;created=False
            if first:
                try:
                    file_descriptor=os.open(name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=descriptor)
                    created=True
                except FileExistsError:pass
            if created:
                info=os.fstat(file_descriptor)
                require(info.st_nlink==1 and info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'proposal created file binding invalid')
                with os.fdopen(file_descriptor,'wb',closefd=False) as output:
                    output.write(raw);output.flush()
                os.fsync(file_descriptor)
            else:
                file_descriptor=os.open(name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=descriptor)
                info=os.fstat(file_descriptor)
                require(stat.S_ISREG(info.st_mode) and info.st_nlink==1 and info.st_uid==os.getuid()
                        and stat.S_IMODE(info.st_mode)==0o600 and info.st_size==len(raw),'proposal existing file binding invalid')
                with os.fdopen(file_descriptor,'rb',closefd=False) as source:observed=source.read(len(raw)+1)
                require(observed==raw,'proposal existing bytes conflict')
            os.fsync(descriptor)
            info=os.fstat(file_descriptor);current=os.stat(name,dir_fd=descriptor,follow_symlinks=False)
            require(stat.S_ISREG(current.st_mode) and current.st_nlink==1
                    and (current.st_dev,current.st_ino)==(info.st_dev,info.st_ino)
                    and target.resolve()==target,'proposal effect path changed')
            require(self.fresh_decision(request_id)==decision,'proposal decision changed after effect')
            read_descriptor=os.open(name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=descriptor)
            try:
                observed_info=os.fstat(read_descriptor)
                require(stat.S_ISREG(observed_info.st_mode) and observed_info.st_nlink==1
                        and observed_info.st_uid==os.getuid() and stat.S_IMODE(observed_info.st_mode)==0o600
                        and observed_info.st_size==len(raw)
                        and (observed_info.st_dev,observed_info.st_ino)==(info.st_dev,info.st_ino),'proposal final file binding invalid')
                with os.fdopen(read_descriptor,'rb',closefd=False) as source:observed=source.read(len(raw)+1)
                after=os.fstat(read_descriptor)
                require((after.st_size,after.st_mtime_ns,after.st_ctime_ns)==
                        (observed_info.st_size,observed_info.st_mtime_ns,observed_info.st_ctime_ns)
                        and observed==raw,'proposal final bytes changed')
                parent=private(target.parent,True).stat();opened=os.fstat(descriptor);path_info=private(target).stat()
                require((parent.st_dev,parent.st_ino)==(opened.st_dev,opened.st_ino)
                        and (path_info.st_dev,path_info.st_ino)==(after.st_dev,after.st_ino),'proposal canonical effect path changed')
            finally:os.close(read_descriptor)
            return self.complete_proposal(action_id,action)
        except BaseException:
            with self.transaction() as db:
                db.execute("UPDATE intake_actions SET status='unknown',result=NULL WHERE id=?",(action_id,))
            raise
        finally:
            if file_descriptor is not None:os.close(file_descriptor)
            if descriptor is not None:os.close(descriptor)

    def enqueue_scope(self, request_id, task):
        decision=self.fresh_decision(request_id)
        require(decision['disposition']=='existing_approved' and decision['next_action']=='resume'
                and decision['task']==task,'enqueue requires the exact current approved task')
        selected=[item for item in self.eligible() if all(item[name]==decision[name] for name in ('spec','plan','task'))]
        require(len(selected)==1,'enqueue approved task no longer eligible')
        return decision,selected[0]

    def start_scope(self, request_id, task, action_id):
        """Validate a queued action against actual approved ledger authority.

        This read-only check neither mints a claim nor permits an unsupported
        native worker. Supervisor-derived owner/fence propagation is separate.
        """
        require(hex_value(action_id,64),'current task start action required')
        decision,selected=self.enqueue_scope(request_id,task)
        policy=decode(read_file(self.config['policy'],65536,True))
        spec_id=Path(selected['spec']).name.split('-',1)[0];approved=policy['specs'][spec_id]
        revision=next(item['sha256'] for item in selected['evidence'] if item['kind']=='spec')
        with self.transaction() as db:
            row=db.execute('SELECT * FROM tasks WHERE id=?',(task,)).fetchone()
            effect=db.execute('SELECT * FROM intake_actions WHERE id=?',(action_id,)).fetchone()
            require(row is not None and row['state']=='queued' and row['owner'] is None and row['revision']==revision,'start task is not an unclaimed approved queue item')
            authority=decode(row['authority']) if row['authority'] is not None else None
            require(isinstance(authority,dict) and set(authority)=={'spec','revision','deps','ac_ids','allowed_paths'}
                    and authority['spec']==spec_id and authority['revision']==revision
                    and authority['deps']==decode(row['deps']) and set(authority['ac_ids'])==set(approved['ac_ids'])
                    and authority['allowed_paths']==approved['allowed_paths'],'start actual task authority differs')
            require(effect is not None and effect['request_id']==request_id and effect['status']=='intent','start action absent or unresolved')
            action=decode(effect['document']);validate_action(action)
            expected={'schema_version':1,'request_id':request_id,'revision':decision['revision'],
                      'decision_sha256':digest(canonical(decision).encode()),'kind':'task_start','target':task,
                      'target_revision':revision,'stage':'queued','paths':approved['allowed_paths'],'principal':None,'fence':None}
            require(action==expected and action_id==digest(canonical(action).encode()),'start action binding differs')
        return action

    def enqueue_intent(self, request_id, task):
        decision,selected=self.enqueue_scope(request_id,task)
        revision=next(item['sha256'] for item in selected['evidence'] if item['kind']=='spec')
        action={'schema_version':1,'request_id':request_id,'revision':decision['revision'],
                'decision_sha256':digest(canonical(decision).encode()),'kind':'task_enqueue',
                'target':task,'target_revision':revision,'stage':'queued','paths':[], 'principal':None,'fence':None}
        validate_action(action);identity=digest(canonical(action).encode())
        with self.transaction() as db:
            row=db.execute('SELECT * FROM intake_actions WHERE id=?',(identity,)).fetchone()
            if row is None:
                db.execute("INSERT INTO intake_actions VALUES(?,?,?,'started',NULL)",(identity,request_id,canonical(action)))
            else:
                require(row['request_id']==request_id and row['document']==canonical(action)
                        and row['status'] in {'started','unknown','completed'},'enqueue action binding changed')
                observed=db.execute('SELECT revision,state FROM tasks WHERE id=?',(task,)).fetchone()
                require(observed is not None and tuple(observed)==(revision,'queued'),'unresolved enqueue requires exact existing effect')
        return identity,action

    def complete_enqueue(self, identity, action):
        self.enqueue_scope(action['request_id'],action['target'])
        result={'action_id':identity,'task':action['target'],'revision':action['target_revision'],'state':'queued'}
        with self.transaction() as db:
            row=db.execute('SELECT document FROM intake_actions WHERE id=?',(identity,)).fetchone()
            task=db.execute('SELECT revision,state FROM tasks WHERE id=?',(action['target'],)).fetchone()
            require(row is not None and row['document']==canonical(action) and task is not None
                    and tuple(task)==(action['target_revision'],'queued'),'enqueue effect differs')
            db.execute("UPDATE intake_actions SET status='completed',result=? WHERE id=?",(canonical(result),identity))
        return result

    def enqueue_task(self, request_id):
        decision=self.fresh_decision(request_id)
        require(decision['next_action']=='resume','enqueue requires approved continuation')
        path=Path(__file__).with_name('factory-ledger.py').resolve()
        require(str(path) in self.config['trusted_files'],'enqueue ledger closure pin missing')
        self.ready()
        import importlib.util
        spec=importlib.util.spec_from_file_location('intake_ledger',path)
        ledger=importlib.util.module_from_spec(spec);spec.loader.exec_module(ledger)
        ledger.import_task(self.config['authority_root'],self.database,decision['task'],self.config['policy'],
                           intake_request=request_id,intake_profile=self.config['profile'])
        decision,selected=self.enqueue_scope(request_id,decision['task'])
        revision=next(item['sha256'] for item in selected['evidence'] if item['kind']=='spec')
        return {'task':decision['task'],'revision':revision,'state':'queued'}

    def lightweight(self, request_id):
        self.ready()
        with self.transaction() as db:
            row = db.execute('SELECT * FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(row is not None, 'unknown intake request')
            if row['decision'] is not None:
                result = decode(row['decision']); validate_decision(result)
                return result
            require(row['status']=='submitted', 'intake assessment unresolved')
            request = decode(row['document'])
        prompt = request['text'].strip().lower()
        choices = {'how does this work?':('answer','answer','Explain the approved factory workflow'),
                   'help':('answer','answer','Explain supported requests and approval gates'),
                   'status':('status','inspect','Inspect current factory state'),
                   'what is the status?':('status','inspect','Inspect current factory state'),
                   'stop':('risk_control','stop','Pause governed work immediately'),
                   'pause':('risk_control','stop','Pause governed work immediately'),
                   '/stop':('risk_control','stop','Pause governed work immediately'),
                   'skip the gates':('risk_control','question','Existing gates cannot be bypassed')}
        references = {'spec':None,'plan':None,'task':None}
        evidence = [{'kind':'request','ref':request_id,'sha256':row['revision']}]
        uncertainty = 'none'
        explicit=re.fullmatch(r'(?:continue|resume) (t-[1-9][0-9]*)',prompt)
        if prompt in {'continue','keep continuing','resume'} or explicit:
            eligible=self.eligible()
            context=None if explicit else self.session_context(request_id,request)
            selected=None
            if explicit:
                matches=[item for item in eligible if item['task']==explicit[1].upper()]
                if len(matches)==1:selected=matches[0]
            elif context is not None:
                previous=context['decision']
                evidence.append({'kind':'request','ref':context['request_id'],'sha256':context['revision']})
                if previous is not None and previous['disposition']=='existing_approved':
                    matches=[item for item in eligible if all(item[name]==previous[name] for name in ('spec','plan','task'))]
                    if len(matches)==1:selected=matches[0]
            if selected is not None:
                references={name:selected[name] for name in references}
                evidence.extend(selected['evidence'])
                disposition,action,rationale='existing_approved','resume','Resume the explicitly selected current eligible session task'
            else:
                disposition,action='clarify','question'
                rationale=('Confirm the outstanding proposal, clarification or blocked request before continuing'
                           if context is not None else 'Name the approved task to continue; no eligible session task is bound')
                uncertainty='ambiguous' if context is not None or len(eligible)>1 else 'missing_context'
        elif prompt in choices:
            disposition,action,rationale = choices[prompt]
        else:
            return None
        result = {'schema_version':1,'request_id':request_id,'revision':row['revision'],
                  'disposition':disposition,'intents':[{'kind':disposition,'summary':rationale,'scope':[]}],
                  'rationale':rationale,'evidence':evidence,'uncertainty':uncertainty,
                  **references,'next_action':action,'blocked_reason':None}
        validate_decision(result)
        binding=None
        try:
            scout,routing=self.assessment_modules()
            raw=None
            if action=='resume':
                raw,*_=self.assessment_context(request_id,request,row['revision'],scout,routing)
            binding=self.decision_binding(request,result,scout,raw)
        except (ValueError,OSError,KeyError,TypeError,UnicodeError):
            # Historical lightweight queries still work in advisory/non-Git installs;
            # absence of a current private binding fences all dependent effects.
            pass
        with self.transaction() as db:
            current = db.execute('SELECT decision,status FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(current['status']=='submitted' or current['decision']==canonical(result), 'intake decision race')
            db.execute("UPDATE intake_requests SET decision=?,status='decided' WHERE id=?",(canonical(result),request_id))
            db.execute('INSERT INTO intake_events(request_id,event) VALUES(?,?)',(request_id,'lightweight_decision'))
            self.settle_proposal(db,request_id,request,result)
            if binding is not None:
                db.execute('INSERT INTO intake_decision_bindings VALUES(?,?)',(request_id,canonical(binding)))
            if action=='stop':
                db.execute('UPDATE intake_identity SET paused=1 WHERE id=1')
                db.execute('UPDATE control SET paused=1 WHERE id=1')
        return result


    @staticmethod
    def assessment_block(request_id, revision, reason):
        return {'schema_version':1,'request_id':request_id,'revision':revision,
                'disposition':'blocked','intents':[{'kind':'blocked','summary':'Intake assessment cannot advance','scope':[]}],
                'rationale':'Assessment is blocked; reconcile protected prerequisites before dependent work',
                'evidence':[],'uncertainty':'none','spec':None,'plan':None,'task':None,
                'next_action':'none','blocked_reason':reason}

    def assessment_modules(self):
        import importlib.util
        directory=Path(__file__).resolve().parent
        names=('factory-intake-scout.py','factory-routing.py','factory-bounded-process.py','factory-supervisor.py')
        require(all(str(directory/name) in self.config['trusted_files'] for name in names),
                'assessment executable closure pins missing')
        # ready/load_contract verify all exact byte pins before imports.
        self.ready()
        modules=[]
        for label,name in [('scout','factory-intake-scout.py'),('routing','factory-routing.py')]:
            spec=importlib.util.spec_from_file_location('outcome_'+label,directory/name)
            module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);modules.append(module)
        return modules

    def contract_catalog(self, scout=None, routing=None):
        """Approved contract applicability is read-only, never runnable eligibility."""
        self.ready()
        if scout is None or routing is None:
            scout,routing=self.assessment_modules()
        policy=decode(read_file(self.config['policy'],65536,True))
        profile=routing.protected(Path(self.config['profile']),[Path(self.config[name]) for name in ('candidate_root','authority_root')])
        require(profile['enabled'] and profile['repository']==policy.get('repository')==self.config['repository'],'foreign contract catalog')
        require(isinstance(policy.get('runtime'),dict) and policy['runtime'].get('routing_profile_sha256')==digest(routing.canonical(profile).encode()),'catalog profile binding invalid')
        specs=policy.get('specs',{})
        require(isinstance(specs,dict) and len(specs)<=100,'catalog approved specification list invalid')
        roots=[scout.source_root(value) for value in profile['source_roots']]
        authority=Path(self.config['authority_root']);result=[];seen=set()
        for identity,approved in specs.items():
            require(isinstance(identity,str) and re.fullmatch(r'\d{3}',identity) and isinstance(approved,dict),'catalog specification entry invalid')
            name=approved.get('path');path=scout.relative(name);scout.permitted(path)
            require(name.startswith('specs/active/') and re.fullmatch(identity+r'-[a-z0-9-]+\.md',path.name)
                    and name not in seen,'catalog specification path binding invalid')
            seen.add(name)
            source=authority/name
            require(source.resolve()==source and source.is_file(),'catalog source not canonical')
            raw=read_file(source,self.config['limits']['context_bytes']);text=raw.decode('utf-8')
            acs=re.findall(r'\*\*(AC-\d+)(?:\s+[—-]\s+[^*]+)?\*\*',text)
            expected=approved.get('ac_ids')
            require(digest(raw)==approved.get('sha256') and header_values(raw,b'status')==[b'approved']
                    and acs and len(set(acs))==len(acs) and isinstance(expected,list)
                    and all(isinstance(ac,str) for ac in expected) and len(set(expected))==len(expected)
                    and set(acs)==set(expected),'catalog specification approval bytes or ACs differ')
            scope=approved.get('allowed_paths')
            require(isinstance(scope,list) and 0<len(scope)<=100 and all(isinstance(value,str) for value in scope)
                    and len(set(scope))==len(scope),'catalog approved paths invalid')
            for value in scope:
                # Preserve glob syntax as scope data; do not stat/read glob strings.
                scoped=scout.relative(value);scout.permitted(scoped)
                require(any(scoped==root or root in scoped.parents for root in roots),'catalog scope outside protected roots')
            evidence=[{'kind':'spec','ref':name,'sha256':digest(raw)}]
            plan=authority/'plans/active'/path.name;plan_name=None
            require(not plan.is_symlink(),'catalog plan symlink rejected')
            if plan.exists():
                require(plan.resolve()==plan and plan.is_file(),'catalog plan not canonical')
                plan_raw=read_file(plan,self.config['limits']['context_bytes'])
                if header_values(plan_raw,b'status')==[b'approved']:
                    require(header_values(plan_raw,b'spec')==[name.encode()],'catalog approved plan references foreign spec')
                    plan_name=str(plan.relative_to(authority))
                    evidence.append({'kind':'plan','ref':plan_name,'sha256':digest(plan_raw)})
            result.append({'spec':name,'plan':plan_name,'task':None,'evidence':evidence,
                           'open_questions':open_questions(text)})
        return result

    def assessment_context(self, request_id, request, revision, scout, routing):
        import time
        policy=decode(read_file(self.config['policy'],65536,True))
        profile=routing.protected(Path(self.config['profile']),[Path(self.config[name]) for name in ('candidate_root','authority_root')])
        require(profile['enabled'] and profile['repository']==policy.get('repository')==self.config['repository'],
                'assessment repository binding invalid')
        require(isinstance(policy.get('runtime'),dict) and policy['runtime'].get('routing_profile_sha256')==digest(routing.canonical(profile).encode()),
                'assessment protected routing profile differs')
        intake=policy.get('intake')
        require(isinstance(intake,dict) and set(intake)=={'enabled','dataflow','context_paths'} and intake['enabled'] is True
                and intake['dataflow']=='private-scout-v1' and isinstance(intake['context_paths'],list)
                and len(intake['context_paths'])<=1000 and all(relative(path) for path in intake['context_paths'])
                and len(set(intake['context_paths']))==len(intake['context_paths']), 'approved assessment dataflow missing')
        require(request['repository']==self.config['repository'] and digest(canonical(request).encode())==revision,
                'assessment stored request binding invalid')
        root=Path(self.config['candidate_root']);deadline=time.monotonic()+20
        environment={'PATH':'/usr/bin:/bin','HOME':'/nonexistent','GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_SYSTEM':'/dev/null',
                     'GIT_CONFIG_GLOBAL':'/dev/null','GIT_CONFIG_COUNT':'0','GIT_TERMINAL_PROMPT':'0','GIT_OPTIONAL_LOCKS':'0','LC_ALL':'C'}
        command=['/usr/bin/git','--no-optional-locks','-c','core.fsmonitor=false','-c','core.hooksPath=/dev/null','-C',str(root),'rev-parse','--verify','HEAD']
        observed=scout._bounded.run(command,env=environment,cwd=str(root),timeout=5,limit=8192)
        require(observed.returncode==0 and observed.stdout.decode('ascii').strip()==request['ref'], 'assessment request ref stale')
        # Delivery/retry secrets and private actor/session metadata never enter context.
        public_request={'text':request['text'],'repository':request['repository'],'ref':request['ref'],
                        'request_id':request_id,'revision':revision}
        lineage=self.proposal_context(request_id,request)
        if lineage is not None:public_request['proposal']=lineage
        limits=self.config['limits']
        def collect(tree, paths, roots, evidence):
            remaining=deadline-time.monotonic();require(remaining>0,'assessment collection deadline')
            return decode(scout.collect_context(public_request,tree,paths,roots,evidence,context_bytes=limits['context_bytes'],
                                               request_chars=limits['request_chars'],collection_seconds=min(20,remaining)))
        context=collect(root,intake['context_paths'],profile['source_roots'],[])
        eligible=self.eligible()
        catalog=self.contract_catalog(scout,routing)
        documents={}
        for item in [*eligible,*catalog]:
            for evidence in item['evidence']:
                kind=evidence['kind'] if evidence['kind'] in {'spec','plan'} else 'task'
                documents[evidence['ref']]={'kind':kind,'path':evidence['ref'],'sha256':evidence['sha256']}
        ledger=Path(self.config['authority_root'])/'tasks/TASKS.md'
        if catalog and ledger.is_file():
            require(ledger.resolve()==ledger,'catalog task ledger not canonical')
            ledger_raw=read_file(ledger,limits['context_bytes'])
            documents['tasks/TASKS.md']={'kind':'task','path':'tasks/TASKS.md','sha256':digest(ledger_raw)}
        if documents:
            authority=collect(Path(self.config['authority_root']),[],['specs','plans','tasks'],list(documents.values()))
            context['approved_evidence']=authority['approved_evidence']
        raw=canonical(context).encode('utf-8')
        require(len(raw)<=limits['context_bytes'] and time.monotonic()<deadline,'combined assessment context bound exceeded')
        evidence={(item['kind'],item['ref'],item['sha256']) for entry in [*eligible,*catalog] for item in entry['evidence']}
        if 'tasks/TASKS.md' in documents:
            evidence.add(('repository','tasks/TASKS.md',documents['tasks/TASKS.md']['sha256']))
        evidence.add(('request',request_id,revision))
        if lineage is not None:evidence.update(('request',item['request_id'],item['revision']) for item in lineage['history'])
        evidence.update(('repository',item['path'],item['sha256']) for item in context['sources'])
        for entry in eligible:
            ledger=next((item for item in entry['evidence'] if item['ref']=='tasks/TASKS.md'),None)
            if ledger:evidence.add(('task',entry['task'],ledger['sha256']))
        return raw,eligible,evidence,set(intake['context_paths']),catalog

    def proposed_source_path(self, name, scout, routing):
        """Validate a proposed filename only; never read it or mint evidence."""
        path=scout.relative(name);scout.permitted(path)
        profile=routing.protected(Path(self.config['profile']),[Path(self.config[key]) for key in ('candidate_root','authority_root')])
        require(profile['enabled'] and profile['repository']==self.config['repository'],'proposed source profile differs')
        roots=[scout.source_root(value) for value in profile['source_roots']]
        require(any(path==base or base in path.parents for base in roots),'proposed source outside protected roots')
        root=Path(self.config['candidate_root'])
        descriptor=os.open(root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        try:
            for index,component in enumerate(path.parts):
                try:info=os.stat(component,dir_fd=descriptor,follow_symlinks=False)
                except FileNotFoundError:
                    # Remaining components are only names in a proposal. Later
                    # publication/mutation must independently revalidate effects.
                    return
                require(not stat.S_ISLNK(info.st_mode),'proposed source symlink rejected')
                if index==len(path.parts)-1:
                    require(stat.S_ISREG(info.st_mode) and info.st_nlink==1,'proposed source is not a regular unlinked file')
                else:
                    require(stat.S_ISDIR(info.st_mode),'proposed source ancestor not directory')
                    child=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=descriptor)
                    os.close(descriptor);descriptor=child
        finally:os.close(descriptor)

    def assess(self, request_id):
        """Reserve one attempt before execution; unknown attempts never replay."""
        require(hex_value(request_id,32),'assessment request identity invalid')
        self.ready()
        with self.transaction() as db:
            initial=db.execute('SELECT * FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(initial is not None,'unknown assessment request')
            if initial['decision'] is not None:
                result=decode(initial['decision']);validate_decision(result);return result
            if db.execute('SELECT 1 FROM intake_assessments WHERE request_id=?',(request_id,)).fetchone():
                return self.assessment_block(request_id,initial['revision'],'assessment-unresolved')
            prompt=decode(initial['document'])['text'].strip().lower()
        if re.fullmatch(r'(?:continue|resume) t-[1-9][0-9]*',prompt) or prompt in {'how does this work?','help','status','what is the status?','stop','pause','/stop','skip the gates','continue','keep continuing','resume'}:
            return self.lightweight(request_id)
        with self.transaction() as db:
            row=db.execute('SELECT * FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(row is not None,'unknown assessment request')
            revision=row['revision'];request=decode(row['document'])
            previous=db.execute('SELECT * FROM intake_assessments WHERE request_id=?',(request_id,)).fetchone()
            if previous is not None:
                require(previous['revision']==revision,'assessment revision binding differs')
                if row['decision'] is not None:
                    result=decode(row['decision']);validate_decision(result);return result
                return self.assessment_block(request_id,revision,'assessment-unresolved')
            require(row['status']=='submitted' and row['assessment_count']==0,'assessment request not eligible')
            db.execute("INSERT INTO intake_assessments(request_id,revision,status,result,reason) VALUES(?,?,'reserved',NULL,NULL)",(request_id,revision))
            db.execute("UPDATE intake_requests SET status='assessing',assessment_count=1 WHERE id=?",(request_id,))
            db.execute('INSERT INTO intake_events(request_id,event) VALUES(?,?)',(request_id,'assessment_reserved'))
        raw_result=None;binding=None
        try:
            scout,routing=self.assessment_modules()
            raw,eligible,evidence,paths,catalog=self.assessment_context(request_id,request,revision,scout,routing)
            # Commit running status, then release transaction before native execution.
            with self.transaction() as db:
                current=db.execute('SELECT status,revision FROM intake_assessments WHERE request_id=?',(request_id,)).fetchone()
                require(tuple(current)==('reserved',revision),'assessment reservation changed')
                db.execute("UPDATE intake_assessments SET status='running' WHERE request_id=?",(request_id,))
            self.ready()
            raw_result=scout.run_assessment(self.config['profile'],[Path(self.config[name]) for name in ('candidate_root','authority_root')],raw,
                                            assessment_seconds=self.config['limits']['assessment_seconds'],output_bytes=self.config['limits']['output_bytes'],
                                            context_bytes=self.config['limits']['context_bytes'],request_chars=self.config['limits']['request_chars'])
            self.ready()
            current_raw,current_eligible,current_evidence,current_paths,current_catalog=self.assessment_context(request_id,request,revision,scout,routing)
            require(current_raw==raw and current_eligible==eligible and current_evidence==evidence and current_paths==paths and current_catalog==catalog,
                    'assessment context changed during process')
            result={**raw_result['assessment'],'request_id':request_id,'revision':revision}
            validate_decision(result)
            require(all((item['kind'],item['ref'],item['sha256']) in evidence for item in result['evidence']),
                    'assessment invented evidence')
            for item in result['intents']:
                for path in item['scope']:
                    if path in paths:
                        continue
                    require(result['next_action'] in {'draft','question'},'uncollected source cannot authorize execution')
                    self.proposed_source_path(path,scout,routing)
            kinds={item['kind'] for item in result['intents']}
            require(result['disposition'] in kinds,'assessment disposition/intent mismatch')
            require(not kinds&{'new_feature','changed_requirement'} or result['next_action'] in {'draft','question'},'assessment mixed change scope cannot execute')
            references=tuple(result[name] for name in ('spec','plan','task'))
            reference_choices=eligible
            if result['disposition'] in {'defect','changed_requirement'} and result['next_action'] in {'draft','question','inspect'}:
                reference_choices=[*eligible,*catalog]
            require(references==(None,None,None) or any(references==tuple(item[name] for name in ('spec','plan','task')) for item in reference_choices),
                    'assessment invented approved scope')
            require(result['disposition']!='existing_approved' or references!=(None,None,None),'assessment approval match missing')
            if references!=(None,None,None):
                selected=next(item for item in reference_choices if references==tuple(item[name] for name in ('spec','plan','task')))
                require(not selected.get('open_questions') or result['next_action'] in {'draft','question'},'catalog open questions require proposal or clarification')
                cited={(item['kind'],item['ref'],item['sha256']) for item in result['evidence']}
                require(all((item['kind'],item['ref'],item['sha256']) in cited for item in selected['evidence']),'assessment approved references not evidenced')
            if result['next_action']=='resume':
                policy=decode(read_file(self.config['policy'],65536,True))
                matches=[value for value in policy.get('specs',{}).values() if isinstance(value,dict) and value.get('path')==references[0]]
                require(len(matches)==1,'assessment approved scope ambiguous');approved=matches[0]
                import fnmatch
                require(all(any(fnmatch.fnmatchcase(path,pattern) for pattern in approved['allowed_paths'])
                            for item in result['intents'] for path in item['scope']), 'assessment exceeds approved task scope')
            binding=self.decision_binding(request,result,scout,raw)
            final_status='blocked' if result['disposition'] in {'blocked','unsupported'} else 'clarify' if result['disposition']=='clarify' else 'decided'
            assessment_status='completed'
        except (ValueError,OSError,KeyError,TypeError,UnicodeError):
            binding=None
            result=self.assessment_block(request_id,revision,'assessment-failed')
            final_status='blocked';assessment_status='blocked'
        validate_decision(result)
        # Storage/ack failure leaves the reservation unknown; never retry process.
        with self.transaction() as db:
            row=db.execute('SELECT revision,status,decision FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(row is not None and row['revision']==revision and row['status']=='assessing' and row['decision'] is None,
                    'assessment final binding changed')
            db.execute('UPDATE intake_assessments SET status=?,result=?,reason=? WHERE request_id=?',
                       (assessment_status,None if raw_result is None else canonical(raw_result),result['blocked_reason'],request_id))
            db.execute('UPDATE intake_requests SET status=?,decision=? WHERE id=?',(final_status,canonical(result),request_id))
            db.execute('INSERT INTO intake_events(request_id,event) VALUES(?,?)',(request_id,'assessment_'+final_status))
            self.settle_proposal(db,request_id,request,result)
            if binding is not None:
                db.execute('INSERT INTO intake_decision_bindings VALUES(?,?)',(request_id,canonical(binding)))
        return result


DISPOSITIONS = {'answer','status','existing_approved','new_feature','changed_requirement',
                'defect','clarify','risk_control','unsupported','blocked'}
NEXT = {'answer','inspect','question','draft','resume','stop','none'}
REQUEST_FIELDS = {'schema_version','source_kind','origin','session','submission_key',
                  'delivery_token','source_revision','parent_request','actor','repository','ref','text'}
DECISION_FIELDS = {'schema_version','request_id','revision','disposition','intents','rationale',
                   'evidence','uncertainty','spec','plan','task','next_action','blocked_reason'}
ACTION_FIELDS = {'schema_version','request_id','revision','decision_sha256','kind','target',
                 'target_revision','stage','paths','principal','fence'}


def string(value, maximum=200):
    return isinstance(value,str) and 0<len(value)<=maximum and '\x00' not in value


def hex_value(value, size):
    return isinstance(value,str) and re.fullmatch('[a-f0-9]{'+str(size)+'}',value) is not None


def relative(value):
    return (string(value,4096) and not Path(value).is_absolute()
            and all(part not in {'','..','.'} for part in value.split('/')) and '\\' not in value)


def schema(value, fields):
    require(isinstance(value,dict) and set(value)==fields
            and type(value['schema_version']) is int and value['schema_version']==1,
            'intake schema invalid')


def validate_request(value, limits=DEFAULT_LIMITS):
    schema(value,REQUEST_FIELDS)
    require(value['source_kind'] in {'claude','slack'} and value['origin']=='human', 'unsupported intake origin')
    require(all(string(value[name]) for name in ('session','source_revision','actor','repository','ref')),
            'request binding fields invalid')
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',value['repository']), 'request repository invalid')
    require(string(value['text'],limits['request_chars']), 'request character limit or empty request')
    for name in ('submission_key','delivery_token'):
        require(value[name] is None or string(value[name]), 'source submission/retry invalid')
    require(value['parent_request'] is None or hex_value(value['parent_request'],32), 'request parent invalid')
    require(value['source_kind']!='slack' or value['submission_key'] is not None, 'Slack source identity required')


def validate_decision(value):
    schema(value,DECISION_FIELDS)
    require(hex_value(value['request_id'],32) and hex_value(value['revision'],64), 'decision binding invalid')
    require(value['disposition'] in DISPOSITIONS and value['next_action'] in NEXT
            and value['uncertainty'] in {'none','missing_context','ambiguous','conflict'}, 'decision enums invalid')
    require(string(value['rationale'],4000) and isinstance(value['intents'],list)
            and 1<=len(value['intents'])<=16, 'decision rationale/intents invalid')
    for intent in value['intents']:
        require(isinstance(intent,dict) and set(intent)=={'kind','summary','scope'}
                and intent['kind'] in DISPOSITIONS and string(intent['summary'],2000)
                and isinstance(intent['scope'],list) and len(intent['scope'])<=100
                and all(relative(path) for path in intent['scope']), 'decision intent invalid')
    require(isinstance(value['evidence'],list) and len(value['evidence'])<=100, 'decision evidence invalid')
    for item in value['evidence']:
        require(isinstance(item,dict) and set(item)=={'kind','ref','sha256'}
                and item['kind'] in {'request','spec','plan','task','repository'}
                and hex_value(item['sha256'],64)
                and (hex_value(item['ref'],32) if item['kind']=='request' else
                     re.fullmatch(r'T-[1-9][0-9]*',item['ref']) if item['kind']=='task' and isinstance(item['ref'],str) else relative(item['ref'])),
                'decision evidence reference invalid')
    for name in ('spec','plan'):
        require(value[name] is None or (relative(value[name]) and value[name].startswith(name+'s/active/')
                and re.fullmatch(r'\d{3}-[a-z0-9-]+\.md',Path(value[name]).name)), 'decision scope reference invalid')
    require(value['task'] is None or (isinstance(value['task'],str) and re.fullmatch(r'T-[1-9][0-9]*',value['task'])), 'decision task invalid')
    require(value['blocked_reason'] is None or (string(value['blocked_reason'],100)
            and re.fullmatch(r'[a-z][a-z0-9_-]*',value['blocked_reason'])), 'decision reason invalid')
    disposition=value['disposition'];action=value['next_action']
    allowed={'answer':{'answer'},'status':{'inspect'},'existing_approved':{'resume','inspect'},
             'new_feature':{'draft','question'},'changed_requirement':{'draft','question'},
             'defect':{'draft','question','inspect'},'clarify':{'question'},
             'risk_control':{'question','stop'},'unsupported':{'none'},'blocked':{'none'}}
    require(action in allowed[disposition], 'decision/action contradiction')
    if action=='resume':
        require(all(value[name] is not None for name in ('spec','plan','task')) and value['uncertainty']=='none'
                and all(item['kind'] in {'existing_approved','answer','status'} for item in value['intents']),
                'mixed or unapproved resume prohibited')
    require(disposition not in {'blocked','unsupported'} or value['blocked_reason'] is not None,
            'blocking disposition requires reason')


def validate_action(value):
    schema(value,ACTION_FIELDS)
    require(hex_value(value['request_id'],32) and all(hex_value(value[name],64)
            for name in ('revision','decision_sha256','target_revision')), 'action binding invalid')
    require(value['kind'] in {'proposal_publish','task_enqueue','task_start','implementation_mutation',
                             'answer','inspect','question','stop'}, 'action kind invalid')
    require(string(value['target'],4096) and string(value['stage']) and isinstance(value['paths'],list)
            and len(value['paths'])<=100 and all(relative(path) for path in value['paths']), 'action target/scope invalid')
    require(value['principal'] is None or string(value['principal']), 'action principal invalid')
    require(value['fence'] is None or (type(value['fence']) is int and value['fence']>0), 'action fence invalid')
    if value['kind']=='implementation_mutation':
        require(value['principal'] is not None and value['fence'] is not None and bool(value['paths']),
                'mutation needs current task principal and fence')


def open_questions(text):
    section = re.search(r'^## Open questions[^\n]*\n(.*?)(?=^## |\Z)',text,re.M|re.S)
    return bool(section and re.search(r'^\s*[-*]\s+(?:\[ \]\s+)?(?:\*\*)?\[OQ(?:-\d+)?\]',section[1],re.M))
