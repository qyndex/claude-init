#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
import copy,importlib.util,json,tempfile
from pathlib import Path
from unittest.mock import patch
fixture=Path('.claude/scripts/test/factory-reporting-queue-delivery.sh').read_text().split("python3 - <<'PY'\n",1)[1].split('count=0\n',1)[0]
s={};exec(compile(fixture,'worker-diagnostic-fixture','exec'),s)
q=s['q'];api=s['API']();client=s['Client']();config=s['config'];now=s['now'];reporting=s['reporting']
private='PRIVATE-worker-payload-/private/operator-token'
with tempfile.TemporaryDirectory() as folder:
 hosted=s['ns'];assert hosted['m'].run(dict(hosted['config'],attachments_enabled=False),hosted['ReportAPI'](),api,client,Path(folder)/'worker.sqlite',now)['status']=='delivered'
 storage={'state_branch':'factory-reporting-state','bootstrap_sha':api.head,'initialize':True,'policy_approvals':{}}
 before=api.head;posts=client.posts
 original=importlib.util.spec_from_file_location
 for stage in ('load','parse','schema','origin'):
  thrown=ValueError(private)
  def spec(name,path,*args,**kwargs):
   result=original(name,path,*args,**kwargs)
   if name=='queue_alert_runtime':
    loader=result.loader
    class Loader:
     def create_module(self,spec):return loader.create_module(spec)
     def exec_module(self,module):
      loader.exec_module(module);state=module.state
      if stage=='load':
       def fail(*args,**kwargs):raise thrown
       state.GitState=fail
      elif stage=='parse':
       real=state.GitState
       def malformed(*args,**kwargs):
        value=real(*args,**kwargs);value.bytes=b'{"private":"'+private.encode()+b'"';return value
       state.GitState=malformed
      elif stage=='schema':
       def fail(*args,**kwargs):raise thrown
       state.validate=fail
    result.loader=Loader()
   return result
  candidate=dict(reporting,start='2026-10-02T00:00:00Z') if stage=='origin' else reporting
  with patch('importlib.util.spec_from_file_location',side_effect=spec):
   try:q.run_queue(api,client,config,storage,candidate,now)
   except ValueError as error:
    details=q.failure_details(error)
    assert details=={'phase':'worker-checkpoint','category':'worker-'+stage+'-invalid'},(stage,details)
    if stage in ('load','schema'):assert error is thrown and error.args==(private,)
    if stage=='origin':assert str(error)=='queue reporting origin differs from protected worker'
    assert private not in json.dumps(details) and 'Traceback' not in json.dumps(details)
    assert api.head==before and client.posts==posts,'diagnostic failure caused an effect'
   else:raise AssertionError('worker guard permitted effects: '+stage)
 # An arbitrary exception carrying a lookalike attribute is not a worker diagnostic.
 forged=ValueError(private);forged._queue_worker_stage='origin'
 assert q.failure_details(forged)=={'phase':'entry','category':'guard-failed'}
print('Four real worker stage failures remain blocked without effects or private diagnostics; exception identity retained')
PY
