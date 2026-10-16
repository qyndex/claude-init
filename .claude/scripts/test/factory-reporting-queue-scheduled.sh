#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: actual config/protected queue entry and real Git state initialization."""
from pathlib import Path
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
adapter=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct',1)[0]
cases=r'''
 from unittest.mock import patch
 from datetime import datetime,timezone
 qs=importlib.util.spec_from_file_location('queue_context',scripts/'factory-reporting-queue.py');q=importlib.util.module_from_spec(qs);qs.loader.exec_module(q)
 gs=importlib.util.spec_from_file_location('queue_report_state',scripts/'factory-git-state.py');g=importlib.util.module_from_spec(gs);gs.loader.exec_module(g)
 authority=(root/'authority').resolve();fixed=authority/'factory';fixed.mkdir(parents=True)
 for name,value in [('policy.json',policy),('receipt-store.json',{'repository':'org/repo','visibility':'public'})]:(fixed/name).write_text(json.dumps(value))
 shutil=__import__('shutil');shutil.copyfile(trust,fixed/'receipt-trust.json');shutil.copyfile(approval,fixed/'receipt-archive-bootstrap.json')
 approved=fixed/'receipt-archive-bootstrap.json';view={'mode':'archive','approval_path':str(approved)}
 class API(PipelineState):
  def request(self,target,method='GET',payload=None):
   if target=='repos/org/repo/actions/workflows/factory-reporting-queue.yml':return {'id':12,'path':'.github/workflows/factory-reporting-queue.yml','state':'active'}
   if target=='repos/org/repo/actions/runs/900':return {'id':900,'run_attempt':2,'workflow_id':12,'path':'.github/workflows/factory-reporting-queue.yml','repository':{'id':101,'full_name':'org/repo'},'head_repository':{'id':101,'full_name':'org/repo'},'head_branch':'main','head_sha':'a'*40,'event':'schedule','status':'in_progress','conclusion':None}
   return super().request(target,method,payload)
 api=API();report_config={'repository':'org/repo','destination':'C1','branch':'main','start':'2026-10-15T00:00:00Z'}
 identity=g.hashlib.sha256(g.canonical(['org/repo','C1','main']).encode()).hexdigest()
 report_state=g.GitState(api,branch,identity,initial,bootstrap_existing=True,state_view=view)
 report=g.HostedDigest(root/'report.sqlite',report_config,report_state)
 reviewed=out('rev-parse',ref);assert reviewed!=initial,'report creation must precede queue initialization'
 env={'GITHUB_REPOSITORY':'org/repo','GITHUB_SERVER_URL':'https://github.com','GITHUB_API_URL':'https://api.github.com','GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted','GITHUB_REF':'refs/heads/main','GITHUB_SHA':'a'*40,'GITHUB_WORKFLOW_SHA':'a'*40,'GITHUB_WORKFLOW_REF':'org/repo/.github/workflows/factory-reporting-queue.yml@refs/heads/main','GITHUB_RUN_ID':'900','GITHUB_RUN_ATTEMPT':'2','GITHUB_EVENT_NAME':'schedule','FACTORY_REPORTING_ENABLED':'true','FACTORY_REPORTING_PROFILE':'github-hosted','FACTORY_REPORTING_QUEUE_ENABLED':'true','FACTORY_REPORTING_BRANCH':'main','FACTORY_REPORTING_CHANNEL':'C1','FACTORY_REPORTING_TEAM_ID':'T1','FACTORY_REPORTING_START':'2026-10-15T00:00:00Z','FACTORY_REPORTING_ATTACHMENTS_ENABLED':'false','FACTORY_REPORTING_STATE_REPOSITORY':'org/repo','FACTORY_REPORTING_STATE_BRANCH':branch,'FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA':reviewed,'FACTORY_REPORTING_QUEUE_INITIALIZE':'true','FACTORY_REPORTING_QUEUE_GRACE_MINUTES':'60','FACTORY_REPORTING_POLICY_APPROVALS':'{}','FACTORY_REPORTING_APP_WRITER_ENABLED':'true','FACTORY_REPORTING_APP_ID':'7'}
 class Client:
  def __init__(self):self.messages=[];self.posts=0;self.hide_digest=False
  def call(self,method,body):
   if method=='auth.test':return {'team_id':'T1','bot_id':'B1','user_id':'U1'}
   if method=='chat.postMessage':
    self.posts+=1;message={'bot_id':'B1','ts':str(100+self.posts)+'.000000','metadata':copy.deepcopy(body['metadata']),'text':body['text']};self.messages.append(message);return {'channel':'C1','message':message}
   assert method=='conversations.history',method
   return {'messages':[m for m in copy.deepcopy(self.messages) if not self.hide_digest or m['metadata']['event_type']!='factory_digest_v1'],'has_more':False,'response_metadata':{'next_cursor':''}}
 original_spec=importlib.util.spec_from_file_location
 def selected_spec(name,path,*args,**kwargs):
  spec=original_spec(name,path,*args,**kwargs)
  if Path(path).name=='factory-reporting-transport.py':
   loader=spec.loader
   class Loader:
    def create_module(self,spec):return loader.create_module(spec)
    def exec_module(self,module):
     loader.exec_module(module);attach=module.attach_reporting_context
     def fixed_context(cfg):
      return attach(cfg,checkout=authority)
     module.attach_reporting_context=fixed_context
   spec.loader=Loader()
  return spec

 from types import SimpleNamespace
 from collections import Counter
 from urllib.parse import urlparse,parse_qs
 ts=original_spec('queue_routed_transport',scripts/'factory-reporting-transport.py');transport=importlib.util.module_from_spec(ts);ts.loader.exec_module(transport)
 workflows={9:'.github/workflows/factory-hosted-digest.yml',10:'.github/workflows/factory-hosted-feedback.yml',11:'.github/workflows/factory-reporting-alerts.yml'}
 waiting={'id':700,'run_attempt':1,'workflow_id':9,'path':workflows[9],'repository':{'id':101,'full_name':'org/repo'},'head_repository':{'id':101,'full_name':'org/repo'},'head_branch':'main','head_sha':'a'*40,'event':'schedule','status':'waiting','conclusion':None,'created_at':'2026-10-12T18:01:23Z','updated_at':'2026-10-12T18:01:23Z','run_started_at':None}
 rows=[];calls=[]
 def provider(command,**kwargs):
  assert command[:5]==['gh','api','--hostname','github.com','--method'],command
  method,target=command[5:7];role={'fixture-source':'source','fixture-writer':'writer'}[kwargs['env']['GH_TOKEN']]
  assert (role=='source')==('/actions/' in target or '/pulls' in target or '/contents/' in target),(role,target)
  payload=json.load(kwargs['stdin']) if '--input' in command else None
  calls.append({'role':role,'method':method,'path':target})
  if '/actions/workflows/' in target and not target.endswith('factory-reporting-queue.yml'):
   suffix=target.split('/actions/workflows/',1)[1];query=parse_qs(urlparse(target).query)
   if '/runs?' in suffix:
    workflow=int(suffix.split('/')[0]);selected=[copy.deepcopy(r) for r in rows if r['workflow_id']==workflow and r['status']==query['status'][0]]
    value={'total_count':len(selected),'workflow_runs':selected}
   else:
    identity,path=next((i,p) for i,p in workflows.items() if p.rsplit('/',1)[1]==suffix)
    value={'id':identity,'path':path,'state':'active'}
  elif '/actions/runs/700/attempts/1/jobs?' in target:value={'total_count':1,'jobs':[{'id':800,'run_id':700,'run_attempt':1,'head_sha':'a'*40,'status':'waiting','created_at':waiting['created_at'],'started_at':None,'steps':[]}]}
  else:value=api.request(target,method,payload)
  return SimpleNamespace(returncode=0,stdout=json.dumps(value).encode(),stderr=b'')
 now=datetime(2026,10,15,22,tzinfo=timezone.utc);client=Client()
 class ReportSource:
  repo='org/repo'
  def request(self,*args,**kwargs):return [[]]
 batch=report.prepare(ReportSource(),'2026-10-15T21:00:00Z')
 report.deliver(batch['key'],g.slack.transport(client,dict(report_config,team_id='T1',attachments_enabled=False),batch))
 env['FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA']=out('rev-parse',ref)
 assert env['FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA']!=initial
 original_reader=q._QueueReader.observe
 def diagnostic_reader(self):
  try:return original_reader(self)
  except Exception as error:
   print('READER_EXCEPTION '+repr(error)+' calls='+str(self.store.calls),flush=True);raise
 q._QueueReader.observe=diagnostic_reader
 observed=q.observe_queue
 def diagnostic_observe(*args,**kwargs):
  value=observed(*args,**kwargs);print('OBSERVATION '+json.dumps(value,default=str),flush=True);return value
 q.observe_queue=diagnostic_observe
 outcomes=[]
 def invoke(label):
  routed=transport.RoutedAPI('org/repo','fixture-source','fixture-writer');start=len(calls)
  try:result=q.protected_entry(env,routed,client,'a'*40,now)
  except Exception as error:
   outcomes.append({'case':label,'error':str(error),'type':type(error).__name__,'calls':routed.budget.calls,'bytes':routed.budget.bytes,'roles':dict(Counter(c['role'] for c in calls[start:]))});print(json.dumps(outcomes[-1]),flush=True);raise
  outcomes.append({'case':label,'result':result,'calls':routed.budget.calls,'bytes':routed.budget.bytes,'roles':dict(Counter(c['role'] for c in calls[start:]))});print(json.dumps(outcomes[-1]),flush=True)
  assert routed.budget.calls<=2048 and routed.budget.bytes<=33554432
  assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
  return result
 with patch.dict(os.environ,{'FACTORY_REPORTING_APP_ID':'7'}),patch.object(importlib.util,'spec_from_file_location',selected_spec),patch.object(transport.process,'run',provider):
  rows[:]=[waiting];assert invoke('scheduled-stalled')['notifications']==1
  assert invoke('scheduled-stalled-restart')['notifications']==0
  rows.clear();client.hide_digest=True
  try:invoke('recovery-missing-remote-receipt')
  except ValueError:pass
  else:raise AssertionError('recovery without exact remote receipt accepted')
  api.conflict=True  # Existing journal: concurrent opaque writer forces actual CAS/reload.
  client.hide_digest=False;assert invoke('scheduled-recovery')['notifications']==1
  assert git('show',ref+':reports/'+'1'*64+'.json').stdout==b'concurrent encrypted checkpoint'
  assert invoke('scheduled-recovery-restart')['notifications']==0
 print(json.dumps({'outcomes':outcomes,'requests':calls},sort_keys=True))
 print('scheduled real Git + actual RoutedAPI queue incident/recovery PASS; synthetic gh/Slack only')
'''
exec(compile(fixture+adapter+cases,'queue-scheduled-routed-real-git','exec'))
PY
