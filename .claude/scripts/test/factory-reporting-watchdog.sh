#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import copy,hashlib,importlib.util,json,sys,tempfile
from datetime import datetime,timedelta,timezone
from pathlib import Path
from unittest.mock import patch
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-reporting-watchdog.py'
assert path.exists(), 'hosted reporting has no external read-only watchdog probe'
spec=importlib.util.spec_from_file_location('watchdog',path);w=importlib.util.module_from_spec(spec);spec.loader.exec_module(w)
def rejects(fn):
    try:fn()
    except (ValueError,RuntimeError,KeyError):return
    raise AssertionError('unverifiable reporting health accepted')
fixture=(root/'.claude/scripts/test/factory-hosted-digest.sh').read_text()
namespace={};exec(fixture.split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory() as tmp:',1)[0],namespace)
hosted=namespace['m'];config=copy.deepcopy(namespace['config']);config['state_repository']='org/repo';config['watchdog_grace_minutes']=60
class ReadOnlyAPI:
    repo='org/repo'
    def __init__(self,api):self.api=api;self.reads=0
    def request(self,path,method='GET',payload=None):
        assert method=='GET' and payload is None;self.reads+=1;return self.api.request(path,method,payload)
class Client:
    def __init__(self):self.message=None;self.posts=0;self.hidden=False;self.wrong=False
    def call(self,method,body):
        if method=='auth.test':return {'team_id':'T1','bot_id':'B1'}
        if method=='chat.postMessage':
            self.posts+=1;self.message={'bot_id':'B1','text':body['text'],'metadata':body['metadata'],'ts':'100.000001'}
            return {'channel':'C1','message':self.message}
        assert method=='conversations.history'
        message=copy.deepcopy(self.message)
        if message and self.wrong:message['text']+='altered'
        return {'messages':[] if self.hidden or message is None else [message]}
with tempfile.TemporaryDirectory() as tmp:
    api=namespace['GitAPI']();client=Client();now=datetime(2026,10,4,22,tzinfo=timezone.utc)
    assert hosted.run(config,namespace['ReportAPI'](),api,client,Path(tmp)/'report',now)['status']=='delivered'
    before=(api.head,api.writes,client.posts);reader=ReadOnlyAPI(api)
    health=w.inspect(config,reader,client,now)
    assert health['status']=='current' and health['latest_receipt_verified'] is True and health['missed_delivery'] is False
    assert before==(api.head,api.writes,client.posts) and reader.reads>0
    # The same probe verifies file receipts using the actual oversized adapter.
    attachment_fixture=(root/'.claude/scripts/test/factory-slack-attachment.sh').read_text()
    attachment_namespace={};exec(attachment_fixture.split("<<'PYTEST'\n",1)[1].split('\nwith tempfile.TemporaryDirectory() as tmp:',1)[0],attachment_namespace)
    file_state=namespace['GitAPI']();file_client=attachment_namespace['Client']()
    file_config=dict(config,attachments_enabled=True)
    assert hosted.run(file_config,attachment_namespace['LargeReport'](),file_state,file_client,Path(tmp)/'file-report',now)['status']=='delivered'
    file_before=(file_state.head,file_state.writes,file_client.posts,file_client.allocations)
    assert w.inspect(file_config,ReadOnlyAPI(file_state),file_client,now)['latest_receipt_verified'] is True
    assert file_before==(file_state.head,file_state.writes,file_client.posts,file_client.allocations)
    print('AC-1: external probe verifies protected checkpoints and text/file receipts without writes passed')
    target=w.state.digest.instant(w.state.slack.due(now+timedelta(days=1)))
    assert w.inspect(config,reader,client,target+timedelta(minutes=59))['status']=='grace'
    missing=w.inspect(config,reader,client,target+timedelta(minutes=60));assert missing['status']=='missed' and missing['missed_delivery'] is True
    assert before==(api.head,api.writes,client.posts)
    for moment in (datetime(2026,10,3,20,59,tzinfo=timezone.utc),datetime(2026,10,3,21,tzinfo=timezone.utc)):
        expected=w.state.slack.due(moment);assert expected in ('2026-10-02T22:00:00+00:00','2026-10-03T21:00:00+00:00')
    print('AC-2: precise due/grace boundary, outage detection and Sydney DST cutoffs passed')
    client.hidden=True;rejects(lambda:w.inspect(config,reader,client,now));client.hidden=False
    client.wrong=True;rejects(lambda:w.inspect(config,reader,client,now));client.wrong=False
    api.protected=False;rejects(lambda:w.inspect(config,reader,client,now));api.protected=True
    api.bypass=True;rejects(lambda:w.inspect(config,reader,client,now));api.bypass=False
    rejects(lambda:w.inspect(dict(config,enabled=False),reader,client,now))
    rejects(lambda:w.inspect(dict(config,watchdog_grace_minutes=True),reader,client,now))
    rejects(lambda:w.inspect(config,reader,client,now.replace(tzinfo=None)))
    bad=copy.deepcopy(config);bad['state_repository']='other/repo';rejects(lambda:w.inspect(bad,reader,client,now))
    empty=namespace['GitAPI']();rejects(lambda:w.inspect(config,ReadOnlyAPI(empty),client,now))
    assert before==(api.head,api.writes,client.posts)
    print('AC-3: lost history, changed content, protection, clock/config and missing checkpoint negatives passed')
    encoded=json.dumps(health);assert 'payload' not in encoded and 'receipt' not in health and 'text' not in encoded
    assert set(health)=={'schema_version','repository','checkpoint_sha','status','missed_delivery','expected_cutoff','delivered_cutoff','pending_batches','latest_receipt_verified'}
    class Response:
        status=200;body=b'OK'
        def __enter__(self):return self
        def __exit__(self,*args):pass
        def read(self,limit):assert limit==1025;return self.body
    class Opener:
        def __init__(self):self.calls=[]
        def open(self,request,timeout):self.calls.append(request);assert timeout==15;return Response()
    opener=Opener();url='https://hc-ping.com/12345678-1234-1234-1234-123456789012'
    w.heartbeat(url,health,opener);assert len(opener.calls)==1 and opener.calls[0].data==b'' and opener.calls[0].get_method()=='POST'
    rejects(lambda:w.heartbeat(url,missing,opener))
    rejects(lambda:w.heartbeat(url,dict(health,latest_receipt_verified=False),opener))
    for bad in ('http://hc-ping.com/12345678-1234-1234-1234-123456789012','https://evil.example/12345678-1234-1234-1234-123456789012',url+'/fail',url+'?create=1',url+'#fragment',url.replace('hc-ping.com','user@hc-ping.com')):
        rejects(lambda:w.heartbeat(bad,health,opener))
    Response.body=b'Unexpected';rejects(lambda:w.heartbeat(url,health,opener))
    assert w.state.slack.NoRedirect().redirect_request(None,None,None,None,None,None) is None
    print('AC-4: non-sensitive status, current-only empty-body heartbeat and strict external endpoint passed')
PYTEST
