#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
case "${1:-authenticated}" in authenticated|edits-replay) ;; *) exit 2 ;; esac
python3 - "$ROOT" "${1:-authenticated}" <<'PYTEST'
import copy,importlib.util,json,os,sqlite3,sys,tempfile
from pathlib import Path
from datetime import datetime,timedelta,timezone
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-slack-feedback.py';assert path.exists(),'authenticated private Slack feedback adapter is absent'
spec=importlib.util.spec_from_file_location('ingress',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
fixture=(root/'.claude/scripts/test/factory-hosted-digest.sh').read_text();ns={};exec(fixture.split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory() as tmp:',1)[0],ns)
hosted=ns['m']
class API(ns['GitAPI']):
    def __init__(self):super().__init__();self.forbid_writes=False
    def request(self,path,method='GET',payload=None):
        if self.forbid_writes:assert method=='GET' and payload is None
        return super().request(path,method,payload)
class Client:
    def __init__(self):self.reports=[];self.input=[];self.pages=[];self.posts=0;self.wrong=False;self.hide_report=False
    def call(self,method,body):
        if method=='auth.test':return {'team_id':'OTHER' if self.wrong else 'T1','bot_id':'B1'}
        if method=='chat.postMessage':
            self.posts+=1;message={'bot_id':'B1','text':body['text'],'metadata':body['metadata'],'ts':'100.000001'};self.reports.append(message);return {'channel':'C1','message':message}
        assert method=='conversations.history'
        if 'oldest' in body:
            assert body['channel']=='C1' and body['include_all_metadata'] is True and body['inclusive'] is True
            if body.get('limit')==100:
                return {'messages':copy.deepcopy(self.input[1:] if body.get('cursor')=='next' else self.input[:1]),'has_more':not bool(body.get('cursor')),'response_metadata':{'next_cursor':'' if body.get('cursor') else 'next'}}
        return {'messages':[] if self.hide_report else copy.deepcopy(self.reports)}
def rejects(fn):
    try:fn()
    except (ValueError,KeyError):return
    raise AssertionError('untrusted private feedback accepted')
if sys.argv[2]=='authenticated':
    # AC-1 / AC-2: actual authenticated ingress, real bound digest checkpoint, fake clients only.
    import hashlib
    with tempfile.TemporaryDirectory() as tmp:
        private=Path(tmp).resolve();private.chmod(0o700);now=datetime(2026,10,4,22,tzinfo=timezone.utc)
        config=dict(ns['config'],feedback_enabled=True,state_repository='org/repo',private_root=str(private),runtime_database=str(private/'runtime.sqlite'),operators=['U1'],feedback_start='2026-10-04T00:00:00Z',implementation_roots=[str(root)])
        api=API();client=Client();assert hosted.run(config,ns['ReportAPI'](),api,client,private/'initial-report',now)['status']=='delivered'
        api.forbid_writes=True;before=(api.head,api.writes,client.posts)
        controller=root/'.claude/scripts/factory-intake.py'
        stable={key:value for key,value in config.items() if key not in {'private_root','runtime_database','implementation_roots','intake_config'}}
        policy={'schema_version':1,'enabled':True,'mode':'hosted-slack-capture-v1','repository':'org/repo','team_id':'T1','destination':'C1','stream':hashlib.sha256(hosted.canonical(['org/repo','C1','main']).encode()).hexdigest(),'feedback_config_sha256':hashlib.sha256(hosted.canonical(stable).encode()).hexdigest(),'controller_sha256':hashlib.sha256(controller.read_bytes()).hexdigest()}
        policy_path=private/'intake.json';policy_path.write_text(json.dumps(policy));policy_path.chmod(0o600);config['intake_config']=str(policy_path)
        ts=str(int(now.timestamp())-10)+'.000001'
        message={'type':'message','user':'U1','ts':ts,'text':'factory feedback #1 enhancement: add login'}
        client.input=[message,dict(message,user='U2'),dict(message,bot_id='B2'),dict(message,text='hello'),dict(message,thread_ts='1.000001')]
        result=m.run(config,api,client,now);assert result['captured']==1
        with sqlite3.connect(config['runtime_database']) as db:
            assert db.execute("SELECT name FROM sqlite_master WHERE name='intake_requests'").fetchone(), 'authenticated Slack feedback did not enter intake'
            rows=db.execute('SELECT id,source_key,document,revision,status,assessment_count FROM intake_requests').fetchall();assert len(rows)==1
            request=json.loads(rows[0][2]);assert request['source_kind']=='slack' and request['actor']=='U1' and request['repository']=='org/repo'
            assert request['submission_key']==f'slack:T1/C1/{ts}' and request['source_revision']==ts and request['text']==message['text']
            assert request['session']=='slack:T1/C1' and request['ref']=='main' and request['parent_request'] is None
            assert request['feedback_id']==result['identities'][0] and request['digest_key'] and request['receipt_sha256'] and request['content_revision']
            assert rows[0][4:] == ('submitted',0) and rows[0][3]==hashlib.sha256(hosted.canonical(request).encode()).hexdigest()
            assert db.execute('SELECT COUNT(*) FROM tasks').fetchone()[0]==0
            assert not db.execute("SELECT name FROM sqlite_master WHERE name='runtime_intake_required'").fetchone()
        assert m.run(config,api,client,now)==result and before==(api.head,api.writes,client.posts)
        with sqlite3.connect(config['runtime_database']) as db:assert db.execute('SELECT COUNT(*) FROM intake_requests').fetchone()[0]==1
        def count():
            with sqlite3.connect(config['runtime_database']) as db:return db.execute('SELECT COUNT(*) FROM intake_requests').fetchone()[0]
        fresh=dict(message,ts=str(int(now.timestamp())-8)+'.000001')
        client.input=[fresh];client.hide_report=True;rejects(lambda:m.run(config,api,client,now));client.hide_report=False;assert count()==1
        client.wrong=True;rejects(lambda:m.run(config,api,client,now));client.wrong=False;assert count()==1
        client.input=[dict(fresh,text='factory feedback #999 defect: absent')];rejects(lambda:m.run(config,api,client,now));assert count()==1
        client.input=[fresh]
        rejects(lambda:m.run({key:value for key,value in config.items() if key!='intake_config'},api,client,now));assert count()==1
        for changes in [{'enabled':False},{'repository':'other/repo'},{'team_id':'OTHER'},{'controller_sha256':'0'*64},{'feedback_config_sha256':'0'*64},{'extra':True}]:
            policy_path.write_text(json.dumps(dict(policy,**changes)));rejects(lambda:m.run(config,api,client,now));assert count()==1
        policy_path.write_text(json.dumps(policy));policy_path.chmod(0o644);rejects(lambda:m.run(config,api,client,now));policy_path.chmod(0o600)
        # AC-6: invalid policy must reject before captured helper code executes.
        real_file=m.__file__;helper_root=private/'adapters/scripts/nested';helper_root.mkdir(parents=True);fake_controller=helper_root/'factory-intake.py'
        fake_controller.write_text("raise AssertionError('untrusted helper executed before policy validation')\n")
        hostile=dict(policy,mode='invalid',controller_sha256=hashlib.sha256(fake_controller.read_bytes()).hexdigest())
        policy_path.write_text(json.dumps(hostile));m.__file__=str(helper_root/'factory-slack-feedback.py')
        try:rejects(lambda:m.run(config,api,client,now))
        finally:m.__file__=real_file;policy_path.write_text(json.dumps(policy))
        # AC-6: a symlinked controller cannot execute even when its target matches the configured digest.
        target=helper_root/'untrusted-source.py';target.write_bytes(fake_controller.read_bytes())
        fake_controller.unlink();fake_controller.symlink_to(target)
        policy_path.write_text(json.dumps(dict(policy,controller_sha256=hashlib.sha256(target.read_bytes()).hexdigest())))
        m.__file__=str(helper_root/'factory-slack-feedback.py')
        try:rejects(lambda:m.run(config,api,client,now))
        finally:m.__file__=real_file;policy_path.write_text(json.dumps(policy));fake_controller.unlink();fake_controller.write_bytes(target.read_bytes())
        # AC-6: finite regular-file capture rejects FIFO, hardlinks, writable source and concurrent growth.
        fifo=helper_root/'fifo';os.mkfifo(fifo);rejects(lambda:m.captured_file(fifo,100))
        hardlink=helper_root/'hardlink.py';os.link(target,hardlink);rejects(lambda:m.captured_file(hardlink,100));hardlink.unlink()
        target.chmod(0o666);rejects(lambda:m.captured_file(target,100));target.chmod(0o600)
        oversized=helper_root/'oversized';oversized.write_bytes(b'x'*101);rejects(lambda:m.captured_file(oversized,100))
        changing=helper_root/'changing';changing.write_bytes(b'initial');original_fdopen=m.os.fdopen
        class ChangingReader:
            def __init__(self,*args,**kwargs):self.handle=original_fdopen(*args,**kwargs)
            def __enter__(self):return self
            def __exit__(self,*args):self.handle.close()
            def read(self,bound):
                raw=self.handle.read(bound);changing.write_bytes(b'changed-after-capture');return raw
        m.os.fdopen=ChangingReader
        try:rejects(lambda:m.captured_file(changing,100))
        finally:m.os.fdopen=original_fdopen
        # Default OFF skips helper reads/execution; partial marker loss cannot become legacy capture.
        legacy_config={key:value for key,value in config.items() if key!='intake_config'}
        legacy_config['runtime_database']=str(private/'legacy.sqlite');m.__file__=str(helper_root/'factory-slack-feedback.py')
        try:assert m.run(legacy_config,api,client,now)['captured']==1
        finally:m.__file__=real_file
        with sqlite3.connect(legacy_config['runtime_database']) as db:
            assert not db.execute("SELECT name FROM sqlite_master WHERE name GLOB 'intake_*'").fetchone()
        with sqlite3.connect(config['runtime_database']) as db:
            db.execute('ALTER TABLE intake_hosted_identity RENAME TO saved_hosted_identity')
        rejects(lambda:m.run({key:value for key,value in config.items() if key!='intake_config'},api,client,now))
        with sqlite3.connect(config['runtime_database']) as db:db.execute('ALTER TABLE saved_hosted_identity RENAME TO intake_hosted_identity')
        local_config=dict(config,runtime_database=str(private/'local.sqlite'))
        with sqlite3.connect(local_config['runtime_database']) as db:db.execute('CREATE TABLE intake_identity(id INTEGER)')
        Path(local_config['runtime_database']).chmod(0o600);rejects(lambda:m.run(local_config,api,client,now))
        assert before==(api.head,api.writes,client.posts)
        print('AC-1/AC-2: authenticated receipt-bound Slack capture, protected stable hosted identity, default-off compatibility, no worker grant passed')

elif sys.argv[2]=='edits-replay':
    # AC-1 / AC-2: actual authenticated ingress, real bound digest checkpoint, fake clients only.
    import hashlib
    with tempfile.TemporaryDirectory() as tmp:
        private=Path(tmp).resolve();private.chmod(0o700);now=datetime(2026,10,4,22,tzinfo=timezone.utc)
        config=dict(ns['config'],feedback_enabled=True,state_repository='org/repo',private_root=str(private),runtime_database=str(private/'runtime.sqlite'),operators=['U1','U2'],feedback_start='2026-10-04T00:00:00Z',implementation_roots=[str(root)])
        api=API();client=Client();assert hosted.run(config,ns['ReportAPI'](),api,client,private/'initial-report',now)['status']=='delivered'
        api.forbid_writes=True;before=(api.head,api.writes,client.posts)
        controller=root/'.claude/scripts/factory-intake.py'
        stable={key:value for key,value in config.items() if key not in {'private_root','runtime_database','implementation_roots','intake_config'}}
        policy={'schema_version':1,'enabled':True,'mode':'hosted-slack-capture-v1','repository':'org/repo','team_id':'T1','destination':'C1','stream':hashlib.sha256(hosted.canonical(['org/repo','C1','main']).encode()).hexdigest(),'feedback_config_sha256':hashlib.sha256(hosted.canonical(stable).encode()).hexdigest(),'controller_sha256':hashlib.sha256(controller.read_bytes()).hexdigest()}
        policy_path=private/'intake.json';policy_path.write_text(json.dumps(policy));policy_path.chmod(0o600);config['intake_config']=str(policy_path)
        ts=str(int(now.timestamp())-10)+'.000001'
        message={'type':'message','user':'U1','ts':ts,'text':'factory feedback #1 enhancement: add login'}

        # AC-2 / AC-9: immutable observed source revisions, exact retries and one serialized current head.
        client.input=[message];first=m.run(config,api,client,now)
        def records():
            with sqlite3.connect(config['runtime_database']) as db:
                return db.execute('SELECT id,source_key,document,revision,status FROM intake_requests ORDER BY source_key').fetchall()
        original=records()[0];original_document=json.loads(original[2])
        edit_ts=str(int(now.timestamp())-5)+'.000001'
        edited=dict(message,text='factory feedback #1 enhancement: add secure login',edited={'user':'U1','ts':edit_ts})
        client.input=[edited];second=m.run(config,api,client,now)
        rows=records();new=[row for row in rows if row[0]!=original[0]][0];document=json.loads(new[2])
        assert document['parent_request']==original[0], 'authenticated Slack edit did not link its immutable previous request'
        assert document['source_revision']==edit_ts and document['submission_key']==original_document['submission_key']+':edit:'+edit_ts
        assert next(row for row in rows if row[0]==original[0])[2:4]==original[2:4], 'edit overwrote original request bytes'
        with sqlite3.connect(config['runtime_database']) as db:
            assert db.execute('SELECT request_id,source_revision FROM intake_slack_heads').fetchall()==[(new[0],edit_ts)]
            assert db.execute('SELECT parent_request,kind FROM intake_slack_revisions WHERE request_id=?',(new[0],)).fetchone()==(original[0],'source_edit')
            assert db.execute('SELECT status FROM intake_requests WHERE id=?',(original[0],)).fetchone()[0]=='superseded'
        # Actual competing authenticated deliveries and module restart preserve one record/event per revision.
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=4) as pool:assert list(pool.map(lambda _:m.run(config,api,client,now),range(8)))==[second]*8
        restart_spec=importlib.util.spec_from_file_location('restart',path);restart=importlib.util.module_from_spec(restart_spec);restart_spec.loader.exec_module(restart)
        assert restart.run(config,api,client,now)==second
        assert records()==rows
        with sqlite3.connect(config['runtime_database']) as db:
            assert db.execute('SELECT COUNT(*) FROM intake_events').fetchone()[0]==2
            assert db.execute('SELECT COUNT(*) FROM factory_feedback').fetchone()[0]==2
            assert not db.execute("SELECT name FROM sqlite_master WHERE name IN ('intake_actions','intake_proposals')").fetchall()
        # An observed historical retry returns its prior feedback identity without restoring a current decision.
        client.input=[message];assert m.run(config,api,client,now)==first
        with sqlite3.connect(config['runtime_database']) as db:
            assert db.execute('SELECT request_id FROM intake_slack_heads').fetchall()==[(new[0],)]
            assert db.execute('SELECT status FROM intake_requests WHERE id=?',(original[0],)).fetchone()[0]=='superseded'
        client.input=[dict(edited,text='factory feedback #1 enhancement: conflicting bytes')];rejects(lambda:m.run(config,api,client,now));assert records()==rows
        # Full batch rollback includes prior fresh feedback when a later authenticated actor breaks source lineage.
        fresh=dict(message,ts=str(int(now.timestamp())-8)+'.000002')
        foreign=dict(edited,user='U2',edited={'user':'U2','ts':str(int(now.timestamp())-3)+'.000001'})
        client.input=[fresh,foreign];rejects(lambda:m.run(config,api,client,now));assert records()==rows
        with sqlite3.connect(config['runtime_database']) as db:
            assert db.execute('SELECT COUNT(*) FROM factory_feedback').fetchone()[0]==2
            assert db.execute('SELECT COUNT(*) FROM feedback_events').fetchone()[0]==2
        # First observed edited source never fabricates unavailable original bytes.
        unseen=dict(message,ts=str(int(now.timestamp())-9)+'.000003',edited={'user':'U1','ts':str(int(now.timestamp())-4)+'.000003'})
        client.input=[unseen];m.run(config,api,client,now)
        with sqlite3.connect(config['runtime_database']) as db:
            observed=db.execute('SELECT id,document FROM intake_requests WHERE source_key=?',(f"slack:T1/C1/{unseen['ts']}:edit:{unseen['edited']['ts']}",)).fetchone()
            assert json.loads(observed[1])['parent_request'] is None
            assert db.execute('SELECT parent_request,kind FROM intake_slack_revisions WHERE request_id=?',(observed[0],)).fetchone()==(None,'previous_unobserved')
            assert db.execute('SELECT COUNT(*) FROM intake_requests').fetchone()[0]==3
        # Distinct identical human messages remain separate identities.
        client.input=[fresh];m.run(config,api,client,now);assert len(records())==4
        # AC-2: pre-lineage capture-only records gain observed provenance without invalidating their current request.
        upgrade_config=dict(config,runtime_database=str(private/'upgrade.sqlite'))
        client.input=[message];m.run(upgrade_config,api,client,now)
        with sqlite3.connect(upgrade_config['runtime_database']) as db:
            upgrade_before=db.execute('SELECT id,document,revision,status FROM intake_requests').fetchone()
            db.execute('ALTER TABLE intake_slack_heads RENAME TO previous_heads')
            db.execute('ALTER TABLE intake_slack_revisions RENAME TO previous_revisions')
        m.run(upgrade_config,api,client,now)
        with sqlite3.connect(upgrade_config['runtime_database']) as db:
            assert db.execute('SELECT id,document,revision,status FROM intake_requests').fetchone()==upgrade_before, 'existing current Slack request lost its disposition during lineage upgrade'
        assert before==(api.head,api.writes,client.posts)
        print('AC-2/AC-9: actual authenticated edits, concurrent retries, restart, immutable lineage, missing-prior provenance and atomic actor-conflict rollback passed')

PYTEST
