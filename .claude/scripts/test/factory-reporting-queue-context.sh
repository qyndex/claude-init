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
   if target=='repos/org/repo/actions/runs/900':return {'id':900,'run_attempt':2,'workflow_id':12,'path':'.github/workflows/factory-reporting-queue.yml','repository':{'id':101,'full_name':'org/repo'},'head_repository':{'id':101,'full_name':'org/repo'},'head_branch':'main','head_sha':'a'*40,'event':'workflow_dispatch','status':'in_progress','conclusion':None}
   return super().request(target,method,payload)
 api=API();report_config={'repository':'org/repo','destination':'C1','branch':'main','start':'2026-10-15T00:00:00Z'}
 identity=g.hashlib.sha256(g.canonical(['org/repo','C1','main']).encode()).hexdigest()
 report_state=g.GitState(api,branch,identity,initial,bootstrap_existing=True,state_view=view)
 g.HostedDigest(root/'report.sqlite',report_config,report_state)
 reviewed=out('rev-parse',ref);assert reviewed!=initial,'report creation must precede queue initialization'
 env={'GITHUB_REPOSITORY':'org/repo','GITHUB_SERVER_URL':'https://github.com','GITHUB_API_URL':'https://api.github.com','GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted','GITHUB_REF':'refs/heads/main','GITHUB_SHA':'a'*40,'GITHUB_WORKFLOW_SHA':'a'*40,'GITHUB_WORKFLOW_REF':'org/repo/.github/workflows/factory-reporting-queue.yml@refs/heads/main','GITHUB_RUN_ID':'900','GITHUB_RUN_ATTEMPT':'2','GITHUB_EVENT_NAME':'workflow_dispatch','FACTORY_REPORTING_ENABLED':'true','FACTORY_REPORTING_PROFILE':'github-hosted','FACTORY_REPORTING_QUEUE_ENABLED':'true','FACTORY_REPORTING_BRANCH':'main','FACTORY_REPORTING_CHANNEL':'C1','FACTORY_REPORTING_TEAM_ID':'T1','FACTORY_REPORTING_START':'2026-10-15T00:00:00Z','FACTORY_REPORTING_ATTACHMENTS_ENABLED':'false','FACTORY_REPORTING_STATE_REPOSITORY':'org/repo','FACTORY_REPORTING_STATE_BRANCH':branch,'FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA':reviewed,'FACTORY_REPORTING_QUEUE_INITIALIZE':'true','FACTORY_REPORTING_QUEUE_GRACE_MINUTES':'60','FACTORY_REPORTING_POLICY_APPROVALS':'{}','FACTORY_REPORTING_APP_WRITER_ENABLED':'true','FACTORY_REPORTING_APP_ID':'7'}
 class Client:
  def __init__(self):self.messages=[];self.posts=0
  def call(self,method,body):
   if method=='auth.test':return {'team_id':'T1','bot_id':'B1','user_id':'U1'}
   if method=='chat.postMessage':
    self.posts+=1;message={'bot_id':'B1','ts':str(100+self.posts)+'.000000','metadata':copy.deepcopy(body['metadata']),'text':body['text']};self.messages.append(message);return {'channel':'C1','message':message}
   assert method=='conversations.history',method
   return {'messages':copy.deepcopy(self.messages),'has_more':False,'response_metadata':{'next_cursor':''}}
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
 failures=[];now=datetime(2026,10,15,22,tzinfo=timezone.utc);client=Client()
 with patch.dict(os.environ,{'FACTORY_REPORTING_APP_ID':'7'}),patch.object(importlib.util,'spec_from_file_location',selected_spec):
  # MEDIUM: exact reviewed current head differs from immutable archive bootstrap.
  try:strict=q.build_config(env)
  except ValueError as error:failures.append('MEDIUM '+str(error));print(failures[-1],flush=True)
  # Actual entry exposes the next masked finding after the bootstrap-only repair.
  try:
   first=q.protected_entry(env,api,client,'a'*40,now,drill=True)
   assert first=={'notifications':1,'reconciled':0},first
  except ValueError as error:failures.append(('HIGH ' if 'context fields' in str(error) else 'ENTRY ')+str(error));print(failures[-1],flush=True)
  assert not failures,failures
  built=q.build_config(env);assert len(built['config'])==8 and len(built['reporting'])==8 and built['storage']['state_view']==view
  again=q.protected_entry(env,api,client,'a'*40,now,drill=True);assert again=={'notifications':0,'reconciled':0} and client.posts==1
  assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
  # Unknown reporting/public config keys and stale reviewed initialization never pass.
  def reject(fn):
   try:fn()
   except ValueError:return
   raise AssertionError('unsafe queue context accepted')
  reject(lambda:q.run_queue(api,client,dict(built['config'],unknown=True),built['storage'],built['reporting'],now,drill_run=900))
  reject(lambda:q.run_queue(api,client,built['config'],built['storage'],dict(built['reporting'],unknown=True),now,drill_run=900))
  # Independent second destination has no queue/report authority; old init head cannot reset.
  storage=dict(built['storage'],bootstrap_sha=initial)
  changed=dict(built['config'],destination='C2');reject(lambda:q.QueueStore(api,changed,storage).read())
  # Actual deletion at a later head cannot silently recreate a previously sent journal.
  head=out('rev-parse',ref);index=root/'delete-index';delete_env=dict(os.environ,GIT_INDEX_FILE=str(index))
  git('read-tree',head,env=delete_env);git('update-index','--force-remove','reports/'+q.stream(built['config'])+'.json',env=delete_env)
  deleted_tree=git('write-tree',env=delete_env).stdout.decode().strip();index.unlink()
  deleted=git('commit-tree',deleted_tree,'-p',head,input=b'delete protected queue fixture').stdout.decode().strip();git('update-ref',ref,deleted,head)
  reject(lambda:q.protected_entry(env,api,client,'a'*40,now,drill=True))
  assert out('rev-parse',ref)==deleted and client.posts==1,'deleted journal was silently reset or resent'
  assert git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
 print('actual strict builder/protected entry/real Git queue init, restart/no resend, exact public schema and independent bootstrap PASS')
'''
exec(compile(fixture+adapter+cases,'queue-context-real-git','exec'))
PY
