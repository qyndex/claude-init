#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
if [[ "${1:-authenticated}" == phase2 ]]; then
  # AC-1/AC-2/AC-5/AC-6/AC-9/AC-10: assembled offline entry and regression inventory.
  for selector in hosted-journey authenticated edits-replay publication checkpoint checkpoint-failure; do
    printf 'phase2 selector: %s\n' "$selector"
    bash "$0" "$selector"
  done
  for suite in factory-legacy-feedback factory-slack-feedback factory-encrypted-feedback factory-hosted-feedback; do
    printf 'phase2 regression: %s\n' "$suite"
    bash "$ROOT/.claude/scripts/test/$suite.sh"
  done
  printf 'phase2 complete: 6 intake selectors, 4 feedback regressions\n'
  exit 0
fi
case "${1:-authenticated}" in authenticated|edits-replay|publication|checkpoint|checkpoint-failure|hosted-journey) ;; *) exit 2 ;; esac
python3 - "$ROOT" "${1:-authenticated}" <<'PYTEST'
import copy,importlib.util,json,os,sqlite3,sys,tempfile
from pathlib import Path
from datetime import datetime,timedelta,timezone
import runpy
runpy.run_path(str(Path(sys.argv[1])/'.claude/scripts/test/intake-private-diagnostics.py'))['install_requested']('slack')
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-slack-feedback.py';assert path.exists(),'authenticated private Slack feedback adapter is absent'
spec=importlib.util.spec_from_file_location('ingress',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
fixture=(root/'.claude/scripts/test/factory-hosted-digest.sh').read_text();ns={};exec(fixture.split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory() as tmp:',1)[0],ns)
hosted=ns['m']
class API(ns['GitAPI']):
    def __init__(self):super().__init__();self.forbid_writes=False;self.payloads=[]
    def request(self,path,method='GET',payload=None):
        if payload is not None:self.payloads.append(copy.deepcopy(payload))
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
        api.forbid_writes=sys.argv[2] not in {'checkpoint','checkpoint-failure','hosted-journey'};before=(api.head,api.writes,client.posts)
        if sys.argv[2] in {'checkpoint','checkpoint-failure','hosted-journey'}:config.update(feedback_key_id='key-v1',feedback_bootstrap_sha=api.head)
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
        api.forbid_writes=sys.argv[2] not in {'checkpoint','checkpoint-failure','hosted-journey'};before=(api.head,api.writes,client.posts)
        if sys.argv[2] in {'checkpoint','checkpoint-failure','hosted-journey'}:config.update(feedback_key_id='key-v1',feedback_bootstrap_sha=api.head)
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

elif sys.argv[2] in {'publication','checkpoint','checkpoint-failure','hosted-journey'}:

    # AC-5 / AC-6 / AC-9: actual bounded primary tool-free Scout and guarded private SQLite proposals.
    import hashlib,threading,time
    from concurrent.futures import ThreadPoolExecutor
    with tempfile.TemporaryDirectory() as tmp:
        private=Path(tmp).resolve();private.chmod(0o700);now=datetime(2026,10,4,22,tzinfo=timezone.utc)
        config=dict(ns['config'],feedback_enabled=True,state_repository='org/repo',private_root=str(private),runtime_database=str(private/'runtime.sqlite'),operators=['U1'],feedback_start='2026-10-04T00:00:00Z',implementation_roots=[str(root)])
        api=API();client=Client();assert hosted.run(config,ns['ReportAPI'](),api,client,private/'initial-report',now)['status']=='delivered'
        api.forbid_writes=sys.argv[2] not in {'checkpoint','checkpoint-failure','hosted-journey'};before=(api.head,api.writes,client.posts)
        if sys.argv[2] in {'checkpoint','checkpoint-failure','hosted-journey'}:config.update(feedback_key_id='key-v1',feedback_bootstrap_sha=api.head)
        def module(name,path):
            spec=importlib.util.spec_from_file_location(name,path);result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result
        routing=module('publication_routing',root/'.claude/scripts/factory-routing.py');core=module('publication_core',root/'.claude/scripts/factory-intake.py')
        def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
        binary=private/'native';binary.write_text(r'''#!__PYTHON__
import json,os,sys,time,sqlite3
from pathlib import Path
assert sys.argv[1:]==['--print','--model','fixture-model','--output-format','json','--tools','','--disallowedTools','mcp__*','--strict-mcp-config','--mcp-config',str(Path(__file__).with_name('mcp.json')),'--setting-sources','','--settings',str(Path(__file__).with_name('settings.json')),'--no-session-persistence']
assert set(os.environ)<={'PATH','LANG','LC_ALL','HOME','CLAUDE_CONFIG_DIR','TMPDIR','CLAUDE_CODE_OAUTH_TOKEN','__CF_USER_TEXT_ENCODING'}
assert os.environ['CLAUDE_CODE_OAUTH_TOKEN']=='fixture-planning' and Path.cwd()==Path(os.environ['HOME'])
assert not list(Path.cwd().iterdir())
context=json.loads(sys.stdin.read().split('\nCONTEXT_JSON\n',1)[1]);assert set(context)=={'schema_version','request','sources','approved_evidence'}
assert context['approved_evidence']==[] and context['sources'];assert 'delivery_token' not in context['request']
with sqlite3.connect(Path(__file__).with_name('runtime.sqlite'),timeout=.1) as db:db.execute('BEGIN IMMEDIATE');db.rollback()
mode=context['request']['text'].split(': ',1)[1]
if mode=='checkpoint':assert Path(__file__).with_name('durable-running').exists(), 'Scout ran before encrypted reservation committed'
counter=Path(__file__).with_name('count');counter.write_text(str(int(counter.read_text())+1) if counter.exists() else '1')
if mode in {'slow','edit-race'}:Path(__file__).with_name('spawned').write_text('ready');time.sleep(.5)
if mode=='timeout':time.sleep(5)
assessment={'schema_version':1,'disposition':'new_feature','intents':[{'kind':'new_feature','summary':'Proposed login','scope':['src/login.py']}],'rationale':'new request requires human approval','evidence':[],'uncertainty':'none','spec':None,'plan':None,'task':None,'next_action':'draft','blocked_reason':None}
result={'type':'result','subtype':'success','is_error':False,'modelUsage':{'fixture-model':{'inputTokens':1,'outputTokens':1}},'result':json.dumps(assessment)}
if mode=='wrong-model':result['modelUsage']={'foreign':{}}
if mode=='quota':result.update(subtype='error_during_execution',is_error=True)
if mode=='invalid':result['result']='not-json'
if mode=='invent-approval':assessment.update(spec='specs/active/001-login.md',plan='plans/active/001-login.md',task='T-1');result['result']=json.dumps(assessment)
if mode=='clarify':assessment.update(disposition='clarify',next_action='question',intents=[{'kind':'clarify','summary':'Which login provider?','scope':[]}],uncertainty='missing_context');result['result']=json.dumps(assessment)
print(json.dumps(result))
'''.replace('__PYTHON__',str(Path(sys.executable).resolve())));binary.chmod(0o700)
        settings=private/'settings.json';settings.write_text('{}');settings.chmod(0o600)
        mcp=private/'mcp.json';mcp.write_text('{"mcpServers":{}}');mcp.chmod(0o600)
        proof=private/'observation.json';caps=['foreground','model-selection','structured-output','tool-free','config-isolation','hook-failure-block'];proof.write_text(json.dumps({'schema_version':1,'runtime':'primary','model':'fixture-model','executable_sha256':sha(binary),'version':'2.1.295','capabilities':caps}));proof.chmod(0o600)
        assessment={'argv':[str(binary),'--print','--model','{model}','--output-format','json','--tools','','--disallowedTools','mcp__*','--strict-mcp-config','--mcp-config',str(mcp),'--setting-sources','','--settings',str(settings),'--no-session-persistence'],'trusted_files':{str(item):sha(item) for item in [binary,settings,mcp,proof]},'version':'2.1.295','capabilities':caps,'observation':{'path':str(proof),'sha256':sha(proof)}}
        native={'kind':'claude-cli','model':'fixture-model','billing':'subscription','location':'local','allowed_model_usage':['fixture-model'],'command':[str(binary),'--safe-mode','--model','{model}','--output-format','json','--print'],'probe':{'argv':[str(binary),'--version'],'trusted_files':{str(binary):sha(binary)},'timeout':5}}
        checks={'kind':'command','model':None,'billing':'unknown','location':'actions','allowed_model_usage':[],'command':[str(binary)],'probe':{'argv':[str(binary)],'trusted_files':{str(binary):sha(binary)},'timeout':5}}
        profile={'schema_version':1,'enabled':True,'repository':'org/repo','source_roots':['src'],'stacks':{'python':{'tools':[str(binary)],'acceptance':[str(binary),'test']}},'runtimes':{'primary':dict(native,assessment=assessment),'review':dict(native,location='actions',command=native['command']+['--no-session-persistence']),'checks':checks},'roles':{role:{'primary':name,'fallbacks':[],'capabilities':sorted(routing.FLOORS[role])} for role,name in [('planning','primary'),('implementation','primary'),('review','review'),('verification','checks'),('security','checks')]}}
        profile_path=private/'profile.json';profile_path.write_text(json.dumps(profile));profile_path.chmod(0o600)
        # Independently normalize only explicitly pinned artifact locators; every remaining profile field stays bound.
        aliases={str(item):'sha256:'+sha(item) for item in [binary,settings,mcp,proof]}
        def normalize(value):
            if isinstance(value,dict):return {aliases.get(key,key):normalize(item) for key,item in value.items()}
            if isinstance(value,list):return [normalize(item) for item in value]
            return aliases.get(value,value) if isinstance(value,str) else value
        semantic_hash=hashlib.sha256(hosted.canonical(normalize(profile)).encode()).hexdigest()
        config['assessment_profile']=str(profile_path)
        stable={key:value for key,value in config.items() if key not in {'private_root','runtime_database','implementation_roots','intake_config','assessment_profile'}}
        closure=['factory-intake.py','factory-intake-scout.py','factory-routing.py','factory-bounded-process.py','factory-feedback.py']
        policy={'schema_version':1,'enabled':True,'mode':'hosted-slack-capture-v1','repository':'org/repo','team_id':'T1','destination':'C1','stream':hashlib.sha256(hosted.canonical(['org/repo','C1','main']).encode()).hexdigest(),'feedback_config_sha256':hashlib.sha256(hosted.canonical(stable).encode()).hexdigest(),'controller_sha256':sha(root/'.claude/scripts/factory-intake.py'),'assessment':{'enabled':True,'dataflow':'private-scout-v1','profile_sha256':semantic_hash,'trusted_files':{name:sha(root/'.claude/scripts'/name) for name in closure},'limits':{'request_chars':20000,'context_bytes':500000,'output_bytes':65536,'assessment_seconds':3}}}
        policy_path=private/'intake.json';policy_path.write_text(json.dumps(policy));policy_path.chmod(0o600);config['intake_config']=str(policy_path)
        os.environ['FACTORY_PLANNING_CLAUDE_OAUTH_TOKEN']='fixture-planning'
        ts=str(int(now.timestamp())-10)+'.000001'
        def message(mode,stamp=ts):return {'type':'message','user':'U1','ts':stamp,'text':'factory feedback #1 enhancement: '+mode}
        if sys.argv[2] in {'checkpoint','checkpoint-failure','hosted-journey'}:
            # AC-9: real hosted restore, AES-GCM ciphertext and pre-provider durable intent.
            encrypted=module('checkpoint_hosted',root/'.claude/scripts/factory-hosted-feedback.py');secret=os.urandom(32)
            import contextlib,io
            journey_stdout=io.StringIO();journey_stderr=io.StringIO()
            def run_encrypted(*args,**kwargs):
                if sys.argv[2]!='hosted-journey':return encrypted.run(*args,**kwargs)
                with contextlib.redirect_stdout(journey_stdout),contextlib.redirect_stderr(journey_stderr):
                    return encrypted.run(*args,**kwargs)
            # AC-5/AC-9: restored holders retain every declared candidate exclusion.
            import shutil
            candidate=private/'additional-candidate';candidate.mkdir(mode=0o700)
            for artifact in [binary,settings,mcp,proof]:shutil.copy2(artifact,candidate/artifact.name)
            hostile_profile=private/'candidate-profile.json'
            hostile_profile.write_text(profile_path.read_text().replace(str(private),str(candidate)));hostile_profile.chmod(0o600)
            bad_config=dict(config,implementation_roots=[str(root),str(candidate)],assessment_profile=str(hostile_profile))
            bad_client=copy.deepcopy(client);bad_client.input=[message('login')]
            run_encrypted(bad_config,copy.deepcopy(api),bad_client,secret,now)
            assert not (candidate/'count').exists(), 'hosted restore dropped an additional candidate root and launched its executable'
            cryptobinding=encrypted.crypto.context('org/repo','C1','main','key-v1')
            report_before=hosted.GitState(api,config['state_branch'],policy['stream'],config['bootstrap_sha']).bytes
            original_request=api.request;crash=[False];seen=[]
            def snapshot():
                checkpoint=hosted.GitState(api,config['state_branch'],cryptobinding['stream'],config['feedback_bootstrap_sha'],bootstrap_existing=True)
                raw=encrypted.crypto.unseal(checkpoint.bytes,secret,cryptobinding)
                check=private/'remote-inspection.sqlite';check.write_bytes(raw)
                with sqlite3.connect(check) as db:
                    tables={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                    requests=db.execute('SELECT id,source_key,document,revision,status,decision,assessment_count FROM intake_requests ORDER BY source_key').fetchall() if 'intake_requests' in tables else []
                    running=db.execute("SELECT request_id FROM intake_assessments WHERE status='running'").fetchall() if 'intake_assessments' in tables else []
                    proposals=db.execute('SELECT * FROM feedback_private_proposals').fetchall() if 'feedback_private_proposals' in tables else []
                return checkpoint,requests,running,proposals
            class RunnerDied(BaseException):pass
            def monitored(path,method='GET',payload=None):
                result=original_request(path,method,payload)
                if method=='PATCH':
                    checkpoint,requests,running,proposals=snapshot();seen.append((requests,running,proposals))
                    if running:
                        (private/'durable-running').write_text('confirmed encrypted reservation')
                        if crash[0]:raise RunnerDied()
                return result
            api.request=monitored
            client.input=[message('checkpoint')]
            first=run_encrypted(config,api,client,secret,now)
            assert first['captured']==1
            checkpoint,requests,running,proposals=snapshot();assert len(requests)==len(proposals)==1 and not running, 'hosted draft did not complete after durable Scout intent'
            assert (private/'count').read_text()=='1'
            # Unrecognized additive older-decoder state is retained byte-for-byte inside SQLite.
            with encrypted.crypto.private_database(checkpoint,secret,cryptobinding) as (_,database):
                with sqlite3.connect(database) as db:
                    db.execute('CREATE TABLE older_decoder_extension(value BLOB)')
                    db.execute('INSERT INTO older_decoder_extension VALUES(?)',(b'private older state',))
            assert requests[0][4]=='decided' and json.loads(requests[0][5])['next_action']=='draft'
            old=(requests,proposals);head=api.head;writes=api.writes
            assert run_encrypted(config,api,client,secret,now)['captured']==1
            assert (snapshot()[1],snapshot()[3])==old and api.head==head and api.writes==writes and (private/'count').read_text()=='1'
            assert any(running and not proposals for _,running,proposals in seen)
            if sys.argv[2]=='hosted-journey':
                # AC-2/AC-6/AC-9: authenticated edit after a fresh encrypted restore fences the old draft.
                import contextlib,io
                public_output=io.StringIO();public_errors=io.StringIO()
                original=requests[0];old_proposal=proposals[0]
                edit_ts=str(int(now.timestamp())-5)+'.000001'
                client.input=[dict(message('checkpoint'),text='factory feedback #1 enhancement: secure-login-private',edited={'user':'U1','ts':edit_ts})]
                with contextlib.redirect_stdout(public_output),contextlib.redirect_stderr(public_errors):
                    assert run_encrypted(config,api,client,secret,now)['captured']==1
                    _,edited,unresolved,drafts=snapshot()
                    assert len(edited)==len(drafts)==2 and not unresolved
                    prior=next(row for row in edited if row[0]==original[0]);current=next(row for row in edited if row[0]!=original[0])
                    assert prior[2:4]==original[2:4] and prior[4]=='superseded'
                    assert json.loads(current[2])['parent_request']==original[0] and json.loads(current[2])['source_revision']==edit_ts
                    assert current[4]=='decided' and all(row[6]==1 for row in edited) and (private/'count').read_text()=='2'
                    assert old_proposal in drafts and all(json.loads(row[2])['approval']=='pending' for row in drafts)
                    head,writes=api.head,api.writes
                    assert run_encrypted(config,api,client,secret,now)['captured']==1
                    assert api.head==head and api.writes==writes and snapshot()[1]==edited and snapshot()[3]==drafts and (private/'count').read_text()=='2'
                    with encrypted.crypto.private_database(snapshot()[0],secret,cryptobinding) as (_,database):
                        restored_config=dict(config,runtime_database=str(database))
                        adapter=core.HostedSlackIntake(restored_config,policy['stream'],policy,policy['controller_sha256'])
                        feedback=m.f.Feedback(database,'org/repo')
                        rejects(lambda:adapter.publish_proposal(feedback,original[0]))
                        with sqlite3.connect(database) as db:
                            assert db.execute('SELECT COUNT(*) FROM tasks').fetchone()[0]==0
                            assert db.execute('SELECT COUNT(*) FROM feedback_private_proposals').fetchone()[0]==2
                            assert set(row[0] for row in db.execute('SELECT status FROM factory_feedback'))=={'open'}
                assert api.head==head and api.writes==writes and client.posts==before[2]
                public=[*api.blobs.values(),json.dumps(api.payloads).encode(),journey_stdout.getvalue().encode(),journey_stderr.getvalue().encode(),public_output.getvalue().encode(),public_errors.getvalue().encode()]
                assert all(secret_text not in channel for channel in public for secret_text in [b'Proposed login',b'factory feedback',b'secure-login-private',b'new request requires human approval'])
                assert hosted.GitState(api,config['state_branch'],policy['stream'],config['bootstrap_sha']).bytes==report_before
                print('AC-1/AC-2/AC-5/AC-6/AC-9: actual authenticated encrypted hosted subprocess journey, restored retry, edited-source supersession, private pending drafts and old-publication rejection passed; public outputs withheld')
                sys.exit(0)
            crash[0]=True;client.input=[message('checkpoint',str(int(now.timestamp())-9)+'.000001')]
            try:run_encrypted(config,api,client,secret,now)
            except RunnerDied:pass
            else:raise AssertionError('runner death did not reach committed remote intent')
            assert len(snapshot()[2])==1 and (private/'count').read_text()=='1'
            crash[0]=False;run_encrypted(config,api,client,secret,now)
            assert len(snapshot()[2])==1 and len(snapshot()[3])==1 and (private/'count').read_text()=='1'
            assert hosted.GitState(api,config['state_branch'],policy['stream'],config['bootstrap_sha']).bytes==report_before
            assert all(b'Proposed login' not in blob and b'factory feedback' not in blob for blob in api.blobs.values())
            with encrypted.crypto.private_database(snapshot()[0],secret,cryptobinding) as (_,database):
                with sqlite3.connect(database) as db:assert db.execute('SELECT value FROM older_decoder_extension').fetchall()==[(b'private older state',)]
            assert client.posts==before[2]
            if sys.argv[2]=='checkpoint-failure':
                # AC-9/AC-10: incompatible future state cannot be consumed or overwritten by an older decoder.
                def fork_api(mutation=None):
                    other=copy.deepcopy(api);other.request=API.request.__get__(other,API)
                    checkpoint=hosted.GitState(other,config['state_branch'],cryptobinding['stream'],config['feedback_bootstrap_sha'],bootstrap_existing=True)
                    if mutation is not None:
                        database=private/'failure-injection.sqlite';database.write_bytes(encrypted.crypto.unseal(checkpoint.bytes,secret,cryptobinding))
                        with sqlite3.connect(database) as db:mutation(db)
                        checkpoint.checkpoint(encrypted.crypto.seal(database.read_bytes(),secret,cryptobinding))
                    return other
                def fresh_client(index=1):
                    result=copy.deepcopy(client);result.input=[message('login',str(int(now.timestamp())-6)+f'.00000{index}')];return result
                def fails(fn):
                    try:fn()
                    except Exception:return
                    raise AssertionError('incompatible hosted checkpoint accepted and written back')
                for mutation in [lambda db:db.execute("UPDATE intake_decision_bindings SET document=json_set(document,'$.selected',json('{}'))"),
                                 lambda db:db.execute("UPDATE intake_actions SET result='{}' WHERE status='completed'"),
                                 lambda db:db.execute('ALTER TABLE intake_requests ADD COLUMN future GENERATED ALWAYS AS (length(document)) VIRTUAL'),
                                 lambda db:db.execute('CREATE TABLE intake_future_protocol(secret TEXT)'),
                                 lambda db:db.execute('UPDATE intake_hosted_identity SET version=2'),
                                 lambda db:db.execute('ALTER TABLE intake_requests ADD COLUMN future TEXT'),
                                 lambda db:db.execute('DROP TABLE intake_hosted_identity'),
                                 lambda db:db.execute("UPDATE intake_requests SET decision=json_set(decision,'$.rationale','substituted') WHERE status='decided'")]:
                    other=fork_api(mutation);head=other.head;count=(private/'count').read_text()
                    fails(lambda:run_encrypted(config,other,fresh_client(),secret,now))
                    assert other.head==head and (private/'count').read_text()==count
                checked=[]
                original_ingress=encrypted.ingress.run
                for limit in ['MAX_DATABASE','MAX_ENVELOPE']:
                    for stage in [1,2]:
                        other=fork_api();head=other.head;before_count=int((private/'count').read_text());calls=[0]
                        def limited(*args,**kwargs):
                            original_barrier=kwargs['checkpoint_barrier']
                            def barrier():
                                calls[0]+=1
                                if calls[0]==stage:setattr(encrypted.crypto,limit,1)
                                return original_barrier()
                            return original_ingress(*args,**dict(kwargs,checkpoint_barrier=barrier))
                        saved=getattr(encrypted.crypto,limit);encrypted.ingress.run=limited
                        try:fails(lambda:run_encrypted(config,other,fresh_client(),secret,now))
                        finally:encrypted.ingress.run=original_ingress;setattr(encrypted.crypto,limit,saved)
                        assert int((private/'count').read_text())==before_count+(stage==2)
                        if stage==1:assert other.head==head
                        run_encrypted(config,other,copy.deepcopy(client) if stage==1 else fresh_client(),secret,now)
                        assert int((private/'count').read_text())==before_count+(stage==2), 'overflow recovery reassessed an unresolved intent'
                        checked.append(other)
                for fault in ['conflict','lost-ack']:
                    for stage in [1,2]:
                        other=fork_api();request=other.request;patches=[0];before_count=int((private/'count').read_text())
                        def faulting(path,method='GET',payload=None):
                            if method=='PATCH':
                                patches[0]+=1
                                if patches[0]==stage:
                                    if fault=='lost-ack':other.drop=True
                                    else:
                                        winner=hosted.GitState(other,config['state_branch'],cryptobinding['stream'],config['feedback_bootstrap_sha'],bootstrap_existing=True)
                                        winner.checkpoint(encrypted.crypto.seal(encrypted.crypto.unseal(winner.bytes,secret,cryptobinding),secret,cryptobinding))
                            return request(path,method,payload)
                        other.request=faulting
                        fails(lambda:run_encrypted(config,other,fresh_client(),secret,now))
                        assert int((private/'count').read_text())==before_count+(stage==2)
                        run_encrypted(config,other,fresh_client(),secret,now)
                        # A pre-intent CAS loser had no committed intent; only that exact case may start on a later fresh authoritative run.
                        expected=before_count+((stage==2) or fault=='conflict' and stage==1)
                        assert int((private/'count').read_text())==expected, 'uncertain checkpoint replay repeated Scout'
                        checked.append(other)
                assert all(b'SQLite format 3' not in blob and b'Proposed login' not in blob and b'factory feedback' not in blob for other in checked for blob in other.blobs.values())
                print('AC-9/AC-10: finite plaintext/envelope overflow, CAS conflicts and lost acknowledgements before/after Scout preserve encrypted authority and fence reassessment')
                print('AC-9/AC-10: incompatible version, namespace, shape, missing marker and substituted provenance reject without provider/writeback')
            print('AC-9: actual encrypted hosted intake roundtrip, durable pre-Scout intent, fresh retry identity/proposal preservation and crashed-runner fencing passed')
            sys.exit(0)
        client.input=[message('login')]
        try:result=m.run(config,api,client,now)
        except ValueError:result=None
        with sqlite3.connect(config['runtime_database']) as db:
            assert db.execute("SELECT name FROM sqlite_master WHERE name='feedback_private_proposals'").fetchone(), 'authenticated bounded Scout draft was not stored privately'
            proposals=db.execute('SELECT document FROM feedback_private_proposals').fetchall();assert len(proposals)==1
            proposal=json.loads(proposals[0][0]);assert proposal['status']=='draft' and proposal['approval']=='pending' and proposal['repository']=='org/repo'
            assert db.execute('SELECT COUNT(*) FROM tasks').fetchone()[0]==0
            assert db.execute('SELECT status FROM factory_feedback').fetchone()[0]=='open'
            assert db.execute('SELECT assessment_count FROM intake_requests').fetchone()[0]==1
        # AC-6: valid-shaped substituted decisions and provenance must not authorize publication.
        adapter=core.HostedSlackIntake(config,policy['stream'],policy,policy['controller_sha256'])
        with sqlite3.connect(config['runtime_database']) as db:
            db.row_factory=sqlite3.Row
            saved=db.execute('SELECT id,decision FROM intake_requests').fetchone();identity=saved['id']
            altered=json.loads(saved['decision']);altered['rationale']='different unassessed scope'
            db.execute('UPDATE intake_requests SET decision=? WHERE id=?',(hosted.canonical(altered),identity))
            rejects(lambda:adapter.proposal_material(db,identity))
            db.execute('UPDATE intake_requests SET decision=? WHERE id=?',(saved['decision'],identity))
            original=db.execute('SELECT result FROM intake_assessments WHERE request_id=?',(identity,)).fetchone()[0]
            for key,value in [('model','foreign-model'),('profile_sha256','0'*64),('assessment_sha256','0'*64)]:
                changed=json.loads(original);changed[key]=value
                db.execute('UPDATE intake_assessments SET result=? WHERE request_id=?',(hosted.canonical(changed),identity))
                rejects(lambda:adapter.proposal_material(db,identity))
            db.execute('UPDATE intake_assessments SET result=? WHERE request_id=?',(original,identity))
            assert adapter.proposal_material(db,identity)[0]['kind']=='proposal_publish'
        # AC-9: private restore relocates pinned artifacts without invalidating the same assessed draft.
        import shutil
        with tempfile.TemporaryDirectory() as restored_tmp:
            restored=Path(restored_tmp).resolve();restored.chmod(0o700)
            for artifact in [binary,settings,mcp,proof,policy_path]:shutil.copy2(artifact,restored/artifact.name)
            restored_profile=restored/profile_path.name
            restored_profile.write_text(profile_path.read_text().replace(str(private),str(restored)));restored_profile.chmod(0o600)
            with sqlite3.connect(config['runtime_database']) as source_db,sqlite3.connect(restored/'runtime.sqlite') as restored_db:source_db.backup(restored_db)
            (restored/'runtime.sqlite').chmod(0o600)
            moved=dict(config,private_root=str(restored),runtime_database=str(restored/'runtime.sqlite'),intake_config=str(restored/policy_path.name),assessment_profile=str(restored_profile))
            moved_adapter=core.HostedSlackIntake(moved,policy['stream'],policy,policy['controller_sha256'])
            feedback_module=module('relocated_feedback',root/'.claude/scripts/factory-feedback.py')
            assert moved_adapter.publish_proposal(feedback_module.Feedback(moved['runtime_database'],'org/repo'),identity)['status']=='draft'
            assert not (restored/'count').exists(), 'restore retry launched Scout again'
        count=(private/'count').read_text();assert count=='1'
        assert m.run(config,api,client,now)==result and (private/'count').read_text()==count
        for number,mode in enumerate(['wrong-model','quota','invalid','invent-approval','clarify'],1):
            client.input=[message(mode,str(int(now.timestamp())-9)+f'.00000{number}')];m.run(config,api,client,now)
            with sqlite3.connect(config['runtime_database']) as db:
                row=db.execute('SELECT status,decision FROM intake_requests WHERE source_key=?',(f"slack:T1/C1/{client.input[0]['ts']}",)).fetchone();decision=json.loads(row[1])
                assert decision['next_action']==('question' if mode=='clarify' else 'none')
                assert decision['spec'] is None and decision['task'] is None
                assert db.execute('SELECT COUNT(*) FROM feedback_private_proposals').fetchone()[0]==1
        # Actual duplicate contenders cannot start a second assessor or publish twice.
        client.input=[message('slow',str(int(now.timestamp())-8)+'.000001')]
        with ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(lambda _:m.run(config,api,client,now),range(8)))
        assert (private/'count').read_text()=='7'
        with sqlite3.connect(config['runtime_database']) as db:assert db.execute('SELECT COUNT(*) FROM feedback_private_proposals').fetchone()[0]==2
        # Source edit during the real subprocess invalidates its prior decision and prevents publication.
        (private/'spawned').unlink(missing_ok=True);racing=message('edit-race',str(int(now.timestamp())-7)+'.000001');client.input=[racing]
        with ThreadPoolExecutor(max_workers=2) as pool:
            future=pool.submit(m.run,config,api,client,now)
            deadline=time.monotonic()+3
            while not (private/'spawned').exists() and time.monotonic()<deadline:time.sleep(.01)
            assert (private/'spawned').exists();client.input=[dict(racing,text='factory feedback #1 enhancement: clarify',edited={'user':'U1','ts':str(int(now.timestamp())-2)+'.000001'})];m.run(config,api,client,now);future.result()
        with sqlite3.connect(config['runtime_database']) as db:
            old=db.execute('SELECT status FROM intake_requests WHERE source_key=?',(f"slack:T1/C1/{racing['ts']}",)).fetchone();assert old[0]=='superseded'
            assert db.execute('SELECT COUNT(*) FROM feedback_private_proposals').fetchone()[0]==2
        assert before==(api.head,api.writes,client.posts)
        public=hosted.GitState(api,config['state_branch'],policy['stream'],config['bootstrap_sha']).bytes
        assert b'Proposed login' not in public and b'factory feedback' not in public
        print('AC-5/AC-6/AC-9: actual bounded Scout, guarded current-source private proposal, usage/schema/quota failures, concurrent replay and edit races passed')

PYTEST
