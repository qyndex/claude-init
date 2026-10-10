#!/usr/bin/env bash
set -euo pipefail
ROOT="${HOSTED_DIGEST_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PYTEST'
from pathlib import Path
from datetime import datetime,timezone
import base64,copy,hashlib,importlib.util,json,sys,tempfile
from unittest.mock import patch
from types import SimpleNamespace
root=Path(sys.argv[1]);assert (root/'.claude/scripts/factory-git-state.py').is_file(), 'hosted durable reporting not implemented'
spec=importlib.util.spec_from_file_location('hosted',root/'.claude/scripts/factory-git-state.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def reject(fn):
    try:fn()
    except (ValueError,RuntimeError):return
    raise AssertionError('unsafe checkpoint accepted')
class GitAPI:
    repo='org/repo'
    def __init__(self):
        self.head='a'*40;self.trees={'b'*40:[]};self.commits={self.head:{'sha':self.head,'tree':{'sha':'b'*40},'parents':[]}};self.blobs={};self.messages=[];self.writes=0;self.fail=False;self.drop=False;self.protected=True;self.private=False;self.truncated=False;self.bypass=False
    def request(self,path,method='GET',payload=None):
        suffix='' if path=='repos/org/repo' else path.removeprefix('repos/org/repo/')
        if method=='GET':
            if suffix=='':return {'full_name':self.repo,'private':self.private,'archived':False,'default_branch':'main'}
            if suffix.startswith('rules/branches/'):return [{'type':t,'ruleset_id':7} for t in ('non_fast_forward','deletion')] if self.protected else []
            if suffix=='rulesets/7':return {'enforcement':'active','bypass_actors':[{'actor_id':1}] if self.bypass else []}
            if suffix=='git/ref/heads/factory-reporting-state':return {'ref':'refs/heads/factory-reporting-state','object':{'type':'commit','sha':self.head}}
            if suffix.startswith('git/commits/'):return copy.deepcopy(self.commits[suffix.split('/')[-1]])
            if suffix.startswith('git/trees/'):
                sha=suffix.split('/')[-1].split('?')[0];return {'sha':sha,'truncated':self.truncated,'tree':copy.deepcopy(self.trees[sha])}
            if suffix.startswith('git/blobs/'):
                sha=suffix.split('/')[-1];data=self.blobs[sha];return {'sha':sha,'size':len(data),'encoding':'base64','content':base64.b64encode(data).decode()}
        if self.fail:raise RuntimeError('checkpoint storage outage')
        if method=='POST' and suffix=='git/blobs':
            data=base64.b64decode(payload['content']);sha=m.git_hash(data);self.blobs[sha]=data;return {'sha':sha}
        if method=='POST' and suffix=='git/trees':
            entries=copy.deepcopy(self.trees[payload['base_tree']]);change=copy.deepcopy(payload['tree'][0]);change['size']=len(self.blobs[change['sha']]);entries=[e for e in entries if e['path']!=change['path']]+[change];sha=hashlib.sha1(m.canonical(entries).encode()).hexdigest();self.trees[sha]=entries;return {'sha':sha}
        if method=='POST' and suffix=='git/commits':
            self.messages.append(payload['message']);sha=hashlib.sha1(m.canonical(payload).encode()).hexdigest();result={'sha':sha,'tree':{'sha':payload['tree']},'parents':[{'sha':p} for p in payload['parents']]};self.commits[sha]=result;return copy.deepcopy(result)
        if method=='PATCH' and suffix=='git/refs/heads/factory-reporting-state':
            assert payload['force'] is False
            candidate=self.commits[payload['sha']]
            if payload['sha']!=self.head and [p['sha'] for p in candidate['parents']]!=[self.head]:raise RuntimeError('stale writer')
            self.head=payload['sha'];self.writes+=1
            if self.drop:self.drop=False;raise RuntimeError('checkpoint acknowledged remotely, response lost')
            return {'ref':'refs/heads/factory-reporting-state','object':{'sha':self.head}}
        raise AssertionError((path,method))
class ReportAPI:
    repo='org/repo'
    def get(self,path):return {'full_name':self.repo,'private':False,'default_branch':'main'}
    def request(self,*args,**kwargs):return [[{'number':1,'title':'Public change','html_url':'https://github.com/org/repo/pull/1','merged_at':'2026-10-02T00:00:00Z','merge_commit_sha':'c'*40,'head':{'sha':'d'*40},'base':{'ref':'main','repo':{'full_name':self.repo}}}]]
class Transport:
    def __init__(self):self.messages={};self.sends=0;self.drop=False
    def send(self,key,payload,destination):
        self.sends+=1;receipt={'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':destination,'message_id':str(self.sends)};self.messages[key]=receipt
        if self.drop:raise RuntimeError('Slack response lost')
        return receipt
    def lookup(self,key):return {'receipt':self.messages.get(key),'authoritative_absence':False}
config={'enabled':True,'repository':'org/repo','destination':'C1','team_id':'T1','branch':'main','start':'2026-10-01T00:00:00Z','state_branch':'factory-reporting-state','bootstrap_sha':'a'*40,'receipt_policy':{'repository':'org/repo','receipts':{'workflow_id':None,'trusted_revisions':{}}}}
stream=hashlib.sha256(m.canonical(['org/repo','C1','main']).encode()).hexdigest()
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp);api=GitAPI();remote=Transport()
    def store(name):return m.HostedDigest(tmp/name,config,m.GitState(api,config['state_branch'],stream,config['bootstrap_sha']))
    # AC-1: first bootstrap is exact; typed state excludes runtime/private tables.
    reject(lambda:m.GitState(api,'main',stream,api.head));reject(lambda:m.GitState(api,config['state_branch'],stream,'0'*40))
    api.protected=False;reject(lambda:m.GitState(api,config['state_branch'],stream,api.head));api.protected=True
    api.bypass=True;reject(lambda:m.GitState(api,config['state_branch'],stream,api.head));api.bypass=False
    api.truncated=True;reject(lambda:m.GitState(api,config['state_branch'],stream,api.head));api.truncated=False
    first=store('first');batch=first.prepare(ReportAPI(),'2026-10-03T00:00:00Z')
    with first.transaction() as db:db.execute('CREATE TABLE private_feedback(secret TEXT)');db.execute("INSERT INTO private_feedback VALUES('DO-NOT-PUBLISH')")
    state=m.GitState(api,config['state_branch'],stream,config['bootstrap_sha']);assert b'DO-NOT-PUBLISH' not in state.bytes and b'private_feedback' not in state.bytes
    entry=api.trees[api.commits[api.head]['tree']['sha']][0];original=api.blobs[entry['sha']];api.blobs[entry['sha']]=original+b'tampered';reject(lambda:m.GitState(api,config['state_branch'],stream,config['bootstrap_sha']));api.blobs[entry['sha']]=original
    exported=json.loads(state.bytes);assert set(exported['tables'])==set(m.TABLES)
    # AC-2: identical pending snapshots race; unique commit messages deny the second writer.
    a=store('a');b=store('b');a.deliver(batch['key'],remote);assert remote.sends==1
    reject(lambda:b.deliver(batch['key'],remote));assert remote.sends==1
    confirmed=json.loads(m.GitState(api,config['state_branch'],stream,config['bootstrap_sha']).bytes);tampered=copy.deepcopy(confirmed);tampered['tables']['digest_batches'][0]['receipt']='{}';reject(lambda:m.validate(tampered,'org/repo',stream))
    assert len(api.messages)==len(set(api.messages)), 'identical writer commits are not uniquely fenced'
    reject(lambda:b.cursor());restored=store('restored');assert restored.cursor()==batch['cutoff'];assert restored.deliver(batch['key'],remote)['message_id']=='1'
    # AC-3: uncertainty is remote before Slack; fresh local runner reconciles a lost response.
    next_batch=restored.prepare(ReportAPI(),'2026-10-04T00:00:00Z');remote.drop=True;reject(lambda:restored.deliver(next_batch['key'],remote));assert remote.sends==2
    remote.drop=False;fresh=store('fresh');assert fresh.batch(next_batch['key'])['status']=='uncertain';fresh.deliver(next_batch['key'],remote);assert remote.sends==2
    # Storage outage cannot allow a send or advancing durable cursor.
    blocked=fresh.prepare(ReportAPI(),'2026-10-05T00:00:00Z');api.fail=True;reject(lambda:fresh.deliver(blocked['key'],remote));assert remote.sends==2;api.fail=False
    retry=store('retry');assert retry.batch(blocked['key'])['status']=='pending';api.drop=True;reject(lambda:retry.deliver(blocked['key'],remote));assert remote.sends==2
    lost=store('lost');assert lost.batch(blocked['key'])['status']=='uncertain';reject(lambda:lost.deliver(blocked['key'],remote));assert remote.sends==2
    # An unexpectedly removed stream after bootstrap never starts a new cursor.
    api.trees[api.commits[api.head]['tree']['sha']]=[];reject(lambda:m.GitState(api,config['state_branch'],stream,config['bootstrap_sha']))
    # Reject unknown table/identity and tampered receipts without executing remote data.
    bad=copy.deepcopy(exported);bad['tables']['private_feedback']=[];reject(lambda:m.validate(bad,'org/repo',stream))
    bad=copy.deepcopy(exported);bad['repository']='other/repo';reject(lambda:m.validate(bad,'org/repo',stream))
