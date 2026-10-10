#!/usr/bin/env bash
set -euo pipefail
ROOT="${DIGEST_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import copy,hashlib,importlib.util,json,multiprocessing,sys,tempfile,time
assert (Path(sys.argv[1])/'.claude/scripts/factory-digest.py').is_file(), 'durable digest not implemented'
spec=importlib.util.spec_from_file_location('digest',Path(sys.argv[1])/'.claude/scripts/factory-digest.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def reject(fn):
    try:fn()
    except (ValueError,BlockingIOError,RuntimeError):return
    raise AssertionError('unsafe report accepted')
class API:
    repo='org/repo'
    def __init__(self):
        self.pages=[[{'number':n,'title':f'Change {n}','html_url':f'https://github.com/org/repo/pull/{n}',
                     'merged_at':'2026-10-03T21:00:00Z','merge_commit_sha':'b'*40,
                     'head':{'sha':'c'*40},'base':{'ref':'main','repo':{'full_name':self.repo}}} for n in range(1,61)]]
        self.pages.append([dict(self.pages[0][0],number=61)])
        self.fail=False
    def request(self,path,**opts):
        assert opts['paginate'] is True and 'per_page=100' in path
        if self.fail:raise RuntimeError('API unavailable')
        return self.pages
class Remote:
    def __init__(self,path):self.path=Path(path);self.drop=False;self.unknown=False;self.ready=None;self.release=None
    def lookup(self,key):
        data=json.loads(self.path.read_text()) if self.path.exists() else {}
        return {'receipt':data.get(key),'authoritative_absence':not self.unknown}
    def send(self,key,payload,destination):
        if self.ready:
            self.ready.touch()
            while not self.release.exists():time.sleep(.02)
        data=json.loads(self.path.read_text()) if self.path.exists() else {}
        assert key not in data,'duplicate remote send'
        receipt={'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':destination,'message_id':str(len(data)+1)}
        data[key]=receipt;self.path.write_text(json.dumps(data))
        if self.drop:raise RuntimeError('remote succeeded; response lost')
        return receipt
assert m.cutoff('2026-10-03')=='2026-10-02T22:00:00+00:00'
assert m.cutoff('2026-10-04')=='2026-10-03T21:00:00+00:00'
assert m.cutoff('2026-04-04')=='2026-04-03T21:00:00+00:00'
assert m.cutoff('2026-04-05')=='2026-04-04T22:00:00+00:00'
with tempfile.TemporaryDirectory() as tmp:
    d=m.Digest(Path(tmp)/'db','org/repo','channel','2026-10-02T21:00:00Z');api=API();remote=Remote(Path(tmp)/'messages')
    # Install a minimal authenticated provenance fixture, never a global task scan.
    with d.transaction() as db:
        db.execute('CREATE TABLE delivery_receipts(task TEXT, revision TEXT, receipt TEXT)')
        db.execute('CREATE TABLE delivery_provenance(task TEXT, provenance TEXT)')
        receipt={'repository':'org/repo','pull_request':1,'merged':True,'eligible':True,'head_sha':'c'*40,'merge_sha':'b'*40,'spec_sha256':'a'*64,'spec':'015','task_ids':['T-188']}
        db.execute('INSERT INTO delivery_receipts VALUES(?,?,?)',('T-188','a'*64,json.dumps({'repository':'org/repo','pr':1,'merge_sha':'b'*40})))
        db.execute('INSERT INTO delivery_provenance VALUES(?,?)',('T-188',json.dumps({'receipt':receipt,'run_id':123,'artifact_digest':'sha256:'+'d'*64})))
    before=d.cursor();api.fail=True;reject(lambda:d.prepare(api,m.cutoff('2026-10-04')));assert d.cursor()==before
    reject(lambda:d.prepare(api,'2999-01-01T00:00:00Z'));assert d.cursor()==before
    api.fail=False
    api.pages[0][0]['head']['sha']='e'*40
    reject(lambda:d.prepare(api,m.cutoff('2026-10-04')));assert d.cursor()==before
    api.pages[0][0]['head']['sha']='c'*40
    api.pages.append([dict(api.pages[0][0],number=99,merged_at=None),dict(api.pages[0][0],number=100,base={'ref':'other','repo':{'full_name':'org/repo'}})])
    batch=d.prepare(api,m.cutoff('2026-10-04'));payload=json.loads(batch['payload'])
    assert len(payload['merges'])==61 and payload['merges'][0]['delivery_evidence'][0]['task']=='T-188'
    assert all(p['evidence_status']=='missing' for p in payload['merges'][1:])
    assert d.prepare(api,m.cutoff('2026-10-05'))==batch
    remote.drop=True;reject(lambda:d.deliver(batch['key'],remote));assert d.cursor()==before and d.batch(batch['key'])['status']=='uncertain'
    remote.drop=False;d.deliver(batch['key'],remote);d.deliver(batch['key'],remote)
    assert len(json.loads(remote.path.read_text()))==1 and d.cursor()==batch['cutoff']
    # Same timestamp merges were all delivered; next interval excludes all 61.
    next_batch=d.prepare(api,m.cutoff('2026-10-05'));assert json.loads(next_batch['payload'])['merges']==[]
    with d.transaction() as db:db.execute("UPDATE digest_batches SET status='uncertain' WHERE key=?",(next_batch['key'],))
    remote.unknown=True;reject(lambda:d.deliver(next_batch['key'],remote));assert d.cursor()==batch['cutoff']
    remote.unknown=False
    remote.ready=Path(tmp)/'ready';remote.release=Path(tmp)/'release'
    proc=multiprocessing.get_context('fork').Process(target=d.deliver,args=(next_batch['key'],remote));proc.start()
    end=time.monotonic()+10
    while not remote.ready.exists() and time.monotonic()<end:time.sleep(.02)
    assert remote.ready.exists();reject(lambda:d.deliver(next_batch['key'],remote))
    remote.release.touch();proc.join(10);assert proc.exitcode==0
    assert len(json.loads(remote.path.read_text()))==2 and d.cursor()==next_batch['cutoff']
    wrong=copy.deepcopy(json.loads(d.batch(batch['key'])['receipt']));wrong['message_id']='forged'
    reject(lambda:d.confirm(batch,wrong));assert d.cursor()==next_batch['cutoff']
    wrong['payload_sha256']='0'*64;reject(lambda:d.confirm(batch,wrong))
print('factory-digest: pagination, equal-time merges, proof mapping, DST, outage catch-up, uncertain sends and process exclusion passed')
PYTEST
