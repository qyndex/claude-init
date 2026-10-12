#!/usr/bin/env python3
"""Private request bindings. Routing assessments never grant task authority."""
import hashlib
import json
import os
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
    descriptor = os.open(path, os.O_RDONLY|getattr(os, 'O_NOFOLLOW', 0))
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
        if not self.database.exists():
            descriptor = os.open(self.database, os.O_RDWR|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0), 0o600)
            os.close(descriptor)
        private(self.database)
        with closing(sqlite3.connect(self.database)) as db:
            db.execute('PRAGMA trusted_schema=OFF')
            require(not db.execute("SELECT name FROM sqlite_master WHERE type IN ('trigger','view')").fetchall(),
                    'executable intake schema rejected')
            tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
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
                CREATE TABLE IF NOT EXISTS intake_events (
                    sequence INTEGER PRIMARY KEY,request_id TEXT,event TEXT NOT NULL);
            '''
            for statement in schema.split(';'):
                if statement.strip():
                    db.execute(statement)
            db.execute('INSERT OR IGNORE INTO intake_identity VALUES(1,1,?,?,?,0)',
                       (self.config['repository'],self.binding,str(self.path)))

    def transaction(self):
        return self.store.transaction()

    def ready(self):
        require(load_contract(self.path)==self.config, 'intake protected contract changed')
        private(self.database)
        with self.transaction() as db:
            require(not db.execute("SELECT name FROM sqlite_master WHERE type IN ('trigger','view')").fetchall(),
                    'executable intake schema rejected')
            row = db.execute('SELECT version,repository,contract_sha256,contract_path,paused FROM intake_identity WHERE id=1').fetchall()
            require([tuple(value) for value in row]==[(1,self.config['repository'],self.binding,str(self.path),0)],
                    'intake unavailable or paused')

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

    def submit_console(self, session, text, ref, *, parent=None, delivery_token=None):
        import uuid
        self.ready()
        require(hex_value(session,32), 'unknown console session')
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
                return self.receipt(previous['id'],previous['revision'],delivery_token)
            if parent is not None:
                previous = db.execute('SELECT document FROM intake_requests WHERE id=?',(parent,)).fetchone()
                require(previous is not None, 'unknown intake parent')
                document = decode(previous['document'])
                require(all(document[name]==request[name] for name in ('session','actor','repository','ref','source_kind')),
                        'foreign intake parent')
            sequence = row['sequence']+1
            identity = uuid.uuid4().hex
            token = uuid.uuid4().hex
            key = 'claude:'+session+':'+str(sequence)
            request.update(submission_key=key,source_revision=str(sequence),delivery_token=token)
            revision = digest(canonical(request).encode())
            db.execute('UPDATE intake_sessions SET sequence=? WHERE id=?',(sequence,session))
            db.execute('INSERT INTO intake_requests(id,source_key,document,revision,status) VALUES(?,?,?,?,?)',
                       (identity,key,canonical(request),revision,'submitted'))
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
            if (digest(raw)!=approved.get('sha256') or not re.search(rb'^status:\s*approved\s*$',raw,re.M)
                    or not acs or len(set(acs))!=len(acs) or set(acs)!=set(approved.get('ac_ids',[]))
                    or not approved.get('allowed_paths') or open_questions(raw.decode())):
                continue
            plan = root/'plans/active'/source.name
            if plan.resolve()!=plan or not plan.is_file():
                continue
            plan_raw = read_file(plan,self.config['limits']['context_bytes'])
            if not re.search(rb'^status:\s*approved\s*$',plan_raw,re.M) or not re.search(
                    rb'^spec:\s*'+re.escape(approved['path'].encode())+rb'\s*$',plan_raw,re.M):
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
        return result

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
        if prompt in {'continue','keep continuing','resume'}:
            eligible = self.eligible()
            if len(eligible)==1:
                chosen = eligible[0]
                references = {name:chosen[name] for name in references}
                evidence.extend(chosen['evidence'])
                disposition,action,rationale = 'existing_approved','resume','Single current approved eligible task'
            else:
                disposition,action,rationale = 'clarify','question','Identify the intended eligible approved task'
                uncertainty = 'ambiguous' if eligible else 'missing_context'
        elif prompt in choices:
            disposition,action,rationale = choices[prompt]
        else:
            return None
        result = {'schema_version':1,'request_id':request_id,'revision':row['revision'],
                  'disposition':disposition,'intents':[{'kind':disposition,'summary':rationale,'scope':[]}],
                  'rationale':rationale,'evidence':evidence,'uncertainty':uncertainty,
                  **references,'next_action':action,'blocked_reason':None}
        validate_decision(result)
        with self.transaction() as db:
            current = db.execute('SELECT decision,status FROM intake_requests WHERE id=?',(request_id,)).fetchone()
            require(current['status']=='submitted' or current['decision']==canonical(result), 'intake decision race')
            db.execute("UPDATE intake_requests SET decision=?,status='decided' WHERE id=?",(canonical(result),request_id))
            db.execute('INSERT INTO intake_events(request_id,event) VALUES(?,?)',(request_id,'lightweight_decision'))
            if action=='stop':
                db.execute('UPDATE intake_identity SET paused=1 WHERE id=1')
                db.execute('UPDATE control SET paused=1 WHERE id=1')
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
