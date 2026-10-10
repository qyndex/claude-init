#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import copy,hashlib,importlib.util,json,sys,tempfile
from pathlib import Path
from unittest.mock import patch
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-slack-attachment.py'
assert path.exists(), 'oversized digests have no verified attachment transport'
spec=importlib.util.spec_from_file_location('attachment',path);a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
def rejects(fn):
    try:fn()
    except (ValueError,KeyError):return
    raise AssertionError('untrusted file receipt accepted')
class Client:
    def __init__(self):
        self.bytes=None;self.filename=None;self.allocations=0;self.posts=0;self.hidden=False;self.drop=False;self.bad=None;self.messages=[]
    def call(self,method,body):
        if method=='auth.test':return {'team_id':'T1','bot_id':'B1','user_id':'U1'}
        if method=='files.getUploadURLExternal':
            self.allocations+=1;self.filename=body['filename'];self.length=body['length'];return {'file_id':'F1','upload_url':'https://files.slack.com/upload/v1/abc'}
        if method=='files.completeUploadExternal':
            assert body['channel_id']=='C1' and body['files']==[{'id':'F1','title':self.filename}]
            self.posts+=1;self.messages=[{'user':'U1','ts':'100.000001','files':[{'id':'F1','name':self.filename}]}]
            if self.drop:raise ValueError('completion response lost')
            return {'ok':True,'files':[{'id':'F1'}]}
        if method=='conversations.history':
            assert body['channel']=='C1'
            if self.hidden:return {'messages':[]}
            if body.get('cursor')=='next':return {'messages':copy.deepcopy(self.messages)}
            return {'messages':[],'response_metadata':{'next_cursor':'next'},'has_more':True}
        if method=='files.info':
            assert body=={'file':'F1'}
            file={'id':'F1','name':self.filename,'user':'U1','mode':'hosted','is_external':False,'size':len(self.bytes),'public_url_shared':False,
                  'shares':{'private':{'C1':[{'ts':'100.000001','team_id':'T1'}]}},'url_private_download':'https://files.slack.com/files-pri/T1-F1/digest.txt'}
            if self.bad:file.update(self.bad)
            return {'file':file}
        raise AssertionError(method)
    def transfer(self,url,data=None,**kwargs):
        if data is not None:
            assert url.startswith('https://files.slack.com/upload/') and len(data)==self.length;self.bytes=data;return b'OK'
        assert kwargs=={'team':'T1','identity':'F1'};return self.bytes
