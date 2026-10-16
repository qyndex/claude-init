#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-5/AC-7: exact protected entry and separated metadata/state credentials."""
import copy,importlib.util,json,os,subprocess,tempfile
from pathlib import Path
from datetime import datetime,timezone
spec=importlib.util.spec_from_file_location('queue',Path('.claude/scripts/factory-reporting-queue.py'));q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
env={'GITHUB_REPOSITORY':'org/repo','GITHUB_SERVER_URL':'https://github.com','GITHUB_API_URL':'https://api.github.com','GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted','GITHUB_REF':'refs/heads/main','GITHUB_SHA':'a'*40,'GITHUB_WORKFLOW_SHA':'a'*40,'GITHUB_WORKFLOW_REF':'org/repo/.github/workflows/factory-reporting-queue.yml@refs/heads/main','GITHUB_RUN_ID':'900','GITHUB_RUN_ATTEMPT':'2','GITHUB_EVENT_NAME':'workflow_dispatch','FACTORY_REPORTING_ENABLED':'true','FACTORY_REPORTING_PROFILE':'github-hosted','FACTORY_REPORTING_QUEUE_ENABLED':'true','FACTORY_REPORTING_BRANCH':'main','FACTORY_REPORTING_CHANNEL':'C1','FACTORY_REPORTING_TEAM_ID':'T1','FACTORY_REPORTING_START':'2026-10-01T00:00:00Z','FACTORY_REPORTING_ATTACHMENTS_ENABLED':'false','FACTORY_REPORTING_STATE_REPOSITORY':'org/repo','FACTORY_REPORTING_STATE_BRANCH':'factory-reporting-state','FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA':'b'*40,'FACTORY_REPORTING_QUEUE_INITIALIZE':'false','FACTORY_REPORTING_QUEUE_GRACE_MINUTES':'60','FACTORY_REPORTING_POLICY_APPROVALS':'{}'}
count=0
built=q.build_config(env)
assert built['config']['queue_monitor_enabled'] is True and built['reporting']['attachments_enabled'] is False and built['storage']['initialize'] is False;count+=1
class API:
 repo='org/repo'
 def __init__(self):self.calls=[];self.change=None
 def request(self,path,method='GET',payload=None):
  self.calls.append((path,method,payload));assert method=='GET' and payload is None
  if path=='repos/org/repo':v={'id':101,'full_name':'org/repo','default_branch':'main'}
  elif path.endswith('/workflows/factory-reporting-queue.yml'):v={'id':12,'path':'.github/workflows/factory-reporting-queue.yml','state':'active'}
  else:
   assert path=='repos/org/repo/actions/runs/900'
   v={'id':900,'workflow_id':12,'run_attempt':2,'path':'.github/workflows/factory-reporting-queue.yml','event':'workflow_dispatch','status':'in_progress','conclusion':None,'head_branch':'main','head_sha':'a'*40,'repository':{'id':101,'full_name':'org/repo'},'head_repository':{'id':101,'full_name':'org/repo'}}
   if self.change:v.update(self.change)
  return v
seen=[]
def delivery(api,client,config,storage,reporting,now,*,drill_run=None):
 seen.append(drill_run);return {'notifications':0}
original=q.run_queue;q.run_queue=delivery
now=datetime.now(timezone.utc)
def rejects(fn):
 global count
 try:fn()
 except ValueError:count+=1;return
 raise AssertionError('unprotected queue ingress accepted')
assert q.protected_entry(env,API(),None,'a'*40,now,drill=True)=={'notifications':0} and seen==[900];count+=1
scheduled=dict(env,GITHUB_EVENT_NAME='schedule');api=API();api.change={'event':'schedule'}
q.protected_entry(scheduled,api,None,'a'*40,now);assert seen[-1] is None;count+=1
for key,value in [('GITHUB_SERVER_URL','https://foreign.invalid'),('GITHUB_API_URL','https://api.foreign.invalid'),('GITHUB_ACTIONS','false'),('RUNNER_ENVIRONMENT','self-hosted'),('GITHUB_REF','refs/pull/1/merge'),('GITHUB_EVENT_NAME','pull_request'),('GITHUB_WORKFLOW_REF','foreign/repo/x@refs/heads/main'),('GITHUB_WORKFLOW_SHA','c'*40),('GITHUB_RUN_ID','True'),('GITHUB_RUN_ATTEMPT','0'),('FACTORY_REPORTING_QUEUE_ENABLED','false'),('FACTORY_REPORTING_PROFILE','self-hosted'),('FACTORY_REPORTING_ATTACHMENTS_ENABLED',''),('FACTORY_REPORTING_QUEUE_INITIALIZE','TRUE'),('FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA',''),('FACTORY_REPORTING_QUEUE_GRACE_MINUTES','14'),('FACTORY_REPORTING_START','2026-10-01T00:00:00.1234567Z'),('FACTORY_REPORTING_STATE_REPOSITORY','foreign/repo'),('FACTORY_REPORTING_POLICY_APPROVALS','{"x":1,"x":2}'),('FACTORY_REPORTING_POLICY_APPROVALS',' '*262145)]:
 bad=dict(env,**{key:value});api=API();before=len(seen)
 rejects(lambda:q.protected_entry(bad,api,None,'a'*40,now));assert len(seen)==before and api.calls==[]