class PrivateReport(ReportAPI):
    def get(self,path):return {**super().get(path),'private':True}
private_state=GitAPI()
with tempfile.TemporaryDirectory() as tmp:
    reject(lambda:m.run(config,PrivateReport(),private_state,None,Path(tmp)/'private',datetime(2026,10,4,22,tzinfo=timezone.utc)))
    assert private_state.writes==0, 'private source published to public state'
# Exercise the hosted runner with the real Slack binding/metadata adapter and new local disks.
class SlackClient:
    def __init__(self):self.messages=[];self.posts=0;self.drop=False
    def call(self,method,body):
        if method=='auth.test':return {'ok':True,'team_id':'T1','bot_id':'B1'}
        if method=='chat.postMessage':
            self.posts+=1;message={'bot_id':'B1','ts':f'{self.posts}.00001','metadata':body['metadata'],'text':body['text']};self.messages.append(message)
            if self.drop:raise RuntimeError('Slack ack lost')
            return {'ok':True,'channel':'C1','message':message}
        assert method=='conversations.history'
        return {'ok':True,'messages':self.messages,'has_more':False,'response_metadata':{'next_cursor':''}}
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp);api=GitAPI();client=SlackClient();now=datetime(2026,10,4,22,tzinfo=timezone.utc)
    assert m.run(config,ReportAPI(),api,client,tmp/'run1',now)['status']=='delivered'
    assert m.run(config,ReportAPI(),api,client,tmp/'run2',now)['status']=='not-due' and client.posts==1
    client.drop=True;later=datetime(2026,10,5,22,tzinfo=timezone.utc)
    reject(lambda:m.run(config,ReportAPI(),api,client,tmp/'run3',later));assert client.posts==2
    client.drop=False;assert m.run(config,ReportAPI(),api,client,tmp/'run4',later)['status']=='delivered' and client.posts==2
