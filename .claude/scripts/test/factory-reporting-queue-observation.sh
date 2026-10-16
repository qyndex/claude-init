#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-5: independently read bounded reporting metadata, never guessed ownership."""
from pathlib import Path
import copy,importlib.util,json,sys,tempfile
from datetime import datetime,timezone,timedelta
from urllib.parse import urlparse,parse_qs
sys.argv=['test',str(Path.cwd())]
fixture=Path('.claude/scripts/test/factory-hosted-digest.sh').read_text().split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory() as tmp:',1)[0]
ns={};exec(compile(fixture,'hosted-queue-health-fixture','exec'),ns)
s=importlib.util.spec_from_file_location('queue',Path('.claude/scripts/factory-reporting-queue.py'));q=importlib.util.module_from_spec(s);s.loader.exec_module(q)
config={'enabled':True,'queue_monitor_enabled':True,'repository':'org/repo','state_repository':'org/repo','branch':'main','destination':'C1','team_id':'T1','grace_minutes':60}
now=datetime(2026,10,15,22,tzinfo=timezone.utc)
workflows={9:'.github/workflows/factory-hosted-digest.yml',10:'.github/workflows/factory-hosted-feedback.yml',11:'.github/workflows/factory-reporting-alerts.yml'}
run={'id':700,'run_attempt':1,'workflow_id':9,'path':workflows[9],'repository':{'id':101,'full_name':'org/repo'},'head_repository':{'id':101,'full_name':'org/repo'},'head_branch':'main','head_sha':'a'*40,'event':'schedule','status':'waiting','conclusion':None,'created_at':'2026-10-12T18:01:23Z','updated_at':'2026-10-12T18:01:23Z','run_started_at':None}
job={'id':800,'run_id':700,'run_attempt':1,'head_sha':'a'*40,'status':'waiting','created_at':'2026-10-12T18:01:23Z','started_at':None,'steps':[]}
class API(ns['GitAPI']):
 def __init__(self):super().__init__();self.runs=[];self.job=copy.deepcopy(job);self.cap=False;self.fail_api=False;self.readonly=False;self.calls=[];self.late=False;self.wait_calls=0;self.disabled_workflow=False;self.bad_count=False;self.partial_jobs=False;self.many_policies=False;self.duplicate=False;self.workflow_id_overflow=False
 def request(self,path,method='GET',payload=None):
  if self.readonly:assert method=='GET' and payload is None,'observer wrote state'
  self.calls.append(path)
  if '/actions/' in path:
   if self.fail_api:raise RuntimeError('DO_NOT_ECHO_PRIVATE_SENTINEL')
   suffix=path.removeprefix('repos/org/repo/');query=parse_qs(urlparse(path).query)
   if suffix.startswith('actions/workflows/') and '/runs?' not in suffix:
    filename=suffix.rsplit('/',1)[1];matches=[(i,p) for i,p in workflows.items() if p.rsplit('/',1)[1]==filename];assert len(matches)==1
    return {'id':2**63 if self.workflow_id_overflow and matches[0][0]==9 else matches[0][0],'path':matches[0][1],'state':'disabled_manually' if self.disabled_workflow else 'active'}
   if '/runs?' in suffix:
    workflow=int(suffix.split('/')[2]);status=query['status'][0];rows=[copy.deepcopy(r) for r in self.runs if r['workflow_id']==workflow and r['status']==status]
    if workflow==9 and status=='waiting':
     self.wait_calls+=1
     if self.late and self.wait_calls>1:rows=[copy.deepcopy(run)]
    if self.cap:return {'total_count':1000,'workflow_runs':rows}
    if self.bad_count:return {'total_count':True,'workflow_runs':rows}
    if self.duplicate and rows:return {'total_count':2,'workflow_runs':[rows[0],rows[0]]}
    page=int(query['page'][0]);return {'total_count':len(rows),'workflow_runs':rows[(page-1)*100:page*100]}
   if '/attempts/' in suffix:
    item=copy.deepcopy(self.job);identity=int(suffix.split('/')[2]);item.update(run_id=identity,id=identity+100)
    if identity!=700:item['created_at']=next(r['created_at'] for r in self.runs if r['id']==identity)
    return {'total_count':2 if self.partial_jobs else 1,'jobs':[item]}
   raise AssertionError(path)
  if self.many_policies and '/rules/branches/' in path:return [{'type':kind,'ruleset_id':i} for i in range(1,201) for kind in ('non_fast_forward','deletion')]
  if self.many_policies and '/rulesets/' in path:return {'enforcement':'active','bypass_actors':[]}
  value=super().request(path,method,payload)
  if path=='repos/org/repo':value['id']=101
  return value