rejects(lambda:q.protected_entry(scheduled,API(),None,'a'*40,now,drill=True))
rejects(lambda:q.protected_entry(env,API(),None,'c'*40,now))
for change in ({'id':True},{'workflow_id':True},{'run_attempt':True},{'run_attempt':3},{'head_sha':'c'*40},{'event':'schedule'},{'head_repository':{'id':102,'full_name':'org/repo'}},{'status':'completed','conclusion':'success'}):
 api=API();api.change=change;before=len(seen)
 rejects(lambda:q.protected_entry(env,api,None,'a'*40,now));assert len(seen)==before
q.run_queue=original
class Route:
 repo='org/repo'
 def __init__(self):self.calls=[]
 def request(self,*args):self.calls.append(args);return {}
actions=Route();state=Route();routed=q.RoutedAPI('org/repo',actions,state)
routed.request('repos/org/repo/actions/runs/900');routed.request('repos/org/repo');routed.request('repos/org/repo/git/refs/heads/state','PATCH',{'sha':'b'*40})
assert len(actions.calls)==1 and len(state.calls)==2;count+=1
rejects(lambda:routed.request('repos/org/repo/actions/runs/900','POST',{}))
rejects(lambda:routed.request('repos/foreign/repo/actions/runs/900'))
routed.request('repos/org/repo/actions/workflows/factory-hosted-digest.yml/runs?branch=release%2Fmain');routed.request('repos/org/repo/git/ref/heads/factory%2Freporting')
assert len(actions.calls)==2 and len(state.calls)==3;count+=1
for encoded in ('%2E','%25','%2f','%5C'):
 rejects(lambda encoded=encoded:routed.request('repos/org/repo/git/ref/heads/factory'+encoded+'reporting'))
# Execute actual main construction, spying only on the external transport module.
import contextlib,io,sys,types
real_spec=importlib.util.spec_from_file_location;created=[];routed_calls=[]
class TokenAPI(API):
 def __init__(self,repository,token):super().__init__();self.repo=repository;self.token=token;created.append(token)
 def request(self,path,method='GET',payload=None):
  routed_calls.append((path,self.token));value=super().request(path,method,payload)
  if path.endswith('/actions/runs/900'):value['head_sha']=head
  return value
class Loader:
 def create_module(self,spec):return None
 def exec_module(self,module):module.API=TokenAPI;module.slack=types.SimpleNamespace(http_client=lambda config:None)
def select_spec(name,path,*args,**kwargs):
 if name=='queue_entry_state':return importlib.util.spec_from_loader(name,Loader())
 return real_spec(name,path,*args,**kwargs)
head=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
saved_env=dict(os.environ);saved_argv=sys.argv[:]
try:
 importlib.util.spec_from_file_location=select_spec;q.run_queue=delivery;sys.argv=['queue']
 for writer in ('STATE_SECRET_SENTINEL',''):
  os.environ.clear();os.environ.update(env,GITHUB_SHA=head,GITHUB_WORKFLOW_SHA=head,GH_TOKEN='ACTION_SECRET_SENTINEL',FACTORY_REPORTING_STATE_TOKEN=writer)
  output=io.StringIO();created.clear();routed_calls.clear()
  with contextlib.redirect_stdout(output):assert q.main()==0
  assert created==['ACTION_SECRET_SENTINEL',writer or 'ACTION_SECRET_SENTINEL']
  assert all(token=='ACTION_SECRET_SENTINEL' if '/actions/' in path else token==(writer or 'ACTION_SECRET_SENTINEL') for path,token in routed_calls)
  assert 'SECRET_SENTINEL' not in output.getvalue();count+=1
finally:
 importlib.util.spec_from_file_location=real_spec;q.run_queue=original;sys.argv=saved_argv;os.environ.clear();os.environ.update(saved_env)
workflow=Path('.github/workflows/factory-reporting-queue.yml').read_text()
assert "cron: '11,26,41,56 * * * *'" in workflow and 'group: factory-reporting-queue-${{ github.repository }}' in workflow and 'cancel-in-progress: false' in workflow;count+=1
assert 'environment: factory-reporting' in workflow and "vars.FACTORY_REPORTING_QUEUE_ENABLED == 'true'" in workflow and "github.ref == format('refs/heads/{0}', github.event.repository.default_branch)" in workflow;count+=1
assert 'workflow_run:' not in workflow and 'contents: write' in workflow and 'actions: read' in workflow and 'FACTORY_REPORTING_STATE_TOKEN: ${{ secrets.FACTORY_REPORTING_STATE_TOKEN }}' in workflow and 'GH_TOKEN: ${{ github.token }}' in workflow;count+=1
assert 'FACTORY_REPORTING_QUEUE_INITIALIZE: ${{ vars.FACTORY_REPORTING_QUEUE_INITIALIZE }}' in workflow and 'FACTORY_REPORTING_ATTACHMENTS_ENABLED: ${{ vars.FACTORY_REPORTING_ATTACHMENTS_ENABLED }}' in workflow and 'FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA: ${{ vars.FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA }}' in workflow;count+=1
for name in ('factory-hosted-digest.yml','factory-hosted-feedback.yml','factory-reporting-alerts.yml'):
 text=Path('.github/workflows',name).read_text();assert 'group: factory-reporting-${{ github.repository }}' in text and 'group: factory-reporting-queue-' not in text
# Actual CLI rejects before any external command and does not echo the input sentinel.
result=subprocess.run(['python3','.claude/scripts/factory-reporting-queue.py'],env=dict(os.environ,GITHUB_SERVER_URL='DO_NOT_ECHO_SENTINEL'),capture_output=True,text=True)
assert result.returncode==2 and 'DO_NOT_ECHO_SENTINEL' not in result.stdout+result.stderr;count+=1
print(f'{count} protected queue workflow/config/credential boundary cases passed; no live calls')
PY