# A blocked post-send history read must retain the confirmed checkpoint and never resend.
class HiddenHistory(SlackClient):
    def call(self,method,body):
        if method=='conversations.history':return {'ok':True,'messages':[],'has_more':False,'response_metadata':{'next_cursor':''}}
        return super().call(method,body)
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp);api=GitAPI();client=HiddenHistory();now=datetime(2026,10,4,22,tzinfo=timezone.utc)
    reject(lambda:m.run(config,ReportAPI(),api,client,tmp/'first',now));assert client.posts==1
    assert m.run(config,ReportAPI(),api,client,tmp/'fresh',now)['status']=='not-due' and client.posts==1
# Spec 023: Slack may split one post; only exact complete authenticated fragments certify it.
class SplitSlack(SlackClient):
    def __init__(self):super().__init__();self.hide=False;self.pages=False
    def call(self,method,body):
        if method=='chat.postMessage':
            self.posts+=1;parts=[body['text'][:80],body['text'][80:]]
            self.messages=[{'bot_id':'B1','ts':f'100.{index:06d}','metadata':body['metadata'],'text':part} for index,part in enumerate(parts)]
            if self.drop:raise RuntimeError('Slack ack lost')
            return {'ok':True,'channel':'C1','message':self.messages[-1]}
        if method=='conversations.history':
            messages=[] if self.hide else list(reversed(self.messages))
            if self.pages:
                return {'ok':True,'messages':messages[1:] if body.get('cursor') else messages[:1],
                        'has_more':not bool(body.get('cursor')), 'response_metadata':{'next_cursor':'' if body.get('cursor') else 'more'}}
            return {'ok':True,'messages':messages,'has_more':False,'response_metadata':{'next_cursor':''}}
        return super().call(method,body)
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp);api=GitAPI();client=SplitSlack();now=datetime(2026,10,4,22,tzinfo=timezone.utc)
    # AC-1 + AC-3: actual post response is only the suffix; complete history certifies all fragments.
    result=m.run(config,ReportAPI(),api,client,tmp/'split-send',now)
    assert result['status']=='delivered' and client.posts==1
    ids=json.loads(result['receipt']['message_id']);assert ids=={'schema_version':1,'slack_message_ids':['100.000000','100.000001']}
    confirmed_head=api.head;assert m.run(config,ReportAPI(),api,client,tmp/'split-fresh',now)['status']=='not-due'
    assert api.head==confirmed_head and client.posts==1
    # AC-2: omitted, duplicated, tampered, foreign and widely separated pieces never certify coverage.
    state=m.GitState(api,config['state_branch'],stream);doc=json.loads(state.bytes);m.validate(doc,'org/repo',stream)
    batch=doc['tables']['digest_batches'][0];transport=m.slack.Slack(client,'T1','C1',batch['key'],batch['payload'])
    original=copy.deepcopy(client.messages);client.pages=True;assert transport.lookup(batch['key'])['receipt']==result['receipt'];client.pages=False
    bad_sets=[original[:1],original[1:],original+original]
    for field,value in [('text','changed'),('bot_id','B2'),('metadata',{'event_type':'factory_digest_v1','event_payload':{'key':batch['key'],'payload_sha256':'0'*64}}),('ts','invalid'),('ts','200.000001')]:
        bad=copy.deepcopy(original);bad[1][field]=value;bad_sets.append(bad)
    duplicate=copy.deepcopy(original);duplicate[1]['ts']=duplicate[0]['ts'];bad_sets.append(duplicate)
    extra=copy.deepcopy(original);extra.append({**extra[1],'ts':'100.000002'});bad_sets.append(extra)
    for messages in bad_sets:
        client.messages=messages;reject(lambda:transport.lookup(batch['key']))
    client.messages=original;assert transport.lookup(batch['key'])['receipt']==result['receipt']
    # Boundary newline dropped by the server is reconstructed only if exact expected text matches.
    full=transport.text;boundary=full.index('\n')
    newline_parts=[{**original[0],'text':full[:boundary]}, {**original[1],'text':full[boundary+1:]}]
    assert transport.fragments_proof(newline_parts)==result['receipt']
    for count in (10,11):
        offsets=[len(full)*index//count for index in range(count+1)]
        pieces=[{**original[0],'ts':f'100.{index:06d}','text':full[offsets[index]:offsets[index+1]]} for index in range(count)]
        if count==10:assert len(json.loads(transport.fragments_proof(pieces)['message_id'])['slack_message_ids'])==10
        else:reject(lambda:transport.fragments_proof(pieces))

with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp);api=GitAPI();client=SplitSlack();client.drop=True;now=datetime(2026,10,4,22,tzinfo=timezone.utc)
    # AC-4: loss of the post response + fresh Actions disks recovers without a second post.
    reject(lambda:m.run(config,ReportAPI(),api,client,tmp/'split-lost',now));assert client.posts==1
    uncertain=m.GitState(api,config['state_branch'],stream);assert json.loads(uncertain.bytes)['tables']['digest_batches'][0]['status']=='uncertain'
    client.drop=False;client.hide=True;reject(lambda:m.run(config,ReportAPI(),api,client,tmp/'split-hidden',now));assert api.head==uncertain.head and client.posts==1
    client.hide=False;assert m.run(config,ReportAPI(),api,client,tmp/'split-recovered',now)['status']=='delivered'
    confirmed=api.head;assert m.run(config,ReportAPI(),api,client,tmp/'split-repeat',now)['status']=='not-due' and api.head==confirmed and client.posts==1
