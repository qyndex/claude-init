#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: protected queue outbox, exact remote receipts, no blind resend."""
from pathlib import Path
import copy,hashlib,importlib.util,json,sys,tempfile
from datetime import datetime,timezone
source=Path('.claude/scripts/test/factory-reporting-queue-observation.sh').read_text().split("python3 - <<'PY'\n",1)[1].split('count=0\nwith tempfile',1)[0]
exec(compile(source,'protected-queue-delivery-fixture','exec'))
BaseAPI=API
class API(BaseAPI):
 def __init__(self):super().__init__();self.drill_attempt=1;self.bad_drill=False;self.after_patch=None
 def request(self,path,method='GET',payload=None):
  if path=='repos/org/repo/actions/workflows/factory-reporting-queue.yml':return {'id':12,'path':'.github/workflows/factory-reporting-queue.yml','state':'active'}
  if path=='repos/org/repo/actions/runs/900':return {'id':900,'run_attempt':self.drill_attempt,'workflow_id':12,'path':'.github/workflows/factory-reporting-queue.yml','repository':{'id':102 if self.bad_drill else 101,'full_name':'org/repo'},'head_repository':{'id':101,'full_name':'org/repo'},'head_branch':'main','head_sha':'d'*40,'event':'workflow_dispatch','status':'in_progress','conclusion':None}
  result=super().request(path,method,payload)
  if method=='PATCH' and self.after_patch:
   callback=self.after_patch;self.after_patch=None;callback()
  return result
class Client:
 def __init__(self):self.messages=[];self.posts=0;self.queue_posts=0;self.drop_queue=False;self.hide_queue=False;self.hide_digest=False;self.tamper_queue=False;self.duplicate=False;self.split=False;self.bad_team=False
 def call(self,method,body):
  if method=='auth.test':return {'team_id':'T2' if self.bad_team else 'T1','bot_id':'B1','user_id':'U1'}
  if method=='chat.postMessage':
   self.posts+=1;queue=body['metadata']['event_type']=='factory_reporting_queue_v1';self.queue_posts+=int(queue)
   parts=[body['text'][:80],body['text'][80:]] if self.split and not queue else [body['text']]
   messages=[{'bot_id':'B1','ts':f'{100+self.posts}.{i:06d}','metadata':copy.deepcopy(body['metadata']),'text':text} for i,text in enumerate(parts)]
   self.messages.extend(messages)
   if queue and self.drop_queue:raise RuntimeError('lost queue response')
   return {'channel':'C1','message':messages[-1]}
  assert method=='conversations.history',method
  messages=copy.deepcopy(self.messages)
  if self.hide_queue:messages=[m for m in messages if m.get('metadata',{}).get('event_type')!='factory_reporting_queue_v1']
  if self.hide_digest:messages=[m for m in messages if m.get('metadata',{}).get('event_type')!='factory_digest_v1']
  for m in messages:
   if self.tamper_queue and m.get('metadata',{}).get('event_type')=='factory_reporting_queue_v1':m['text']+='changed'
  if self.duplicate:messages+=copy.deepcopy([m for m in messages if m.get('metadata',{}).get('event_type')=='factory_reporting_queue_v1'])
  return {'messages':messages,'has_more':False,'response_metadata':{'next_cursor':''}}
reporting={'enabled':True,'repository':'org/repo','state_repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','start':'2026-10-01T00:00:00Z','attachments_enabled':False}
count=0
def rejects(fn):
 global count
 try:fn()
 except (ValueError,RuntimeError):count+=1;return
 raise AssertionError('unproven queue delivery accepted')
