#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import importlib.util,json,os,sqlite3,sys,tempfile
from pathlib import Path
from datetime import datetime,timezone
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-hosted-feedback.py';assert path.exists(),'encrypted hosted intake absent'
spec=importlib.util.spec_from_file_location('feedback_hosted',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
fixture=(root/'.claude/scripts/test/factory-slack-feedback.sh').read_text();ns={};exec(fixture.split("<<'PYTEST'\n",1)[1].split('\nwith tempfile.TemporaryDirectory() as tmp:',1)[0],ns)
hosted=ns['hosted'];api=ns['API']();client=ns['Client']();now=datetime(2026,10,4,22,tzinfo=timezone.utc)
config=dict(ns['ns']['config'],feedback_enabled=True,state_repository='org/repo',operators=['U1'],feedback_start='2026-10-04T00:00:00Z',feedback_key_id='key-v1')
def reject(fn):
    try:fn()
    except Exception:return
    raise AssertionError('unsafe hosted feedback accepted')
secret=os.urandom(32)
with tempfile.TemporaryDirectory() as temporary:
    assert hosted.run(config,ns['ns']['ReportAPI'](),api,client,Path(temporary)/'report',now)['status']=='delivered'
config['feedback_bootstrap_sha']=api.head
report_stream=hosted.hashlib.sha256(hosted.canonical(['org/repo','C1','main']).encode()).hexdigest()
report_before=hosted.GitState(api,config['state_branch'],report_stream,config['bootstrap_sha']).bytes
binding=m.crypto.context('org/repo','C1','main','key-v1')
reject(lambda:hosted.GitState(api,config['state_branch'],binding['stream'],api.head))
reject(lambda:m.run(dict(config,feedback_bootstrap_sha='0'*40),api,client,secret,now))
client.input=[{'type':'message','user':'U1','ts':str(int(now.timestamp())-10)+'.000001','text':'factory feedback #1 defect: PRIVATE SIGNAL EXACT WORDS'}]
posts=client.posts
result=m.run(config,api,client,secret,now);assert result['captured']==1 and client.posts==posts
checkpoint=hosted.GitState(api,config['state_branch'],binding['stream'],config['feedback_bootstrap_sha'],bootstrap_existing=True)
assert b'PRIVATE SIGNAL' not in checkpoint.bytes
assert hosted.GitState(api,config['state_branch'],report_stream,config['bootstrap_sha']).bytes==report_before
with m.crypto.private_database(checkpoint,secret,binding) as (_,path):
    with sqlite3.connect(path) as db:
        assert json.loads(db.execute('SELECT document FROM factory_feedback').fetchone()[0])['text']==client.input[0]['text']
        assert db.execute('SELECT COUNT(*) FROM tasks').fetchone()[0]==0
print('AC-1: actual authenticated intake commits exact private feedback only as ciphertext while preserving the existing public reporting stream and separate approval gates')
writes=api.writes;assert m.run(config,api,client,secret,now)['captured']==1 and api.writes==writes
client.input=[dict(client.input[0],ts=str(int(now.timestamp())-5)+'.000001',text='factory feedback #1 enhancement: SECOND PRIVATE SIGNAL')]
api.drop=True;reject(lambda:m.run(config,api,client,secret,now));writes=api.writes
assert m.run(config,api,client,secret,now)['captured']==1 and api.writes==writes and client.posts==posts
print('AC-2: lost Git acknowledgement replays from actual authoritative encrypted checkpoint without duplicate feedback, Slack sends or checkpoint churn')
head=api.head
client.hide_report=True;reject(lambda:m.run(config,api,client,secret,now));client.hide_report=False
reject(lambda:m.run(config,api,client,os.urandom(32),now))
reject(lambda:m.run(dict(config,feedback_enabled=False),api,client,secret,now))
reject(lambda:m.run(dict(config,operators=[]),api,client,secret,now))
assert api.head==head and client.posts==posts
workflow=(root/'.github/workflows/factory-hosted-feedback.yml').read_text()
assert 'pull_request:' not in workflow and 'pull_request_target:' not in workflow and 'FACTORY_APP_PRIVATE_KEY' not in workflow
assert "vars.FACTORY_FEEDBACK_ENABLED == 'true'" in workflow and 'github.ref == format' in workflow
assert 'environment: factory-reporting' in workflow and 'persist-credentials: false' in workflow
assert 'group: factory-reporting-${{ github.repository }}' in workflow and 'cancel-in-progress: false' in workflow
assert 'upload-artifact' not in workflow and 'FACTORY_FEEDBACK_STATE_KEY: ${{ secrets.FACTORY_FEEDBACK_STATE_KEY }}' in workflow
print('AC-3: disabled intake, wrong keys, missing exact remote receipt and invalid allowlist fail without checkpointing partial or unauthenticated observations')
a=hosted.GitState(api,config['state_branch'],binding['stream'],config['feedback_bootstrap_sha'],bootstrap_existing=True)
b=hosted.GitState(api,config['state_branch'],binding['stream'],config['feedback_bootstrap_sha'],bootstrap_existing=True)
with m.crypto.private_database(a,secret,binding) as (_,path):
    with sqlite3.connect(path) as db:db.execute('CREATE TABLE race(value INTEGER)');db.execute('INSERT INTO race VALUES(1)')
try:
    with m.crypto.private_database(b,secret,binding) as (_,path):
        with sqlite3.connect(path) as db:db.execute('CREATE TABLE race(value INTEGER)');db.execute('INSERT INTO race VALUES(2)')
except RuntimeError:pass
else:raise AssertionError('stale encrypted writer overwrote authority')
assert hosted.GitState(api,config['state_branch'],report_stream,config['bootstrap_sha']).bytes==report_before
# A removed private stream must not reset using an old bootstrap approval.
api.trees[api.commits[api.head]['tree']['sha']]=[item for item in api.trees[api.commits[api.head]['tree']['sha']] if item['path']!=a.path]
reject(lambda:m.run(config,api,client,secret,now))
print('AC-4: actual Git compare-and-swap rejects stale encrypted writers; exact bootstrap is required and removed state never silently resets; public reporting state is preserved')
PYTEST
