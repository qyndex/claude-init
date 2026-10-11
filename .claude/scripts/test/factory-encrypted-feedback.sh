#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import base64,copy,importlib.util,json,os,sqlite3,sys
from pathlib import Path
path=Path(sys.argv[1])/'.claude/scripts/factory-encrypted-feedback.py'
assert path.exists(),'authenticated encrypted feedback checkpoint absent'
spec=importlib.util.spec_from_file_location('encrypted',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def reject(fn):
    try:fn()
    except Exception:return
    raise AssertionError('unsafe encrypted checkpoint accepted')
class Checkpoint:
    def __init__(self):self.bytes=None;self.writes=0;self.lost_ack=False
    def checkpoint(self,data):
        self.bytes=data;self.writes+=1
        if self.lost_ack:raise OSError('lost remote acknowledgement')
store=Checkpoint();secret=os.urandom(32);binding=m.context('org/repo','C1','main','key-v1')
with m.private_database(store,secret,binding) as (root,path):
    private=path;assert root.stat().st_mode&0o777==0o700 and path.stat().st_mode&0o777==0o600
    with sqlite3.connect(path) as db:
        db.execute('CREATE TABLE signals(id INTEGER PRIMARY KEY,text TEXT)');db.execute('INSERT INTO signals VALUES(1,?)',('PRIVATE FEEDBACK EXACT WORDS',))
assert not private.exists() and b'PRIVATE FEEDBACK' not in store.bytes and b'SQLite format' not in store.bytes
raw=m.unseal(store.bytes,secret,binding)
assert b'PRIVATE FEEDBACK EXACT WORDS' in raw
assert set(json.loads(store.bytes))==m.FIELDS
print('AC-1: real AES-256-GCM roundtrip preserves exact SQLite feedback with private temporary modes and ciphertext-only padded envelope')
for changed in [dict(binding,repository='foreign/repo'),m.context('org/repo','C2','main','key-v1'),dict(binding,key_id='key-v2')]:reject(lambda:m.unseal(store.bytes,secret,changed))
reject(lambda:m.unseal(store.bytes,os.urandom(32),binding))
doc=json.loads(store.bytes);cipher=bytearray(base64.b64decode(doc['ciphertext']));cipher[-1]^=1;doc['ciphertext']=base64.b64encode(cipher).decode();reject(lambda:m.unseal(m.canonical(doc),secret,binding))
reject(lambda:m.unseal(store.bytes[:-1],secret,binding));reject(lambda:m.unseal(store.bytes.replace(b'"schema_version":1',b'"schema_version":1,"schema_version":1'),secret,binding))
print('AC-2: wrong key, altered ciphertext, duplicate fields, truncation and foreign repository/channel/key bindings fail before opening plaintext SQLite')
prior=store.bytes
with m.private_database(store,secret,binding) as (_,path):
    with sqlite3.connect(path) as db:assert db.execute('SELECT text FROM signals').fetchone()[0]=='PRIVATE FEEDBACK EXACT WORDS'
assert store.bytes==prior and store.writes==1
store.lost_ack=True
try:
    with m.private_database(store,secret,binding) as (_,path):
        with sqlite3.connect(path) as db:db.execute('INSERT OR IGNORE INTO signals VALUES(2,"second")')
except OSError:pass
else:raise AssertionError('lost acknowledgement not surfaced')
store.lost_ack=False;writes=store.writes
with m.private_database(store,secret,binding) as (_,path):
    with sqlite3.connect(path) as db:db.execute('INSERT OR IGNORE INTO signals VALUES(2,"second")');assert db.execute('SELECT COUNT(*) FROM signals').fetchone()[0]==2
assert store.writes==writes
assert m.seal(raw,secret,binding)!=m.seal(raw,secret,binding)
print('AC-3: unchanged state avoids nonce/checkpoint churn; lost-ack replay starts from authoritative ciphertext and preserves idempotent records')
prior=store.bytes
try:
    with m.private_database(store,secret,binding) as (_,path):
        with sqlite3.connect(path) as db:db.execute('DELETE FROM signals')
        raise RuntimeError('intake failed')
except RuntimeError:pass
assert store.bytes==prior
reject(lambda:m.seal(b'x'*m.MAX_DATABASE,secret,binding));reject(lambda:m.key('bad'))
def poison():
    with m.private_database(store,secret,binding) as (_,path):
        with sqlite3.connect(path) as db:db.execute('UPDATE feedback_checkpoint_identity SET repository="foreign/repo"')
reject(poison);assert store.bytes==prior
def executable_schema():
    with m.private_database(store,secret,binding) as (_,path):
        with sqlite3.connect(path) as db:db.execute('CREATE VIEW unsafe AS SELECT * FROM signals')
reject(executable_schema);assert store.bytes==prior
def detached_journal():
    with m.private_database(store,secret,binding) as (_,path):
        Path(str(path)+'-journal').write_bytes(b'uncertain journal')
reject(detached_journal);assert store.bytes==prior
assert m.key(base64.b64encode(secret).decode())==secret
# Retain every actual connection so garbage collection cannot hide an open handle.
connections=[];original_connect=m.sqlite3.connect
def tracked_connect(*args,**kwargs):
    connection=original_connect(*args,**kwargs);connections.append(connection);return connection
m.sqlite3.connect=tracked_connect
try:
    with m.private_database(type(store)(),secret,binding):pass
finally:m.sqlite3.connect=original_connect
for connection in connections:
    try:connection.execute('SELECT 1')
    except sqlite3.ProgrammingError:pass
    else:raise AssertionError('private checkpoint SQLite handle remained open')
print('AC-4: failed intake, invalid key/database and foreign SQLite identity cannot publish partial state; private plaintext is removed after success or failure')
PY
