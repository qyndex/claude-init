#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import copy,importlib.util,json,sys,tempfile
from datetime import datetime,timedelta,timezone
from pathlib import Path
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-reporting-alerts.py';assert path.exists(),'durable GitHub-only alerts are absent'
spec=importlib.util.spec_from_file_location('alerts',path);a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
fixture=(root/'.claude/scripts/test/factory-hosted-digest.sh').read_text();ns={};exec(fixture.split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory() as tmp:',1)[0],ns)
hosted=ns['m'];config=dict(ns['config'],monitor_enabled=True,state_repository='org/repo')
class Client:
    def __init__(self):self.messages=[];self.posts=0;self.drop=False;self.hide_alert=False;self.tamper=False
    def call(self,method,body):
        if method=='auth.test':return {'team_id':'T1','bot_id':'B1'}
        if method=='chat.postMessage':
            self.posts+=1;message={'bot_id':'B1','text':body['text'],'metadata':body['metadata'],'ts':str(100+self.posts)+'.000001'}
            self.messages.insert(0,message)
            if self.drop:raise ValueError('response lost')
            return {'channel':'C1','message':message}
        assert method=='conversations.history'
        if body.get('cursor')=='next':
            messages=copy.deepcopy(self.messages)
            if self.hide_alert:messages=[m for m in messages if m['metadata']['event_type']!='factory_reporting_alert_v1']
            if self.tamper:
                for m in messages:
                    if m['metadata']['event_type']=='factory_reporting_alert_v1':m['text']+='changed'
            return {'messages':messages}
        return {'messages':[],'has_more':True,'response_metadata':{'next_cursor':'next'}}
class API(ns['GitAPI']):
    def __init__(self):super().__init__();self.bad_run=False;self.attempt=1
    def request(self,path,method='GET',payload=None):
        if path.endswith('/actions/workflows/factory-hosted-digest.yml'):return {'id':9,'path':'.github/workflows/factory-hosted-digest.yml'}
        if '/actions/runs/' in path:
            return {'id':700,'run_attempt':self.attempt,'workflow_id':9,'repository':{'full_name':'org/repo'},'head_repository':{'full_name':'other/repo' if self.bad_run else 'org/repo'},'head_branch':'main','event':'workflow_dispatch','status':'completed','conclusion':'failure','created_at':'2026-10-04T22:00:00Z'}
        return super().request(path,method,payload)
def rejects(fn):
    try:fn()
    except (ValueError,KeyError,RuntimeError):return
    raise AssertionError('untrusted or uncertain alert accepted')
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp);api=API();client=Client();now=datetime(2026,10,4,22,tzinfo=timezone.utc)
    assert hosted.run(config,ns['ReportAPI'](),api,client,tmp/'first',now)['status']=='delivered'
    before=api.head;assert a.run(config,api,client,now)['notifications']==0 and api.head==before
    missing=now+timedelta(days=1,hours=1)
    assert a.run(config,api,client,missing)['notifications']==1;count=client.posts
    assert a.run(config,api,client,missing+timedelta(days=1))['notifications']==0 and client.posts==count
    assert hosted.run(config,ns['ReportAPI'](),api,client,tmp/'recovery',missing)['status']=='delivered'
    assert a.run(config,api,client,missing)['notifications']==1
    assert a.run(config,api,client,missing)['notifications']==0
    stream=a.state.hashlib.sha256(a.state.canonical(['org/repo','C1','main']).encode()).hexdigest()
    checkpoint=a.state.GitState(api,config['state_branch'],stream,config['bootstrap_sha'])
    doc=json.loads(checkpoint.bytes);assert [r['kind'] for r in doc['alerts']]==['overdue','recovery'] and all(r['status']=='confirmed' for r in doc['alerts'])
    assert len(doc['tables']['digest_batches'])==2
    print('AC-1: real hosted state proves due alert, prolonged-incident suppression, digest preservation and one verified recovery')
    client.drop=True;rejects(lambda:a.run(config,api,client,missing,drill_run=800));count=client.posts
    client.hide_alert=True;rejects(lambda:a.run(config,api,client,missing));assert client.posts==count
    client.hide_alert=False;client.drop=False;assert a.run(config,api,client,missing,drill_run=800)['notifications']==0 and client.posts==count
    assert a.run(config,api,client,missing)['notifications']==1
    assert a.run(config,api,client,missing+timedelta(minutes=5),drill_run=800)['notifications']==0
    for loss in ('before-intent','intent-ack','confirmation-ack'):
        other=API();remote=Client();assert hosted.run(config,ns['ReportAPI'](),other,remote,tmp/loss,now)['status']=='delivered'
        initial_posts=remote.posts
        if loss=='before-intent':other.fail=True
        elif loss=='intent-ack':other.drop=True
        else:
            original=remote.call
            def with_confirmation_loss(method,body):
                result=original(method,body)
                if method=='chat.postMessage':other.drop=True
                return result
            remote.call=with_confirmation_loss
        rejects(lambda:a.run(config,other,remote,now,drill_run=900))
        if loss!='confirmation-ack':assert remote.posts==initial_posts
        other.fail=False
        if loss=='intent-ack':rejects(lambda:a.run(config,other,remote,now,drill_run=900));assert remote.posts==initial_posts
        elif loss=='confirmation-ack':assert a.run(config,other,remote,now,drill_run=900)['notifications']==0 and remote.posts==initial_posts+1
        else:assert a.run(config,other,remote,now,drill_run=900)['notifications']==1
    print('AC-2: lost acknowledgement and fresh invocation reconcile durable intent; hidden history never resends and drill retry is idempotent')
    api.bad_run=True;before=(api.head,client.posts);rejects(lambda:a.run(config,api,client,missing,failed_run=700));assert before==(api.head,client.posts)
    api.bad_run=False;assert a.run(config,api,client,missing,failed_run=700)['notifications']==1
    assert a.run(config,api,client,missing,failed_run=700)['notifications']==0
    assert a.run(config,api,client,missing)['notifications']==1
    api.attempt=2;assert a.run(config,api,client,missing,failed_run=700)['notifications']==1
    assert a.run(config,api,client,missing)['notifications']==1
    rejects(lambda:a.run(dict(config,monitor_enabled=False),api,client,missing))
    rejects(lambda:a.run(dict(config,state_repository='other/repo'),api,client,missing))
    rejects(lambda:a.run(config,api,client,missing.replace(tzinfo=None)))
    print('AC-3: actual run provenance, default branch, disabled/foreign inputs and failure deduplication pass')
    checkpoint=a.state.GitState(api,config['state_branch'],stream,config['bootstrap_sha']);doc=json.loads(checkpoint.bytes)
    bad=copy.deepcopy(doc);bad['alerts'][0]['extra']='secret';rejects(lambda:a.state.validate(bad,'org/repo',stream))
    bad=copy.deepcopy(doc);bad['alerts'][0]['message_id']='invalid';rejects(lambda:a.state.validate(bad,'org/repo',stream))
    bad=copy.deepcopy(doc);bad['alerts'].append(copy.deepcopy(bad['alerts'][0]));rejects(lambda:a.state.validate(bad,'org/repo',stream))
    client.tamper=True;rejects(lambda:a.run(config,api,client,missing,drill_run=801));client.tamper=False
    workflow=(root/'.github/workflows/factory-reporting-alerts.yml').read_text();assert 'workflow_run:' in workflow and 'environment: factory-reporting' in workflow and 'FACTORY_REPORTING_MONITOR_ENABLED' in workflow and 'factory-reporting-${{ github.repository }}' in workflow and 'HEARTBEAT' not in workflow
    print('AC-4: typed journal rejects malformed receipts and duplicate rows; protected GitHub-only workflow needs no external monitor')
PYTEST
