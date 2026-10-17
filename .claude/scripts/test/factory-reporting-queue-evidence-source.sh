#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-8: real local checkout + bounded protected GitHub run/log observations."""
import copy,importlib.util,json,os,subprocess,tempfile
from pathlib import Path
from datetime import datetime,timezone
module=Path('.claude/scripts/factory-reporting-queue-evidence.py')
assert module.exists(),'protected run/source/log evidence observer is absent'
spec=importlib.util.spec_from_file_location('evidence',module);e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
count=0
# Actual public Actions format observed in job116777712471; selected safe fixture,
# not raw job logs or actual rollout proof. Runner setup precedes CLI JSON.
framed=(b'2026-10-16T00:00:00.1234567Z [command]/usr/bin/git version\n'
        b'2026-10-16T00:00:00.1234567Z shell setup\n'
        b'2026-10-16T00:00:00.1234567Z {"notifications":1,"reconciled":0}\n'
        b'2026-10-16T00:00:00.1234567Z {"notifications":0,"reconciled":0}\n')
assert e.results(framed)==[{'notifications':1,'reconciled':0},{'notifications':0,'reconciled':0}]
count+=1
selections={'drill':{'run_id':900,'attempt':2},'recovery':{'run_id':901,'attempt':1},'repeat':{'run_id':902,'attempt':1}}
with tempfile.TemporaryDirectory() as directory:
 root=Path(directory);(root/'.github/workflows').mkdir(parents=True);(root/'.claude/scripts').mkdir(parents=True)
 (root/'.github/workflows/factory-reporting-queue.yml').write_text('reviewed workflow fixture')
 (root/'.claude/scripts/factory-reporting-queue.py').write_text('# reviewed runtime fixture\n')
 def git(*args):return subprocess.check_output(['git','-C',directory,*args],stderr=subprocess.DEVNULL,text=True).strip()
 git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');git('add','.');git('commit','-qm','reviewed source')
 sha=git('rev-parse','HEAD');now=datetime(2026,10,16,2,tzinfo=timezone.utc)
 class API:
  repo='org/repo'
  def __init__(self):self.calls=[];self.mutate=None;self.extra=b'';self.drift=False
  def request(self,path,method='GET',payload=None,*,raw=False):
   assert method=='GET' and payload is None;self.calls.append(path)
   if path=='repos/org/repo':v={'id':101,'full_name':self.repo,'default_branch':'main','archived':False,'private':False}
   elif path=='repos/org/repo/git/ref/heads/main':v={'ref':'refs/heads/main','object':{'type':'commit','sha':'c'*40 if self.drift and self.calls.count(path)>1 else sha}}
   elif path.endswith('/workflows/factory-reporting-queue.yml'):v={'id':12,'path':'.github/workflows/factory-reporting-queue.yml','state':'active'}
   elif '/attempts/' in path:
    run=int(path.split('/runs/')[1].split('/')[0]);v={'total_count':1,'jobs':[{'id':run+100,'run_id':run,'run_attempt':selections[('drill','recovery','repeat')[run-900]]['attempt'],'head_sha':sha,'name':'monitor','status':'completed','conclusion':'success','steps':[{'number':2,'name':'Observe and reconcile protected queue notifications','status':'completed','conclusion':'success'}]}]}
   elif path.endswith('/logs'):
    run=int(path.split('/jobs/')[1].split('/')[0])-100;values=[1,0] if run==900 else [1] if run==901 else [0]
    return b'2026-10-16T00:00:00.1234567Z [command]/usr/bin/git version\n2026-10-16T00:00:00.1234567Z shell setup\n'+b''.join(b'2026-10-16T00:00:00.1234567Z '+json.dumps({'notifications':n,'reconciled':0}).encode()+b'\n' for n in values)+self.extra
   else:
    run=int(path.rsplit('/',1)[1]);role=('drill','recovery','repeat')[run-900];hour=run-900
    v={'id':run,'run_attempt':selections[role]['attempt'],'workflow_id':12,'path':'.github/workflows/factory-reporting-queue.yml','repository':{'id':101,'full_name':self.repo},'head_repository':{'id':101,'full_name':self.repo},'head_branch':'main','head_sha':sha,'event':'workflow_dispatch','status':'completed','conclusion':'success','created_at':f'2026-10-15T{20+hour}:00:00Z','run_started_at':f'2026-10-15T{20+hour}:00:01Z','updated_at':f'2026-10-15T{20+hour}:01:00Z'}
   return self.mutate(path,v) if self.mutate else v
 api=API();proof=e.observe_runs(api,root,'main',selections,now)
 assert proof['source_sha']==sha and [r['notifications'] for r in proof['runs']]==[[1,0],[1],[0]] and proof['mode']=='administrative-run-observation';count+=1
 def rejects(fn):
  global count
  try:fn()
  except ValueError:count+=1;return
  raise AssertionError('untrusted source/run/log accepted')
 for field,bad in [('id',True),('run_attempt',True),('run_attempt',9),('workflow_id',13),('head_sha','b'*40),('head_branch','feature'),('event','pull_request'),('conclusion','failure'),('repository',{'id':102,'full_name':'org/repo'}),('head_repository',{'id':101,'full_name':'foreign/repo'}),('run_started_at','2026-10-15T20:00:01.1234567Z'),('updated_at','2027-01-01T00:00:00Z')]:
  badapi=API();badapi.mutate=lambda path,value,field=field,bad=bad:dict(value,**{field:bad}) if path.endswith('/runs/900') else value
  rejects(lambda:e.observe_runs(badapi,root,'main',selections,now))
 for bad in (b'{"notifications":0,"reconciled":0}\n',b'{"notifications":true,"reconciled":0}\n',b'{"notifications":0,"notifications":0,"reconciled":0}\n',b'{"notifications":0,"reconciled":0,"secret":"DO_NOT_ECHO"}\n',b'{not-json}\n',b'x'*2097153):
  badapi=API();badapi.extra=bad;rejects(lambda:e.observe_runs(badapi,root,'main',selections,now))
 for mutate in (lambda p,v:dict(v,total_count=1000) if '/attempts/' in p else v,lambda p,v:dict(v,jobs=v['jobs']*2,total_count=2) if '/attempts/' in p else v,lambda p,v:dict(v,default_branch='other') if p=='repos/org/repo' else v):
  badapi=API();badapi.mutate=mutate;rejects(lambda:e.observe_runs(badapi,root,'main',selections,now))
 badapi=API();badapi.drift=True;rejects(lambda:e.observe_runs(badapi,root,'main',selections,now))
 (root/'.claude/scripts/factory-reporting-queue.py').write_text('dirty source')
 dirty=API();rejects(lambda:e.observe_runs(dirty,root,'main',selections,now));assert dirty.calls==[]
 git('checkout','--','.claude/scripts/factory-reporting-queue.py')
 rejects(lambda:e.observe_runs(API(),root,'main',dict(selections,other={}),now))
 # Raw result lines need server timestamp provenance, not echoed JSON/caller text.
 rejects(lambda:e.results(b'{"notifications":1,"reconciled":0}\n'))
 rejects(lambda:e.results('not bytes'))
 for bad in (b'[command]/usr/bin/git version\n',b'2026-10-16T00:00:00Z [unknown]runner\n',b'2026-10-16T00:00:00Z []\n',b'2026-10-16T00:00:00Z {bad}\n',b'2026-10-16T00:00:00Z {"notifications":0,"notifications":0,"reconciled":0}\n'):
  rejects(lambda bad=bad:e.results(bad))
 # Actual bounded gh subprocess, no network: fixed-host command and stream limits.
 tools=root/'tools';tools.mkdir();stub=tools/'gh';stub.write_text('#!'+__import__('sys').executable+'\nimport json,os,sys\nprint(json.dumps({"ok":True,"args":sys.argv[1:],"slack":"FACTORY_SLACK_BOT_TOKEN" in os.environ,"writer":"FACTORY_REPORTING_STATE_TOKEN" in os.environ}))\n');stub.chmod(0o755)
 saved=dict(os.environ)
 try:
  os.environ.update(PATH=str(tools)+':'+saved['PATH'],FACTORY_SLACK_BOT_TOKEN='SLACK_SENTINEL',FACTORY_REPORTING_STATE_TOKEN='STATE_SENTINEL');transport=e.GitHub('org/repo')
  actual=transport.request('repos/org/repo');assert actual=={'ok':True,'args':['api','--hostname','github.com','--method','GET','repos/org/repo'],'slack':False,'writer':False};count+=1
  assert transport.request('repos/org/repo/git/ref/heads/release%2Fmain')['ok'] is True;count+=1
  rejects(lambda:transport.request('repos/foreign/repo'))
  rejects(lambda:transport.request('repos/org/repo','POST',{}))
  for i in range(126):transport.request('repos/org/repo')
  rejects(lambda:transport.request('repos/org/repo'))
  # Modern gh refuses terminal controls unless explicitly accepted. These bytes
  # remain bounded pipe data for hashing/parsing, never terminal output.
  stub.write_text('#!'+__import__('sys').executable+'\nimport sys\nassert "--allow-escape-sequences" in sys.argv[1:], "raw log opt-in absent"\nsys.stdout.buffer.write(b"\\x1b[32mrunner setup\\x1b[0m\\n2026-10-16T00:00:00Z {\\"notifications\\":0,\\"reconciled\\":0}\\n")\n');stub.chmod(0o755)
  captured=e.GitHub('org/repo').request('repos/org/repo/actions/jobs/100/logs',raw=True)
  assert b'\x1b[32m' in captured and e.results(captured)==[{'notifications':0,'reconciled':0}];count+=1
  rejects(lambda:e.GitHub('org/repo').request('repos/org/repo',raw=True))
  # AC-9: the retainer's exact artifact ZIP uses the same real bounded transport.
  stub.write_text('#!'+__import__('sys').executable+'\nimport sys\nassert sys.argv[1:]==["api","--hostname","github.com","--method","GET","--allow-escape-sequences","repos/org/repo/actions/artifacts/501/zip"]\nsys.stdout.buffer.write(b"PK\\x03\\x04\\x00\\xff\\x1b")\n');stub.chmod(0o755)
  assert e.GitHub('org/repo').request('repos/org/repo/actions/artifacts/501/zip',raw=True)==b'PK\x03\x04\x00\xff\x1b';count+=1
  for endpoint in ('repos/org/repo/actions/artifacts/0/zip','repos/org/repo/actions/artifacts/501/zip?x=1','repos/org/repo/actions/artifacts/501','repos/foreign/repo/actions/artifacts/501/zip'):
   rejects(lambda endpoint=endpoint:e.GitHub('org/repo').request(endpoint,raw=True))
  stub.write_text('#!'+__import__('sys').executable+'\nimport sys\nsys.stdout.write("x"*2097153)\n');stub.chmod(0o755)
  try:e.GitHub('org/repo').request('repos/org/repo/actions/jobs/100/logs',raw=True)
  except ValueError as error:assert 'output limit' in str(error);count+=1
  else:raise AssertionError('actual streamed log exceeded cap')
  stub.write_text('#!'+__import__('sys').executable+'\nimport sys\nsys.stdout.write("x"*2097152)\n');stub.chmod(0o755)
  total=e.GitHub('org/repo')
  for i in range(16):assert len(total.request('repos/org/repo/actions/jobs/100/logs',raw=True))==2097152
  rejects(lambda:total.request('repos/org/repo/actions/jobs/100/logs',raw=True))
  stub.write_text('#!/bin/sh\nprintf \'{"key":1,"key":2}\'\n');stub.chmod(0o755)
  rejects(lambda:e.GitHub('org/repo').request('repos/org/repo'))
 finally:os.environ.clear();os.environ.update(saved)
 print(f'{count} bounded reviewed-source/run/job/log observer cases passed; fixtures only, no live credit')
PY