fixture=(root/'.claude/scripts/test/factory-hosted-digest.sh').read_text()
definitions=fixture.split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory() as tmp:',1)[0]
fixtures={};exec(definitions,fixtures)
hosted=fixtures['m'];config=copy.deepcopy(fixtures['config']);config['attachments_enabled']=True
from datetime import datetime,timezone
class LargeReport(fixtures['ReportAPI']):
    def request(self,*args,**kwargs):
        pr=super().request(*args,**kwargs)[0][0]
        return [[dict(pr,number=i,title='Feature '+str(i)+' '+('x'*150),html_url=f'https://github.com/org/repo/pull/{i}') for i in range(1,301)]]
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp);state=fixtures['GitAPI']();client=Client();now=datetime(2026,10,4,22,tzinfo=timezone.utc)
    result=hosted.run(config,LargeReport(),state,client,tmp/'first.sqlite',now)
    assert result['status']=='delivered' and client.posts==client.allocations==1
    text=client.bytes.decode();assert len(text)>35000 and '#300' in text and 'Merged PRs: 300' in text
    receipt=json.loads(result['receipt']['message_id']);assert receipt['slack_file_id']=='F1' and receipt['text_sha256']==hashlib.sha256(client.bytes).hexdigest()
    before=state.head;assert hosted.run(config,LargeReport(),state,client,tmp/'repeat.sqlite',now)['status']=='not-due' and state.head==before and client.posts==1
    print('AC-1: actual hosted oversized report, exact file bytes and unchanged repeat passed')
    payload=json.loads(hosted.GitState(state,config['state_branch'],hosted.hashlib.sha256(hosted.canonical(['org/repo','C1','main']).encode()).hexdigest()).bytes)['tables']['digest_batches'][0]['payload']
    key=result['receipt']['key'];transport=a.Attachment(client,'T1','C1',key,payload)
    for bad in ({'user':'U2'},{'name':'forged.txt'},{'size':1},{'public_url_shared':True},{'is_external':True},{'shares':{'private':{'C1':[{'ts':'100.000001','team_id':'T1'},{'ts':'101.000001','team_id':'T1'}]}}},{'shares':{'private':{'C2':[{'ts':'100.000001','team_id':'T1'}]}}}):
        client.bad=bad;rejects(lambda:transport.lookup(key))
    client.bad=None;original=client.bytes;client.bytes=original[:-1]+b'!';rejects(lambda:transport.lookup(key));client.bytes=original
    message=copy.deepcopy(client.messages);client.messages[0]['user']='U2';rejects(lambda:transport.lookup(key));client.messages=message+message;rejects(lambda:transport.lookup(key));client.messages=message
    print('AC-2: uploader, destination, privacy, identity, byte tampering and ambiguous share negatives passed')
    fresh=fixtures['GitAPI']();lost=Client();lost.drop=True
    rejects(lambda:hosted.run(config,LargeReport(),fresh,lost,tmp/'lost.sqlite',now));assert lost.posts==lost.allocations==1
    lost.hidden=True;rejects(lambda:hosted.run(config,LargeReport(),fresh,lost,tmp/'hidden.sqlite',now));assert lost.posts==1
    lost.hidden=False;lost.drop=False;assert hosted.run(config,LargeReport(),fresh,lost,tmp/'recovered.sqlite',now)['status']=='delivered'
    assert lost.posts==lost.allocations==1
    off=copy.deepcopy(config);off['attachments_enabled']=False
    disabled_state=fixtures['GitAPI']();disabled=Client();rejects(lambda:hosted.run(off,LargeReport(),disabled_state,disabled,tmp/'off.sqlite',now));assert disabled.allocations==0
    print('AC-3: completion loss, fresh-disk recovery, hidden history uncertainty and disabled default passed')
    # Exercise HTTP URL/header boundaries without external requests or credentials.
    class Response:
        status=200
        def __enter__(self):return self
        def __exit__(self,*args):pass
        raw=b'OK'
        def read(self,n):return self.raw
    class Opener:
        def __init__(self):self.requests=[]
        def open(self,request,timeout):self.requests.append(request);return Response()
    http=object.__new__(a.HTTP);http.token='fixture-only';http.opener=Opener()
    http.transfer('https://files.slack.com/upload/v1/abc',b'report')
    assert http.opener.requests[-1].get_header('Authorization') is None
    http.transfer('https://files.slack.com/files-pri/T1-F1/report.txt',team='T1',identity='F1')
    assert http.opener.requests[-1].get_header('Authorization')=='Bearer fixture-only'
    for url in ('https://evil.example/upload/v1/abc','http://files.slack.com/upload/v1/abc','https://files.slack.com.evil/upload/v1/abc','https://files.slack.com:443/upload/v1/abc','https://user@files.slack.com/upload/v1/abc','https://files.slack.com/upload/v1/abc#fragment'):
        rejects(lambda:http.transfer(url,b'report'))
    rejects(lambda:http.transfer('https://files.slack.com/files-pri/T2-F1/report.txt',team='T1',identity='F1'))
    rejects(lambda:http.transfer('https://files.slack.com/upload/v1/abc',b'x'*1000001))
    Response.raw=b'{"ok":true,"file":{}}'
    assert http.call('files.info',{'file':'F1'})['ok'] is True
    request=http.opener.requests[-1];assert request.get_method()=='GET' and 'file=F1' in request.full_url
    assert http.call('files.getUploadURLExternal',{'filename':'report.txt','length':6})['ok'] is True
    assert http.opener.requests[-1].get_method()=='POST'
    assert http.call('files.completeUploadExternal',{'files':[{'id':'F1'}]})['ok'] is True
    Response.raw=b'{"ok":false,"error":"fixture-private-token"}'
    try:http.call('files.info',{'file':'F1'})
    except ValueError as error:assert 'fixture-private-token' not in str(error)
    else:raise AssertionError('File API failure accepted')
    Response.raw=b'not json';rejects(lambda:http.call('files.info',{'file':'F1'}))
    Response.raw=b'{"ok":true,"ok":true}';rejects(lambda:http.call('files.info',{'file':'F1'}))
    assert a.slack.NoRedirect().redirect_request(None,None,None,None,None,None) is None
    rejects(lambda:a.slack.transport(client,dict(config,attachments_enabled='true'),{'key':key,'payload':payload}))
    print('AC-4: HTTPS host/path, token separation, API envelope/methods and strict bounds passed')
PYTEST
