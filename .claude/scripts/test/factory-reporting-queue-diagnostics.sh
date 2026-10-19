#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
import importlib.util,json,os,subprocess,sys
from pathlib import Path
path=Path('.claude/scripts/factory-reporting-queue.py').resolve()
spec=importlib.util.spec_from_file_location('queue_diagnostics',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
sentinel='PRIVATE-CONTENT-/operator/private/file-and-token-value'
# Exercise the actual entrypoint with an invalid nonsecret policy flag.
result=subprocess.run([sys.executable,str(path)],env={'PATH':os.environ['PATH'],'FACTORY_REPORTING_APP_WRITER_ENABLED':'invalid'},capture_output=True,text=True)
assert result.returncode==2
assert '"phase":"entry"' in result.stderr and '"category":"guard-failed"' in result.stderr,result.stderr
assert 'Traceback' not in result.stderr
# A real configuration failure must identify its phase without serializing inputs.
try:m.build_config({'FACTORY_REPORTING_ENABLED':sentinel})
except ValueError as error:
 original=(error.args,error.__traceback__)
 value=m.failure_details(error)
 assert value=={'phase':'configuration','category':'guard-failed'},value
 assert (error.args,error.__traceback__)==original
 assert sentinel not in json.dumps(value)
else:raise AssertionError('Invalid configuration accepted')
# Metadata errors retain only known fixed codes; arbitrary exception text cannot escape.
reader=object.__new__(m._QueueReader)
try:reader.time(sentinel)
except m._QueueObservationError as error:
 value=m.failure_details(error)
 assert value=={'phase':'metadata-clock','category':'metadata-clock-invalid'},value
else:raise AssertionError('Invalid clock accepted')
for error in [m._QueueObservationError(sentinel),ValueError(sentinel),RuntimeError(sentinel)]:
 value=m.failure_details(error)
 assert set(value)=={'phase','category'} and value['phase']=='entry'
 assert sentinel not in json.dumps(value) and '/operator/' not in json.dumps(value)
 assert value['category'] in ('metadata-unknown','guard-failed','unexpected')
# Diagnostics failure itself must not expose a chained private traceback.
for target in ('json.dumps','pathlib.Path.resolve'):
 code = "import runpy,sys\nfrom unittest.mock import patch\nsys.argv=["+repr(str(path))+"]\nwith patch("+repr(target)+", side_effect=RuntimeError("+repr(sentinel)+")):\n runpy.run_path("+repr(str(path))+",run_name='__main__')\n"
 result=subprocess.run([sys.executable,'-'],input=code,env={'PATH':os.environ['PATH'],'FACTORY_REPORTING_APP_WRITER_ENABLED':'invalid'},capture_output=True,text=True)
 assert result.returncode==2 and 'diagnostic-unavailable' in result.stderr,(target,result.stderr)
 assert sentinel not in result.stderr and 'Traceback' not in result.stderr,(target,result.stderr)
# A broken diagnostic sink must still exit2 without a chained traceback.
code = "import runpy,sys\nfrom unittest.mock import patch\nsys.argv=["+repr(str(path))+"]\nwith patch('builtins.print', side_effect=RuntimeError("+repr(sentinel)+")):\n runpy.run_path("+repr(str(path))+",run_name='__main__')\n"
result=subprocess.run([sys.executable,'-'],input=code,env={'PATH':os.environ['PATH'],'FACTORY_REPORTING_APP_WRITER_ENABLED':'invalid'},capture_output=True,text=True)
assert result.returncode==2 and sentinel not in result.stderr and 'Traceback' not in result.stderr,result.stderr
# Actual run_queue unknown-observation path: preserve safe reason and no new effect.
import tempfile,copy
fixture=Path('.claude/scripts/test/factory-reporting-queue-delivery.sh').read_text().split("python3 - <<'PY'\n",1)[1].split('count=0\n',1)[0]
space={};exec(compile(fixture,'queue-diagnostic-delivery-fixture','exec'),space)
q=space['q'];api=space['API']();client=space['Client']();config=space['config'];now=space['now'];reporting=space['reporting']
with tempfile.TemporaryDirectory() as folder:
 hosted=space['ns'];delivered=hosted['m'].run(dict(hosted['config'],attachments_enabled=False),hosted['ReportAPI'](),api,client,Path(folder)/'worker.sqlite',now)
 assert delivered['status']=='delivered'
 storage={'state_branch':'factory-reporting-state','bootstrap_sha':api.head,'initialize':True,'policy_approvals':{}}
 store=q.QueueStore(api,config,storage)
 empty={k:config[k] for k in ('repository','branch','destination','team_id')};empty.update(schema_version=1,stream=q.stream(config),events=[])
 store.checkpoint(None,empty);before=api.head;posts=client.posts
 original=q.observe_queue
 try:
  for reason in ('protected-reporting-health-not-current','run-list-capacity',sentinel):
   q.observe_queue=lambda *args,reason=reason:{'status':'unknown','reason':reason}
   try:q.run_queue(api,client,config,storage,reporting,now)
   except ValueError as error:
    details=q.failure_details(error)
    assert details['category']==(reason if reason!=sentinel else 'metadata-unknown'),details
    assert str(error)=='queue metadata unknown; no notification or recovery proof'
    assert api.head==before and client.posts==posts and sentinel not in json.dumps(details)
   else:raise AssertionError('Unknown observation permitted delivery')
 finally:q.observe_queue=original
 # A checkpoint failure nested in its real _load must keep write context visible.
 def unavailable(*args,**kwargs):raise ValueError(sentinel)
 store.request=unavailable
 try:store.checkpoint(empty,empty)
 except ValueError as error:
  assert q.failure_details(error)['phase']=='journal-checkpoint',q.failure_details(error)
 else:raise AssertionError('Invalid checkpoint accepted')
print('Actual blocked entrypoint and fixed phase/category diagnostics PASS; private strings, paths and traceback remain absent')
PY