# Exercise credential separation and fixed-host API envelope without network.
client=m.API('org/repo','fixture-state-credential')
def envelope(command,**kwargs):
    assert command[:5]==['gh','api','--hostname','github.com','--method']
    assert kwargs['env']['GH_TOKEN']=='fixture-state-credential' and 'fixture-state-credential' not in command
    return SimpleNamespace(returncode=0,stdout=b'{"ok":true}',stderr=b'')
with patch.object(m.subprocess,'run',envelope):assert client.request('repos/org/repo/git/refs/heads/factory-reporting-state')['ok'] is True
reject(lambda:client.request('repos/foreign/repo/git/refs/heads/main'))
workflow=(root/'.github/workflows/factory-hosted-digest.yml').read_text()
assert 'pull_request:' not in workflow and 'pull_request_target:' not in workflow and 'FACTORY_APP_PRIVATE_KEY' not in workflow
assert 'runs-on: ubuntu-latest' in workflow and 'persist-credentials: false' in workflow and 'environment: factory-reporting' in workflow
assert "vars.FACTORY_REPORTING_PROFILE == 'github-hosted'" in workflow and "vars.FACTORY_REPORTING_ENABLED == 'true'" in workflow
assert 'pull-requests: read' in workflow and 'contents: write' in workflow
assert "vars.FACTORY_REPORTING_PROFILE == 'self-hosted'" in (root/'.github/workflows/factory-digest.yml').read_text()
print('factory-hosted-digest: typed public checkpoints, exact bootstrap/protection, unique CAS writers, storage/Slack ack loss, fresh-run recovery and disabled trusted workflow passed')
PYTEST