with tempfile.TemporaryDirectory() as temp:
 directory=Path(temp)
 def setup(name,client=None,report_api=None,attachments=False):
  api=API();client=client or Client();hc=dict(ns['config'],attachments_enabled=attachments)
  delivered=ns['m'].run(hc,report_api or ns['ReportAPI'](),api,client,directory/name,now)
  assert delivered['status']=='delivered'
  storage={'state_branch':'factory-reporting-state','bootstrap_sha':api.head,'initialize':True,'policy_approvals':{}}
  return api,client,storage
 for invalid in (None, [], True, 'config'):
  try:q.run_queue(API(),None,invalid,None,reporting,now)
  except ValueError:count+=1
  else:raise AssertionError('non-object config accepted')
 api,client,storage=setup('first')
 api.runs=[copy.deepcopy(run)]
 first=q.run_queue(api,client,config,storage,reporting,now)
 assert first['notifications']==1 and client.queue_posts==1;count+=1
 assert q.run_queue(api,client,config,storage,reporting,now)['notifications']==0 and client.queue_posts==1;count+=1
 api.runs=[];client.hide_digest=True
 rejects(lambda:q.run_queue(api,client,config,storage,reporting,now));assert client.queue_posts==1
 client.hide_digest=False
 recovered=q.run_queue(api,client,config,storage,reporting,now)
 assert recovered['notifications']==1 and client.queue_posts==2;count+=1
 assert q.run_queue(api,client,config,storage,reporting,now)['notifications']==0 and client.queue_posts==2;count+=1
 # Lost effects reconcile on fresh invocation, never blindly retry absent history.
 lost,remote,ls=setup('lost');lost.runs=[copy.deepcopy(run)];remote.drop_queue=True
 rejects(lambda:q.run_queue(lost,remote,config,ls,reporting,now));assert remote.queue_posts==1
 remote.drop_queue=False;remote.hide_queue=True
 rejects(lambda:q.run_queue(lost,remote,config,ls,reporting,now));assert remote.queue_posts==1
 remote.hide_queue=False;remote.tamper_queue=True
 rejects(lambda:q.run_queue(lost,remote,config,ls,reporting,now));remote.tamper_queue=False;remote.duplicate=True
 rejects(lambda:q.run_queue(lost,remote,config,ls,reporting,now));remote.duplicate=False
 assert q.run_queue(lost,remote,config,ls,reporting,now)['notifications']==0 and remote.queue_posts==1;count+=1
 # No durable intent means no post when storage fails.
 broken,bc,bs=setup('broken');broken.runs=[copy.deepcopy(run)];broken.fail=True
 rejects(lambda:q.run_queue(broken,bc,config,bs,reporting,now));assert bc.queue_posts==0
 drill,dc,ds=setup('drill')
 assert q.run_queue(drill,dc,config,ds,reporting,now,drill_run=900)['notifications']==1;count+=1
 assert q.run_queue(drill,dc,config,ds,reporting,now,drill_run=900)['notifications']==0 and dc.queue_posts==1;count+=1
 notice=[m for m in dc.messages if m.get('metadata',{}).get('event_type')=='factory_reporting_queue_v1'][0]
 assert 'drill' in notice['text'] and 'not an actual' in notice['text'];count+=1
 drill.bad_drill=True;rejects(lambda:q.run_queue(drill,dc,config,ds,reporting,now,drill_run=900))
 # Boolean identities must not compare equal to integer 1 or establish a drill.
 class DrillIdentityAPI(API):
  mutation=None
  def request(self,path,method='GET',payload=None):
   if path.endswith('/actions/workflows/factory-reporting-queue.yml'):
    value=super().request(path,method,payload);value['id']=1;return value
   if path.endswith('/actions/runs/1'):
    value=super().request('repos/org/repo/actions/runs/900',method,payload);value.update(id=1,workflow_id=1)
    field,bad=self.mutation
    if field=='response':return bad
    if field.startswith('repository.'):
     value['repository'][field.split('.')[1]]=bad
    else:value[field]=bad
    return value
   value=super().request(path,method,payload)
   if path=='repos/org/repo' and self.mutation and self.mutation[0]=='root_id':value['id']=self.mutation[1]
   return value
 for field,bad in [('id',True),('workflow_id',True),('run_attempt',True),('repository.id',True),('root_id',0),('response',[])]:
  typed,tc,ts=setup('identity-'+field);typed.__class__=DrillIdentityAPI;typed.mutation=(field,bad)
  rejects(lambda:q.run_queue(typed,tc,config,ts,reporting,now,drill_run=1));assert tc.queue_posts==0
 # Same global branch advances for our journal; unchanged worker proof still recovers.
 drill.bad_drill=False;before=drill.head
 assert q.run_queue(drill,dc,config,ds,reporting,now)['notifications']==1 and drill.head!=before;count+=1
 for key,value in [('attachments_enabled','true'),('start','2026-10-02T00:00:00Z'),('destination','C2'),('unknown',True)]:
  rejects(lambda key=key,value=value:q.run_queue(drill,dc,config,ds,dict(reporting,**{key:value}),now))
 split=Client();split.split=True;sa,sc,ss=setup('split',split)
 q.run_queue(sa,sc,config,ss,reporting,now,drill_run=900)
 fragments=copy.deepcopy(sc.messages);sc.messages=[m for m in sc.messages if not (m.get('metadata',{}).get('event_type')=='factory_digest_v1' and m['ts'].endswith('.000001'))]
 rejects(lambda:q.run_queue(sa,sc,config,ss,reporting,now));assert sc.queue_posts==1
 sc.messages=fragments
 assert q.run_queue(sa,sc,config,ss,reporting,now)['notifications']==1;count+=1
 assert len(json.loads(q.QueueStore(sa,config,ss).state.GitState(sa,ss['state_branch'],ns['stream']).bytes)['tables']['digest_batches'])==1
 # Actual existing Attachment adapter, explicitly enabled; no invented split transport.
 file_source=Path('.claude/scripts/test/factory-slack-attachment.sh').read_text().split("<<'PYTEST'\n",1)[1].split('fixture=',1)[0]
 file_ns={};exec(compile(file_source,'existing-file-adapter-fixture','exec'),file_ns)
 class FileClient(Client,file_ns['Client']):
  def __init__(self):Client.__init__(self);file_ns['Client'].__init__(self);self.hide_file=False
  def call(self,method,body):
   if method.startswith('files.'):return file_ns['Client'].call(self,method,body)
   value=Client.call(self,method,body)
   if method=='conversations.history' and self.hide_file:value['messages']=[m for m in value['messages'] if not m.get('files')]
   return value
  def transfer(self,*args,**kwargs):return file_ns['Client'].transfer(self,*args,**kwargs)
 class LargeReport(ns['ReportAPI']):
  def request(self,*args,**kwargs):
   pr=super().request(*args,**kwargs)[0][0]
   return [[dict(pr,number=i,title='Feature '+str(i)+' '+('x'*150),html_url=f'https://github.com/org/repo/pull/{i}') for i in range(1,301)]]
 fa,fc,fs=setup('file',FileClient(),LargeReport(),attachments=True);file_reporting=dict(reporting,attachments_enabled=True)
 assert len(fc.bytes)>35000 and fc.allocations==1;count+=1
 q.run_queue(fa,fc,config,fs,file_reporting,now,drill_run=900)
 rejects(lambda:q.run_queue(fa,fc,config,fs,reporting,now));assert fc.queue_posts==1
 fc.hide_file=True;rejects(lambda:q.run_queue(fa,fc,config,fs,file_reporting,now));fc.hide_file=False
 original_file=fc.bytes;fc.bytes=original_file[:-1]+b'!'
 rejects(lambda:q.run_queue(fa,fc,config,fs,file_reporting,now));fc.bytes=original_file
 assert q.run_queue(fa,fc,config,fs,file_reporting,now)['notifications']==1 and fc.queue_posts==2 and fc.allocations==1;count+=1
 # New worker bytes after recovery-intent CAS must block the recovery post.
 race,rc,rs=setup('race');q.run_queue(race,rc,config,rs,reporting,now,drill_run=900)
 def change_worker():
  state=q.QueueStore(race,config,rs).state;worker=state.GitState(race,rs['state_branch'],ns['stream']);worker.checkpoint(worker.bytes+b'\n')
 race.after_patch=change_worker
 rejects(lambda:q.run_queue(race,rc,config,rs,reporting,now));assert rc.queue_posts==1
 rejects(lambda:q.run_queue(race,rc,config,rs,reporting,now));assert rc.queue_posts==1
 print(f'{count} queue intent/receipt/recovery/split/failure cases passed; no live Slack')
PY
