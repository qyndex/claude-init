#!/usr/bin/env python3
"""Authenticated private SQLite checkpoints; ciphertext only crosses Git boundary."""
import base64
from contextlib import closing, contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import struct
import tempfile
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAX_DATABASE = 4_000_000
MAX_ENVELOPE = 6_000_000
FIELDS = {'schema_version','format','repository','stream','key_id','nonce','ciphertext'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()


def pairs(items):
    result={}
    for key,value in items:
        require(key not in result,'duplicate encrypted state field')
        result[key]=value
    return result


def context(repository, destination, branch, key_id):
    require(isinstance(repository,str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository),'invalid feedback repository')
    require(all(isinstance(value,str) and 0<len(value)<=200 for value in (destination,branch,key_id)),'invalid feedback context')
    require(re.fullmatch(r'[A-Za-z0-9_-]{1,64}',key_id),'invalid feedback key ID')
    stream=hashlib.sha256(canonical([repository,destination,branch,'private-feedback-v1'])).hexdigest()
    return {'schema_version':1,'format':'factory-private-feedback-v1','repository':repository,'stream':stream,'key_id':key_id}


def key(encoded):
    require(isinstance(encoded,str) and len(encoded)==44,'feedback key must be base64 encoded 32 bytes')
    result=base64.b64decode(encoded,validate=True)
    require(len(result)==32 and base64.b64encode(result).decode()==encoded,'invalid feedback key')
    return result


def seal(raw, secret, binding):
    require(isinstance(secret,bytes) and len(secret)==32,'invalid encryption key')
    require(isinstance(raw,bytes) and 0<len(raw)<=MAX_DATABASE,'feedback database size invalid')
    require(raw.startswith(b'SQLite format 3\0'),'feedback checkpoint must be SQLite')
    size=max(4096,1<<(len(raw)+8-1).bit_length())
    padded=struct.pack('>Q',len(raw))+raw+os.urandom(size-len(raw)-8)
    nonce=os.urandom(12)
    document={**binding,'nonce':base64.b64encode(nonce).decode(),'ciphertext':base64.b64encode(AESGCM(secret).encrypt(nonce,padded,canonical(binding))).decode()}
    encoded=canonical(document)
    require(len(encoded)<=MAX_ENVELOPE,'encrypted checkpoint exceeds bound')
    return encoded


def unseal(encoded, secret, binding):
    require(isinstance(encoded,bytes) and 0<len(encoded)<=MAX_ENVELOPE,'encrypted checkpoint size invalid')
    document=json.loads(encoded,object_pairs_hook=pairs)
    require(isinstance(document,dict) and set(document)==FIELDS and type(document['schema_version']) is int,'encrypted checkpoint schema invalid')
    require({name:document[name] for name in binding}==binding,'encrypted checkpoint context differs')
    require(isinstance(secret,bytes) and len(secret)==32,'invalid encryption key')
    require(isinstance(document['nonce'],str) and isinstance(document['ciphertext'],str),'invalid ciphertext encoding')
    nonce=base64.b64decode(document['nonce'],validate=True)
    ciphertext=base64.b64decode(document['ciphertext'],validate=True)
    require(len(nonce)==12 and 4112<=len(ciphertext)<=4_194_320,'ciphertext bounds invalid')
    padded=AESGCM(secret).decrypt(nonce,ciphertext,canonical(binding))
    require(len(padded)>=4096 and len(padded)&(len(padded)-1)==0,'invalid feedback padding')
    length=struct.unpack('>Q',padded[:8])[0]
    require(0<length<=MAX_DATABASE and length<=len(padded)-8,'invalid database length')
    raw=padded[8:8+length]
    require(raw.startswith(b'SQLite format 3\0'),'invalid feedback database')
    return raw



HOSTED_SCHEMA = {'intake_hosted_identity': 'CREATE TABLE intake_hosted_identity(id INTEGER PRIMARY KEY CHECK(id=1),version '
                           'INTEGER NOT NULL,mode TEXT NOT NULL,repository TEXT NOT NULL,contract_sha256 '
                           'TEXT NOT NULL)',
 'intake_requests': 'CREATE TABLE intake_requests(id TEXT PRIMARY KEY,source_key TEXT UNIQUE NOT '
                    'NULL,document TEXT NOT NULL,revision TEXT NOT NULL,status TEXT NOT NULL,decision '
                    'TEXT,assessment_count INTEGER NOT NULL DEFAULT 0)',
 'intake_events': 'CREATE TABLE intake_events(sequence INTEGER PRIMARY KEY,request_id TEXT,event TEXT NOT '
                  'NULL)',
 'intake_slack_heads': 'CREATE TABLE intake_slack_heads(source_key TEXT PRIMARY KEY,request_id TEXT UNIQUE '
                       'NOT NULL,source_revision TEXT NOT NULL,actor TEXT NOT NULL)',
 'intake_slack_revisions': 'CREATE TABLE intake_slack_revisions(request_id TEXT PRIMARY KEY,source_key TEXT '
                           'NOT NULL,source_revision TEXT NOT NULL,parent_request TEXT,kind TEXT NOT NULL)',
 'intake_assessments': 'CREATE TABLE intake_assessments(request_id TEXT PRIMARY KEY,revision TEXT NOT '
                       'NULL,status TEXT NOT NULL,result TEXT,reason TEXT)',
 'intake_decision_bindings': 'CREATE TABLE intake_decision_bindings(request_id TEXT PRIMARY KEY,document '
                             'TEXT NOT NULL)',
 'intake_actions': 'CREATE TABLE intake_actions(id TEXT PRIMARY KEY,request_id TEXT NOT NULL,document TEXT '
                   'NOT NULL,status TEXT NOT NULL,result TEXT)',
 'feedback_private_proposals': 'CREATE TABLE feedback_private_proposals(action_id TEXT PRIMARY '
                               'KEY,request_id TEXT UNIQUE NOT NULL,document TEXT NOT NULL)',
 'feedback_checkpoint_identity': 'CREATE TABLE feedback_checkpoint_identity(id INTEGER PRIMARY KEY '
                                 'CHECK(id=1),repository TEXT NOT NULL)',
 'factory_feedback': 'CREATE TABLE factory_feedback(id TEXT PRIMARY KEY, document TEXT NOT NULL, status TEXT '
                     'NOT NULL, version INTEGER NOT NULL DEFAULT 0)',
 'feedback_ingress_identity': 'CREATE TABLE feedback_ingress_identity (id INTEGER PRIMARY KEY, repository '
                              'TEXT NOT NULL, team TEXT NOT NULL, destination TEXT NOT NULL)'}


def intake_document(raw):
    value=json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda _:require(False,'nonfinite intake checkpoint'))
    require(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)==raw,'noncanonical intake checkpoint document')
    return value


