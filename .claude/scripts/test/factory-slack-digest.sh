#!/usr/bin/env bash
set -euo pipefail
ROOT="${SLACK_DIGEST_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
import copy,hashlib,importlib.util,json,sys,tempfile,os,urllib.error
from datetime import datetime,timezone
assert (Path(sys.argv[1])/'.claude/scripts/factory-slack-digest.py').is_file(), 'Slack digest transport not implemented'
spec=importlib.util.spec_from_file_location('slack',Path(sys.argv[1])/'.claude/scripts/factory-slack-digest.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def reject(fn):
    try:fn()
    except (ValueError,RuntimeError):return
    raise AssertionError('unsafe Slack delivery accepted')
class Client:
    def __init__(self):self.messages=[];self.posts=0;self.drop=False;self.team='T1';self.pages=None
    def call(self,method,body):
        if method=='auth.test':return {'ok':True,'team_id':self.team,'bot_id':'B1'}
        if method=='chat.postMessage':
            assert body['mrkdwn'] is False and body['parse']=='none' and body['unfurl_links'] is False
            self.posts+=1
            message={'bot_id':'B1','ts':f'{self.posts}.00001','metadata':body['metadata'],'text':body['text']}
            self.messages.append(message)
            if self.drop:raise RuntimeError('response lost')
            return {'ok':True,'channel':body['channel'],'message':message}
        assert method=='conversations.history' and body['include_all_metadata'] is True
        if self.pages:return self.pages[1 if body.get('cursor') else 0]
        return {'ok':True,'messages':self.messages,'has_more':False,'response_metadata':{'next_cursor':''}}
class API:
    repo='org/repo'
    def request(self,path,**opts):return [[{'number':n,'title':'<@U1> & <!channel>','html_url':f'https://github.com/org/repo/pull/{n}',
        'merged_at':'2026-10-03T21:00:00Z','merge_commit_sha':'b'*40,'head':{'sha':'c'*40},'base':{'ref':'main','repo':{'full_name':self.repo}}} for n in range(1,62)]]
# Exercise the real HTTP envelope with an injected opener; no real credential/network.
os.environ['FACTORY_SLACK_BOT_TOKEN']='xoxb-fixture-not-a-secret'
http=m.SlackHTTP()
class Response:
    def __init__(self,blob):self.blob=blob
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def read(self,size):return self.blob
class Opener:
    def __init__(self,blob):self.blob=blob
    def open(self,request,timeout):
        assert request.full_url.startswith('https://slack.com/api/') and timeout==15
        return Response(self.blob)
http.opener=Opener(b'{"ok":true}');assert http.call('auth.test',{})['ok'] is True
http.opener=Opener(b'{"ok":false,"error":"invalid_auth"}');reject(lambda:http.call('auth.test',{}))
http.opener=Opener(b'not json');reject(lambda:http.call('auth.test',{}))
assert m.NoRedirect().redirect_request(None,None,None,None,None,None) is None
class QueryOpener(Opener):
    def open(self,request,timeout):
        from urllib.parse import urlparse,parse_qs
        assert request.get_method()=='GET'
        assert parse_qs(urlparse(request.full_url).query)['include_all_metadata']==['true']
        return super().open(request,timeout)
http.opener=QueryOpener(b'{"ok":true,"messages":[]}')
http.call('conversations.history',{'channel':'C1','include_all_metadata':True})
client=Client();m.preflight(client,'T1','C1');assert client.posts==0
client.team='T2';reject(lambda:m.preflight(client,'T1','C1'));assert client.posts==0
class NoHistory(Client):
    def call(self,method,body):
        if method=='conversations.history':raise ValueError('missing_scope')
        return super().call(method,body)
client=NoHistory();reject(lambda:m.preflight(client,'T1','C1'));assert client.posts==0
os.environ.pop('FACTORY_SLACK_BOT_TOKEN')
now=datetime(2026,10,4,22,tzinfo=timezone.utc)
assert m.due(datetime(2026,10,3,20,59,tzinfo=timezone.utc))=='2026-10-02T22:00:00+00:00'
assert m.due(datetime(2026,10,3,21,tzinfo=timezone.utc))=='2026-10-03T21:00:00+00:00'
with tempfile.TemporaryDirectory() as tmp:
    config={'enabled':True,'repository':'org/repo','destination':'C1','team_id':'T1','start':'2026-10-02T00:00:00Z','database':str(Path(tmp)/'db')}
    disabled=dict(config,enabled=False);reject(lambda:m.configured(disabled))
    client=Client();store=m.configured(config);before=store.cursor()
    assert m.watchdog(config,now)['missed_delivery'] is True
    client.drop=True;reject(lambda:m.run(config,API(),client,now));assert store.cursor()==before
    batch=store.prepare(API(),m.due(now));transport=m.Slack(client,'T1','C1',batch['key'],batch['payload'])
    text=transport.text;assert '<@' not in text and '<!channel>' not in text and '&lt;' in text
    assert all(f'#{n} ' in text for n in range(1,62))
    valid=copy.deepcopy(client.messages[0])
    client.pages=[{'messages':[],'response_metadata':{'next_cursor':'more'},'has_more':True},
                  {'messages':[valid],'response_metadata':{'next_cursor':''},'has_more':False}]
    assert transport.lookup(batch['key'])['receipt']['key']==batch['key']
    client.pages=None
    for field,value in [('text','changed'),('metadata',{'event_type':'factory_digest_v1','event_payload':{'key':batch['key'],'payload_sha256':'0'*64}})]:
        bad=copy.deepcopy(valid);bad[field]=value;client.messages=[bad];reject(lambda:transport.lookup(batch['key']))
    bad=copy.deepcopy(valid);bad['bot_id']='B2';client.messages=[bad];assert transport.lookup(batch['key'])['receipt'] is None
    client.messages=[];assert transport.lookup(batch['key'])=={'receipt':None,'authoritative_absence':False}
    reject(lambda:store.deliver(batch['key'],transport));assert client.posts==1 and store.cursor()==before
    client.messages=[valid,valid];reject(lambda:transport.lookup(batch['key']))
    client.pages=[{'messages':[valid],'has_more':True,'response_metadata':{}}]*2;reject(lambda:transport.lookup(batch['key']))
    client.pages=None;client.messages=[valid];client.drop=False
    result=m.run(config,API(),client,now);assert result['status']=='delivered' and client.posts==1
    assert m.watchdog(config,now)['missed_delivery'] is False
    assert m.run(config,API(),client,now)['status']=='not-due'
    client.team='T2';reject(lambda:m.Slack(client,'T1','C1',batch['key'],batch['payload']))
    oversized=json.loads(batch['payload']);oversized['merges']*=100
    reject(lambda:m.render(json.dumps(oversized)))
print('factory-slack-digest: sender/workspace binding, pagination, uncertainty, escaping, size limit, due time and watchdog passed')
PYTEST
