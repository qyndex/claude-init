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


def validate_database(path, repository):
    with closing(sqlite3.connect(f'{path.as_uri()}?mode=ro',uri=True)) as db:
        db.execute('PRAGMA trusted_schema=OFF')
        require(db.execute('PRAGMA journal_mode').fetchone()[0]=='delete','feedback database must not use detached journals')
        require(db.execute('PRAGMA quick_check').fetchall()==[('ok',)],'feedback database integrity failed')
        identities=db.execute('SELECT repository FROM feedback_checkpoint_identity WHERE id=1').fetchall()
        require(identities==[(repository,)],'feedback database repository differs')
        require(not db.execute("SELECT name FROM sqlite_master WHERE type IN ('view','trigger')").fetchall(),'feedback database contains executable schema')


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
                require(not path.is_symlink() and path.is_file() and path.stat().st_uid==os.getuid() and path.stat().st_mode&0o777==0o600,'private database path/mode changed')
                require(not any(Path(str(path)+suffix).exists() for suffix in ('-wal','-shm','-journal')),'feedback database has uncheckpointed journals')
                validate_database(path,binding['repository'])
                current=path.read_bytes()
                if current!=previous:
                    checkpoint.checkpoint(seal(current,secret,binding))
                    previous=current
            if checkpoint_ready is not None:checkpoint_ready(persist)
            yield root,path
            persist()
    finally:
        os.umask(old)