def intake_hash(raw):
    return hashlib.sha256(raw.encode()).hexdigest()



def validate_shapes(db, names):
    def indices(connection,table):
        result=set()
        for name,unique,origin,partial in connection.execute('SELECT name,"unique",origin,partial FROM pragma_index_list(?)',(table,)):
            require(connection.execute('SELECT sql FROM sqlite_master WHERE type="index" AND name=?',(name,)).fetchone()==(None,),
                    'unsupported explicit hosted index')
            columns=tuple(connection.execute('SELECT * FROM pragma_index_xinfo(?)',(name,)).fetchall())
            result.add((unique,origin,partial,columns))
        return result
    normalize=lambda sql:re.sub(r'\s+',' ',sql).strip()
    with closing(sqlite3.connect(':memory:')) as expected:
        for name in names:
            expected.execute(HOSTED_SCHEMA[name])
            actual=db.execute('SELECT type,sql FROM sqlite_master WHERE name=?',(name,)).fetchone()
            known=expected.execute('SELECT type,sql FROM sqlite_master WHERE name=?',(name,)).fetchone()
            require(actual is not None and actual[0]=='table' and normalize(actual[1])==normalize(known[1])
                    and db.execute('SELECT * FROM pragma_table_xinfo(?)',(name,)).fetchall()==expected.execute('SELECT * FROM pragma_table_xinfo(?)',(name,)).fetchall()
                    and indices(db,name)==indices(expected,name),'unsupported hosted table shape or constraints')