count=0
with tempfile.TemporaryDirectory() as temp:
 api=API();storage={'state_branch':'factory-reporting-state','bootstrap_sha':api.head,'initialize':False,'policy_approvals':{}}
 hc=ns['config'];state=ns['m'];store=state.HostedDigest(Path(temp)/'worker',hc,state.GitState(api,hc['state_branch'],ns['stream'],hc['bootstrap_sha']))
 batch=store.prepare(ns['ReportAPI'](),state.slack.due(now));store.deliver(batch['key'],ns['Transport']());api.readonly=True
 before=api.head
 healthy=q.observe_queue(api,config,storage,now)
 assert healthy['status']=='metadata-current' and healthy['scope']=='queue-metadata' and healthy['coverage_complete'] and healthy['recovery_eligible'] is False and healthy['receipt_verified'] is False;count+=1
 api.runs=[copy.deepcopy(run),dict(copy.deepcopy(run),id=701,workflow_id=11,path=workflows[11],status='pending',updated_at='2026-10-15T21:59:00Z',created_at='2026-10-15T21:59:00Z')]
 stalled=q.observe_queue(api,config,storage,now)
 assert stalled['status']=='stalled' and stalled['stalled'][0]['run_id']==700 and stalled['stalled'][0]['execution_observed'] is False and stalled['deployment_context']=='unknown',stalled;count+=1
 assert 'owner' not in json.dumps(stalled) and api.head==before;count+=1
 def unknown(change):
  global count
  candidate=copy.deepcopy(api);candidate.runs=[copy.deepcopy(run)];change(candidate)
  result=q.observe_queue(candidate,config,storage,now)
  assert result['status']=='unknown' and not result['coverage_complete'] and not result['recovery_eligible'],result
  assert candidate.head==before and 'PRIVATE_SENTINEL' not in json.dumps(result);count+=1
 for key,value in [('head_branch','foreign'),('repository',{'id':102,'full_name':'org/repo'}),('event','pull_request'),('run_attempt',True),('head_sha','not-sha'),('created_at','9999-01-01T00:00:00Z'),('updated_at','bad'),('path',workflows[10])]:
  unknown(lambda a,key=key,value=value:a.runs[0].update({key:value}))
 unknown(lambda a:setattr(a,'cap',True));unknown(lambda a:setattr(a,'fail_api',True))
 unknown(lambda a:a.job.update(run_attempt=2));unknown(lambda a:a.job.update(status='unknown-state'))
 unknown(lambda a:a.job.update(started_at='9999-01-01T00:00:00Z'))
 unknown(lambda a:(setattr(a,'runs',[]),setattr(a,'late',True),setattr(a,'wait_calls',0)))
 unknown(lambda a:a.trees.update({a.commits[a.head]['tree']['sha']:[]}))
 unknown(lambda a:setattr(a,'disabled_workflow',True))
 unknown(lambda a:setattr(a,'bad_count',True))
 unknown(lambda a:setattr(a,'partial_jobs',True))
 unknown(lambda a:setattr(a,'duplicate',True))
 unknown(lambda a:setattr(a,'many_policies',True))
 unknown(lambda a:a.job.update(head_sha='e'*40))
 unknown(lambda a:a.job.update(steps=[{'status':'queued'}]*101))
 unknown(lambda a:setattr(a,'runs',[dict(copy.deepcopy(run),id=700+i) for i in range(17)]))
 unknown(lambda a:a.runs[0].pop('conclusion'))
 unknown(lambda a:setattr(a,'workflow_id_overflow',True))
 # Recent activity on an old run is conservative grace, not a newly proved stall.
 api.runs=[dict(copy.deepcopy(run),updated_at='2026-10-15T21:59:00Z')]
 recent=q.observe_queue(api,config,storage,now);assert recent['status']=='metadata-current' and not recent['stalled'];count+=1
 for bad in (dict(config,grace_minutes=True),dict(config,grace_minutes=14),dict(config,queue_monitor_enabled=False)):
  result=q.observe_queue(api,bad,storage,now);assert result['status']=='unknown' and not result['coverage_complete'];count+=1
 future=q.observe_queue(api,config,storage,datetime.now(timezone.utc)+timedelta(hours=1))
 assert future['status']=='unknown' and future['reason']=='clock-invalid' and not future['coverage_complete'];count+=1
 print(f'{count} bounded protected queue observation cases passed; no Slack or state mutation')
PY
