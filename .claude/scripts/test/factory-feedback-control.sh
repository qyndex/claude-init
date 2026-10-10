#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import copy,hashlib,importlib.util,json,os,sys
from pathlib import Path
from datetime import datetime,timezone
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-feedback-control.py';assert path.exists(),'authenticated control adapter absent'
spec=importlib.util.spec_from_file_location('control',path);c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
fixture=(root/'.claude/scripts/test/factory-feedback.sh').read_text().split("<<'PY'\n",1)[1].split('    # Legacy closure entry point',1)[0]
# Reuse the actual feedback fixture while its private SQLite/report context remains open.
addition='''
    private=Path(tmp).resolve();private.chmod(0o700);database=runtime.resolve();database.chmod(0o600)
    config={'enabled':True,'feedback_control_enabled':True,'repository':'org/repo','team_id':'T1','destination':'C1','operators':['U1'],'private_root':str(private),'runtime_database':str(database),'implementation_roots':[str(root)],'feedback_start':'2026-10-04T00:00:00Z','approved_specs':policy['specs'],'amendment_proposals':{}}
    with f.store.transaction() as db:
        db.execute('CREATE TABLE feedback_ingress_identity(id INTEGER PRIMARY KEY,repository TEXT,team TEXT,destination TEXT)');db.execute("INSERT INTO feedback_ingress_identity VALUES(1,'org/repo','T1','C1')")
    doc['source_ref']='slack:T1/C1/control-source';third=f.intake(report,doc);f.store.enqueue('T-5','5'*64,[])
    config['approved_specs']['005']={'sha256':'5'*64,'task_ids':['T-5']}
    proposal={'impact':'Operator reviewed exact impact.','bindings':[{'task':'T-5','spec':'005','revision':'5'*64}],'supersedes':[]}
    digest=hashlib.sha256(m.canonical(proposal).encode()).hexdigest();config['amendment_proposals'][third]={digest:proposal}
    now=datetime(2026,10,4,22,tzinfo=timezone.utc);stamp=str(int(now.timestamp())-10)+'.000001'
    class Client:
        def __init__(self):self.inputs=[];self.wrong=False
        def call(self,method,body):
            if method=='auth.test':return {'team_id':'OTHER' if self.wrong else 'T1','bot_id':'B1'}
            assert method=='conversations.history';return {'messages':copy.deepcopy(self.inputs),'has_more':False}
    client=Client()
    def command(text,ts=stamp,user='U1'):return {'type':'message','user':user,'ts':ts,'text':text}
    approve=command(f'factory approve {third} version 1 sha256:{digest}')
    client.inputs=[approve,command('factory accept malformed',user='U2')]
    assert c.ingress.messages(client,config,now)==[], 'capture poller rejected approval commands'
    assert c.run(config,client,now)=={'commands':1,'confirmed':1};assert f.reconcile(third)=='planned'
    with f.store.transaction() as db:count=db.execute('SELECT COUNT(*) FROM feedback_events WHERE feedback=?',(third,)).fetchone()[0]
    assert c.run(config,client,now)['confirmed']==1
    with f.store.transaction() as db:assert f.row(db,third)['version']==1 and db.execute('SELECT COUNT(*) FROM feedback_events WHERE feedback=?',(third,)).fetchone()[0]==count
    print('AC-1: authenticated exact hash/version approval, private namespace, outsider filtering and immutable command replay passed')
    accept=command(f'factory accept {third} version 1',str(int(now.timestamp())-5)+'.000001');client.inputs=[accept]
    reject(lambda:c.run(config,client,now));assert f.reconcile(third)=='planned'
    with f.store.transaction() as db:db.execute("UPDATE tasks SET state='merged' WHERE id='T-5'")
    reject(lambda:c.run(config,client,now));receipt('T-5','5'*64,'005',5)
    assert c.run(config,client,now)['confirmed']==1 and f.reconcile(third)=='accepted'
    assert c.run(config,client,now)['confirmed']==1
    f.accept(third,'U1',f'slack:T1/C1/{accept["ts"]}')
    reject(lambda:f.accept(third,'U1',f'slack:T1/C1/{accept["ts"]}',expected_version=2))
    print('AC-2: acceptance requires full matching delivery provenance and exact version, with durable replay and distinct delivered/accepted state')
    doc['source_ref']='slack:T1/C1/control-second';fourth=f.intake(report,doc);config['amendment_proposals'][fourth]={digest:proposal}
    client.inputs=[command(f'factory approve {fourth} version 1 sha256:{digest}',str(int(now.timestamp())-4)+'.000001')]
    original=c.f.Feedback.event
    def lose_confirmation(db,identity,event):
        if event['type']=='operator-command':raise OSError('lost confirmation')
        return original(db,identity,event)
    c.f.Feedback.event=staticmethod(lose_confirmation)
    try:
        try:c.run(config,client,now)
        except OSError:pass
        else:raise AssertionError('confirmation loss absent')
    finally:c.f.Feedback.event=staticmethod(original)
    assert f.reconcile(fourth)=='delivered';assert c.run(config,client,now)['confirmed']==1
    with f.store.transaction() as db:assert f.row(db,fourth)['version']==1
    changed_proposal=copy.deepcopy(proposal);changed_proposal['impact']='Conflicting second approval';other=hashlib.sha256(m.canonical(changed_proposal).encode()).hexdigest()
    config['amendment_proposals'][fourth][other]=changed_proposal
    client.inputs=[command(f'factory approve {fourth} version 1 sha256:{other}',str(int(now.timestamp())-2)+'.000001')]
    reject(lambda:c.run(config,client,now))
    authority={'repository':'org/repo','specs':config['approved_specs'],'feedback_amendments':{fourth:other}}
    reject(lambda:f.plan(fourth,changed_proposal,authority,expected_version=1))
    with f.store.transaction() as db:assert f.row(db,fourth)['version']==1
    print('AC-3: lost control confirmation resumes committed amendment once; stale/conflicting approvals fenced inside core transaction')
    client.inputs=[copy.deepcopy(approve)];client.inputs[0]['edited']={'user':'U1','ts':stamp};reject(lambda:c.run(config,client,now))
    client.inputs=[command(f'factory accept {fourth} version 2')];reject(lambda:c.run(config,client,now))
    client.inputs=[command(f'factory approve {fourth} version 2 sha256:{"f"*64}')];reject(lambda:c.run(config,client,now))
    client.inputs=[approve];client.wrong=True;reject(lambda:c.run(config,client,now));client.wrong=False
    reject(lambda:c.run({**config,'feedback_control_enabled':False},client,now))
    reject(lambda:c.run({**config,'destination':'C2'},client,now))
    duplicate=copy.deepcopy(approve);duplicate['text']=f'factory accept {third} version 1';client.inputs=[approve,duplicate];reject(lambda:c.run(config,client,now))
    assert f.reconcile(third)=='accepted';assert f.reconcile(fourth)=='delivered'
    print('AC-4: edits, stale acceptance, missing protected proposals, disabled/foreign configuration and conflicting authenticated sources fail closed')
'''
exec(fixture+addition,globals())
PYTEST