def validate_hosted(db, repository):
    """Admit only supported hosted v1 shapes and internally bound recovery states."""
    names={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    cohort={name for name in names if name.startswith('intake_') or name=='feedback_private_proposals'}
    if not cohort:return
    require(cohort<=set(HOSTED_SCHEMA) and 'intake_hosted_identity' in cohort,'unsupported hosted intake namespace')
    required={'intake_hosted_identity','intake_requests','intake_events','intake_slack_heads','intake_slack_revisions'}
    require(required<=cohort,'incomplete hosted intake capture schema')
    require(('intake_assessments' in cohort)==('intake_decision_bindings' in cohort),'incomplete hosted assessment schema')
    require('intake_actions' not in cohort or 'intake_assessments' in cohort,'hosted action without assessment schema')
    require('feedback_private_proposals' not in cohort or 'intake_actions' in cohort,'hosted proposal without action schema')
    validate_shapes(db,cohort|{'factory_feedback','feedback_ingress_identity'})
    def rows(name):
        cursor=db.execute('SELECT * FROM '+name)
        fields=[item[0] for item in cursor.description]
        return [dict(zip(fields,row)) for row in cursor]
    marker=rows('intake_hosted_identity')
    hex64=lambda value:isinstance(value,str) and re.fullmatch('[a-f0-9]{64}',value) is not None
    require(len(marker)==1 and marker[0]['id']==1 and marker[0]['version']==1 and marker[0]['mode']=='hosted-slack-capture-v1'
            and marker[0]['repository']==repository and hex64(marker[0]['contract_sha256']),'unsupported hosted intake identity')
    contract=marker[0]['contract_sha256'];requests={row['id']:row for row in rows('intake_requests')};documents={};bases={}
    require({'factory_feedback','feedback_ingress_identity'}<=names,'hosted authenticated feedback provenance missing')
    ingress=db.execute('SELECT repository,team,destination FROM feedback_ingress_identity').fetchall()
    require(len(ingress)==1 and ingress[0][0]==repository,'hosted ingress identity differs')
    fields={'source_kind','origin','session','submission_key','source_revision','actor','repository','ref','content_revision','text','parent_request','delivery_token','feedback_id','digest_key','receipt_sha256'}
    for identity,row in requests.items():
        request=intake_document(row['document']);documents[identity]=request
        source=re.fullmatch(r'slack:([^/]+)/([^/]+)/([0-9]+\.[0-9]{1,6})(?::edit:([0-9]+\.[0-9]{1,6}))?',row['source_key'])
        require(isinstance(identity,str) and re.fullmatch('[a-f0-9]{32}',identity) and set(request)==fields and source is not None
                and tuple(source.group(i) for i in (1,2))==tuple(ingress[0][1:]) and request['source_kind']=='slack' and request['origin']=='human'
                and request['session']=='slack:'+source[1]+'/'+source[2] and request['submission_key']==row['source_key']
                and request['source_revision']==(source[4] or source[3]) and request['repository']==repository and request['delivery_token'] is None
                and hex64(request['content_revision']) and hex64(request['receipt_sha256']) and intake_hash(row['document'])==row['revision']
                and row['status'] in {'submitted','assessing','decided','blocked','superseded'} and row['assessment_count'] in (0,1),'hosted request provenance differs')
        base=row['source_key'].split(':edit:',1)[0];bases[identity]=base
        feedback=db.execute('SELECT document FROM factory_feedback WHERE id=?',(request['feedback_id'],)).fetchone()
        require(feedback is not None,'hosted feedback record missing')
        original=json.loads(feedback[0],object_pairs_hook=pairs)
        require(all(original[key]==request[target] for key,target in [('source_ref','submission_key'),('reporter','actor'),('repository','repository'),('text','text'),('digest_key','digest_key')]),'hosted feedback provenance differs')
        if row['decision'] is not None:
            decision=intake_document(row['decision'])
            decision_fields={'schema_version','request_id','revision','disposition','intents','rationale','evidence','uncertainty','spec','plan','task','next_action','blocked_reason'}
            allowed={'answer':{'answer'},'status':{'inspect'},'new_feature':{'draft','question'},'changed_requirement':{'draft','question'},
                     'defect':{'draft','question','inspect'},'clarify':{'question'},'risk_control':{'question','stop'},'unsupported':{'none'},'blocked':{'none'}}
            require(set(decision)==decision_fields and type(decision['schema_version']) is int and decision['schema_version']==1
                    and decision['request_id']==identity and decision['revision']==row['revision'] and decision['next_action'] in allowed.get(decision['disposition'],set())
                    and decision['uncertainty'] in {'none','missing_context','ambiguous','conflict'} and all(decision[key] is None for key in ('spec','plan','task'))
                    and isinstance(decision['rationale'],str) and 0<len(decision['rationale'])<=4000
                    and isinstance(decision['intents'],list) and 1<=len(decision['intents'])<=16,'unsupported hosted decision')
            for intent in decision['intents']:
                require(isinstance(intent,dict) and set(intent)=={'kind','summary','scope'} and intent['kind'] in allowed
                        and isinstance(intent['summary'],str) and 0<len(intent['summary'])<=2000 and isinstance(intent['scope'],list) and len(intent['scope'])<=100
                        and all(isinstance(path,str) and path and not path.startswith('/') and '\\' not in path and all(part not in {'','.','..'} for part in path.split('/')) for path in intent['scope']),
                        'unsupported hosted intent')
            require(isinstance(decision['evidence'],list) and len(decision['evidence'])<=100 and all(isinstance(item,dict) and set(item)=={'kind','ref','sha256'}
                    and (item['kind'],item['ref'],item['sha256']) in {('request',identity,row['revision']),('repository','delivered/digest.json',request['content_revision'])}
                    for item in decision['evidence']),'unsupported hosted evidence')
            require(decision['blocked_reason'] is None or isinstance(decision['blocked_reason'],str) and re.fullmatch('[a-z][a-z0-9_-]{0,99}',decision['blocked_reason']), 'unsupported hosted blocked reason')
            require(decision['disposition'] not in {'unsupported','blocked'} or decision['blocked_reason'] is not None,'hosted blocked reason missing')
        require(row['status'] not in {'decided','blocked'} or row['decision'] is not None,'hosted outcome missing')
    revisions={row['request_id']:row for row in rows('intake_slack_revisions')};heads=rows('intake_slack_heads')
    require(set(revisions)==set(requests) and {row['source_key'] for row in heads}==set(bases.values()),'hosted source lineage missing')
    for identity,row in revisions.items():
        request=documents[identity];parent=request['parent_request']
        require(row['source_key']==bases[identity] and row['source_revision']==request['source_revision'] and row['parent_request']==parent
                and row['kind'] in {'initial','source_edit','previous_unobserved'}
                and (parent is None or parent in requests and bases[parent]==bases[identity] and documents[parent]['actor']==request['actor']), 'hosted source lineage differs')
    from decimal import Decimal
    for row in heads:
        identity=row['request_id'];request=documents.get(identity)
        require(request is not None and row['source_key']==bases[identity] and row['source_revision']==request['source_revision'] and row['actor']==request['actor']
                and requests[identity]['status']!='superseded' and all(other==identity or requests[other]['status']=='superseded' for other in requests if bases[other]==bases[identity])
                and Decimal(row['source_revision'])==max(Decimal(documents[other]['source_revision']) for other in requests if bases[other]==bases[identity]),'hosted current source differs')
    require(all(row['request_id'] in requests for row in rows('intake_events')),'hosted event request missing')
    assessments={row['request_id']:row for row in rows('intake_assessments')} if 'intake_assessments' in cohort else {}
    bindings={row['request_id']:intake_document(row['document']) for row in rows('intake_decision_bindings')} if 'intake_decision_bindings' in cohort else {}
    require(set(assessments)==set(bindings),'hosted assessment reservation missing')
    for identity,row in assessments.items():
        request=requests.get(identity);binding=bindings[identity]
        require(request is not None and row['revision']==request['revision'] and request['assessment_count']==1
                and row['status'] in {'running','unknown','completed','blocked'} and binding['revision']==request['revision']
                and binding['request_document']==request['document'] and binding['contract_sha256']==contract
                and hex64(binding['profile_sha256']) and hex64(binding['context_sha256']) and isinstance(binding['selected'],dict),'hosted assessment provenance differs')
        selected=binding['selected'];selection_fields={'runtime','model','argv','profile_sha256','assessment_sha256','capability_evidence'}
        binding_fields={'attempt','revision','request_document','contract_sha256','profile_sha256','context_sha256','selected'}
        require(set(binding)==binding_fields|({'result_sha256'} if row['status']=='completed' else set())
                and isinstance(binding['attempt'],str) and re.fullmatch('[a-f0-9]{32}',binding['attempt']) and set(selected)==selection_fields
                and all(isinstance(selected[key],str) and selected[key] for key in ('runtime','model'))
                and isinstance(selected['argv'],list) and selected['argv'] and all(isinstance(arg,str) for arg in selected['argv'])
                and hex64(selected['profile_sha256']) and hex64(selected['assessment_sha256']) and selected['capability_evidence']=='protected-observation',
                'unsupported hosted assessment selection')
        if row['status'] in {'running','unknown'}:
            require(row['result'] is None and request['decision'] is None and request['status'] in {'assessing','superseded'},'hosted unresolved assessment differs')
        if row['status']=='blocked':
            require(request['status'] in {'blocked','superseded'} and request['decision'] is not None
                    and row['reason']==intake_document(request['decision'])['blocked_reason'],'hosted failed assessment differs')
        if row['status']=='completed':
            require(request['status'] in {'decided','superseded'} and row['result'] is not None,'hosted completed assessment outcome missing')
            raw=intake_document(row['result']);decision=intake_document(request['decision'])
            require(set(raw)==selection_fields|{'assessment','output_bytes'} and type(raw['output_bytes']) is int and 0<=raw['output_bytes']<=MAX_DATABASE
                    and binding.get('result_sha256')==intake_hash(row['result']) and all(raw.get(key)==value for key,value in binding['selected'].items())
                    and {**raw['assessment'],'request_id':identity,'revision':request['revision']}==decision,'hosted assessed decision differs')
    require(all(row['assessment_count']==0 or identity in assessments for identity,row in requests.items()),'hosted assessment history missing')
    require(all(row['status']!='decided' or identity in assessments and assessments[identity]['status']=='completed' for identity,row in requests.items()),'hosted decision assessment missing')
    actions={row['id']:row for row in rows('intake_actions')} if 'intake_actions' in cohort else {}
    for identity,row in actions.items():
        action=intake_document(row['document']);request=requests.get(row['request_id'])
        require(request is not None and row['request_id'] in assessments and assessments[row['request_id']]['status']=='completed'
                and set(action)=={'request_id','revision','kind','contract_sha256','decision_sha256','target_revision'}
                and action['request_id']==row['request_id'] and action['revision']==request['revision'] and action['kind']=='proposal_publish'
                and action['contract_sha256']==contract and action['decision_sha256']==intake_hash(request['decision']) and identity==intake_hash(row['document'])
                and row['status'] in {'reserved','unknown','completed'},'hosted action provenance differs')
        proposal={'schema_version':1,'status':'draft','approval':'pending','repository':repository,'request_id':row['request_id'],'revision':request['revision'],
                  'source':documents[row['request_id']],'decision':intake_document(request['decision'])}
        encoded=json.dumps(proposal,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)
        require(intake_document(request['decision'])['next_action']=='draft' and action['target_revision']==intake_hash(encoded), 'hosted proposal intent differs')
        result={'action_id':identity,'request_id':row['request_id'],'sha256':action['target_revision'],'status':'draft'}
        require((row['result'] is None if row['status']!='completed' else intake_document(row['result'])==result),'hosted proposal result differs')
    proposals=rows('feedback_private_proposals') if 'feedback_private_proposals' in cohort else []
    for row in proposals:
        action=actions.get(row['action_id']);proposal=intake_document(row['document'])
        require(action is not None and action['request_id']==row['request_id'] and proposal=={'schema_version':1,'status':'draft','approval':'pending','repository':repository,
                'request_id':row['request_id'],'revision':requests[row['request_id']]['revision'],'source':documents[row['request_id']],
                'decision':intake_document(requests[row['request_id']]['decision'])}
                and intake_hash(row['document'])==intake_document(action['document'])['target_revision'],'hosted proposal provenance differs')
    require(all(row['status']!='completed' or any(proposal['action_id']==identity for proposal in proposals) for identity,row in actions.items()),'hosted completed proposal missing')


def database_bytes(path):
    """Capture finite stable private SQLite bytes before decode or checkpoint work."""
    require(path.is_absolute() and path.resolve()==path,'private database must be canonical')
    require(not any(Path(str(path)+suffix).exists() for suffix in ('-wal','-shm','-journal')),'feedback database has uncheckpointed journals')
    descriptor=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        opened=os.fstat(descriptor)
        require(stat.S_ISREG(opened.st_mode) and opened.st_uid==os.getuid() and opened.st_nlink==1
                and stat.S_IMODE(opened.st_mode)==0o600 and 0<opened.st_size<=MAX_DATABASE,'private database type/mode/link/size invalid')
        with os.fdopen(descriptor,'rb',closefd=False) as handle:raw=handle.read(MAX_DATABASE+1)
        identity=lambda value:(value.st_dev,value.st_ino,value.st_uid,value.st_mode,value.st_nlink,value.st_size,value.st_mtime_ns,value.st_ctime_ns)
        require(len(raw)<=MAX_DATABASE and identity(opened)==identity(os.fstat(descriptor))==identity(path.lstat()),'private database changed during capture')
        return raw
    finally:os.close(descriptor)


def validate_database(path, repository):
    raw=database_bytes(path)
    with closing(sqlite3.connect(f'{path.as_uri()}?mode=ro',uri=True)) as db:
        db.execute('PRAGMA trusted_schema=OFF')
        require(db.execute('PRAGMA journal_mode').fetchone()[0]=='delete','feedback database must not use detached journals')
        validate_shapes(db,{'feedback_checkpoint_identity'})
        identities=db.execute('SELECT repository FROM feedback_checkpoint_identity WHERE id=1').fetchall()
        require(identities==[(repository,)],'feedback database repository differs')
        require(not db.execute("SELECT name FROM sqlite_master WHERE type IN ('view','trigger')").fetchall(),'feedback database contains executable schema')
        validate_hosted(db,repository)
        require(db.execute('PRAGMA quick_check').fetchall()==[('ok',)],'feedback database integrity failed')
    require(database_bytes(path)==raw,'private database changed during validation')
    return raw


@contextmanager
def private_database(checkpoint, secret, binding, *, checkpoint_ready=None):
    """Fresh authoritative holder per retry; failed operations never publish plaintext."""
    require(checkpoint_ready is None or callable(checkpoint_ready),'invalid runtime checkpoint receiver')
    previous=None if checkpoint.bytes is None else unseal(checkpoint.bytes,secret,binding)
    old=os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(prefix='factory-feedback-') as temporary:
            root=Path(temporary).resolve();path=root/'runtime.sqlite'
            if previous is None:
                with closing(sqlite3.connect(path)) as db, db:
                    db.execute('CREATE TABLE feedback_checkpoint_identity(id INTEGER PRIMARY KEY CHECK(id=1),repository TEXT NOT NULL)')
                    db.execute('INSERT INTO feedback_checkpoint_identity VALUES(1,?)',(binding['repository'],))
            else:
                path.write_bytes(previous)
            path.chmod(0o600)
            validate_database(path,binding['repository'])
            def persist():
                nonlocal previous
                current=validate_database(path,binding['repository'])
                if current!=previous:
                    checkpoint.checkpoint(seal(current,secret,binding))
                    previous=current
            if checkpoint_ready is not None:checkpoint_ready(persist)
            yield root,path
            persist()
    finally:
        os.umask(old)
