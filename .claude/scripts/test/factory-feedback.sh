#!/usr/bin/env bash
set -euo pipefail
ROOT="${FEEDBACK_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import copy,hashlib,importlib.util,json,os,subprocess,sys,tempfile
root=Path(sys.argv[1]);assert (root/'.claude/scripts/factory-feedback.py').is_file(), 'receipt-gated feedback not implemented'
spec=importlib.util.spec_from_file_location('feedback',root/'.claude/scripts/factory-feedback.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def reject(fn):
    try:fn()
    except (ValueError,KeyError):return
    raise AssertionError('unsafe feedback accepted')
class API:
    repo='org/repo'
    def request(self,*args,**kwargs):return [[{'number':1,'title':'Feature','html_url':'https://github.com/org/repo/pull/1','merged_at':'2026-10-02T00:00:00Z','merge_commit_sha':'a'*40,'head':{'sha':'b'*40},'base':{'ref':'main','repo':{'full_name':self.repo}}}]]
class Transport:
    def send(self,key,payload,destination):return {'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':destination,'message_id':'1.1'}
with tempfile.TemporaryDirectory() as tmp:
    report=Path(tmp)/'report';runtime=Path(tmp)/'runtime'
    d=m.digest.Digest(report,'org/repo','C1','2026-10-01T00:00:00Z');batch=d.prepare(API(),'2026-10-03T00:00:00Z')
    f=m.Feedback(runtime,'org/repo');doc={'repository':'org/repo','source_ref':'slack:T1/C1/123.45','reporter':'U1','text':'Please fix\nmy exact words <@U2>','kind':'defect','digest_key':batch['key'],'pull_requests':[1]}
    reject(lambda:f.intake(report,doc));d.deliver(batch['key'],Transport());identity=f.intake(report,doc);assert f.intake(report,doc)==identity
    changed=copy.deepcopy(doc);changed['text']='edited';reject(lambda:f.intake(report,changed))
    changed=copy.deepcopy(doc);changed['pull_requests']=[2];reject(lambda:f.intake(report,changed))
    changed=copy.deepcopy(doc);changed['repository']='foreign/repo';reject(lambda:f.intake(report,changed))
    assert f.reconcile(identity)=='open'
    f.store.enqueue('T-1','1'*64,[]);f.store.enqueue('T-2','2'*64,[]);f.store.enqueue('T-3','3'*64,[])
    old_claim=f.store.claim('T-3','worker',30,now=1)
    f.store.transition('T-3','worker',old_claim,'implementing',action=('old-effect',{'op':'create-pr'}),now=2)
    f.store.dispatch('old-effect','sender',30,now=3)
    amendment={'impact':'Repair two affected specs, supersede pending old revision.','bindings':[{'task':'T-1','spec':'001','revision':'1'*64},{'task':'T-2','spec':'002','revision':'2'*64}],'supersedes':['3'*64]}
    policy={'repository':'org/repo','specs':{'001':{'sha256':'1'*64,'task_ids':['T-1']},'002':{'sha256':'2'*64,'task_ids':['T-2']}},'feedback_amendments':{identity:hashlib.sha256(m.canonical(amendment).encode()).hexdigest()}}
    reject(lambda:f.plan(identity,amendment,{**policy,'feedback_amendments':{}}))
    assert f.plan(identity,amendment,policy)==1;assert f.plan(identity,amendment,policy)==1
    assert f.store.actions()[0]['status']=='uncertain'
    reject(lambda:f.store.heartbeat('T-3','worker',old_claim,30,now=4))
    f.store.reconcile('old-effect',None,remote_absent=True)
    reject(lambda:f.store.dispatch('old-effect','sender',30,now=4))
    with f.store.transaction() as db:
        row=f.store.row(db,'T-3');assert row['state']=='blocked' and row['owner'] is None and row['fence']>old_claim
        db.execute("UPDATE tasks SET state='merged' WHERE id IN ('T-1','T-2')")
    assert f.reconcile(identity)=='planned', 'local merged markers closed feedback without receipts'
    reject(lambda:f.accept(identity,'operator','slack:accept'))
    def receipt(task,revision,spec_id,pr):
        delivery={'repository':'org/repo','pr':pr,'merge_sha':'a'*40}
        provenance={'run_id':100+pr,'receipt':{'repository':'org/repo','pull_request':pr,'merge_sha':'a'*40,'spec':spec_id,'spec_sha256':revision,'task_ids':[task],'merged':True,'eligible':True}}
        with f.store.transaction() as db:
            db.execute('CREATE TABLE IF NOT EXISTS delivery_receipts(task TEXT PRIMARY KEY,revision TEXT,receipt TEXT)');db.execute('CREATE TABLE IF NOT EXISTS delivery_provenance(task TEXT PRIMARY KEY,provenance TEXT)')
            db.execute('INSERT INTO delivery_receipts VALUES(?,?,?)',(task,revision,json.dumps(delivery)));db.execute('INSERT INTO delivery_provenance VALUES(?,?)',(task,json.dumps(provenance)))
    receipt('T-1','1'*64,'001',1)
    assert f.reconcile_spec('001')[identity]=='planned', 'partial multi-spec delivery closed feedback'
    receipt('T-2','2'*64,'002',2)
    with f.store.transaction() as db:
        original=db.execute("SELECT provenance FROM delivery_provenance WHERE task='T-2'").fetchone()[0];bad=json.loads(original);bad['receipt']['spec_sha256']='9'*64
        db.execute("UPDATE delivery_provenance SET provenance=? WHERE task='T-2'",(json.dumps(bad),))
    reject(lambda:f.reconcile(identity))
    with f.store.transaction() as db:
        assert f.row(db,identity)['status']=='planned'
        db.execute("UPDATE delivery_provenance SET provenance=? WHERE task='T-2'",(original,))
    assert f.reconcile(identity)=='delivered'
    assert f.reconcile_spec('002')[identity]=='delivered'
    f.accept(identity,'operator','slack:T1/C1/accept');f.accept(identity,'operator','slack:T1/C1/accept');assert f.reconcile(identity)=='accepted'
    reject(lambda:f.accept(identity,'someone','other-source'))
    with f.store.transaction() as db:
        row=f.row(db,identity);assert json.loads(row['document'])['text']==doc['text'];assert db.execute('SELECT COUNT(*) FROM feedback_events WHERE feedback=?',(identity,)).fetchone()[0]==4
    # A fresh requirement signal gets a versioned plan; old delivery cannot satisfy newer revisions.
    doc['source_ref']='slack:T1/C1/new';second=f.intake(report,doc)
    policy['feedback_amendments'][second]=hashlib.sha256(m.canonical(amendment).encode()).hexdigest();f.plan(second,amendment,policy);assert f.reconcile(second)=='delivered'
    f.store.enqueue('T-4','4'*64,[])
    newer={'impact':'Changed requirement','bindings':[{'task':'T-4','spec':'004','revision':'4'*64}],'supersedes':['1'*64]}
    policy['specs']['004']={'sha256':'4'*64,'task_ids':['T-4']};policy['feedback_amendments'][second]=hashlib.sha256(m.canonical(newer).encode()).hexdigest()
    assert f.plan(second,newer,policy)==2;assert f.reconcile(second)=='planned'
    with f.store.transaction() as db:assert f.store.row(db,'T-1')['state']=='merged', 'completed delivery history erased'
    # Legacy closure entry point no longer sed-closes candidate-owned markdown.
    env=dict(os.environ);env.pop('FACTORY_RUNTIME_DB',None);env.pop('FACTORY_REPOSITORY',None)
    legacy=subprocess.run(['bash',str(root/'.claude/scripts/post-ship-close-feedback.sh'),'001'],env=env,capture_output=True,text=True)
    assert legacy.returncode==1 and 'Feedback remains open' in legacy.stderr
    wrapper=(root/'.claude/scripts/post-ship-close-feedback.sh').read_text();assert 'factory-feedback.py' in wrapper and 'sed -i' not in wrapper and 'mv "$fb"' not in wrapper
print('factory-feedback: immutable intake, delivered source, full approved amendments, stale fencing, multi-spec receipts, versions and separate acceptance passed')
PY
