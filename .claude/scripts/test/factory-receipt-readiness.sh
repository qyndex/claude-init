#!/usr/bin/env bash
# Spec014 AC-1/2/5/6/7/8: readiness is observed proof, never a declaration.
set -euo pipefail
cd "$(dirname "$0")/../../.."
"${FACTORY_TEST_PYTHON:-python3}" - <<'PYTEST'
from pathlib import Path
import importlib.util,json,subprocess,sys,tempfile,os
scripts=Path('.claude/scripts').resolve()
s=importlib.util.spec_from_file_location('readiness',scripts/'factory-preflight.py');p=importlib.util.module_from_spec(s);s.loader.exec_module(p)
with tempfile.TemporaryDirectory() as temporary:
 path=Path(temporary)/'policy.json';path.write_text('{}')
 old=subprocess.run([sys.executable,str(scripts/'factory-preflight.py'),'--policy',str(path)],capture_output=True,text=True)
 assert old.returncode==1 and set(json.loads(old.stdout))=={'ready','missing'},old
 assert 'operator-approved policy activation' in json.loads(old.stdout)['missing']
 for flag,state_repo in (('false','org/repo'),('TRUE','org/repo'),('true','foreign/repo'),('true','org/repo')):
  env={'PATH':os.environ.get('PATH',''),'GITHUB_REPOSITORY':'org/repo','FACTORY_REPORTING_STATE_REPOSITORY':state_repo,
       'FACTORY_REPORTING_APP_WRITER_ENABLED':flag,'FACTORY_REPORTING_APP_ID':'7'}
  child=subprocess.run([sys.executable,str(scripts/'factory-preflight.py'),'--reporting-config',str(path)],env=env,capture_output=True,text=True)
  assert child.returncode==1 and json.loads(child.stdout)['checks']['configuration']['status']=='failed',child
  assert 'ready' not in json.loads(child.stdout)
 incomplete=subprocess.run([sys.executable,str(scripts/'factory-preflight.py'),'--reporting-config',str(path),'--interval-end','2026-10-15T23:00:00Z'],capture_output=True,text=True)
 assert incomplete.returncode==2 and 'all three interval selectors' in incomplete.stderr,incomplete
assert callable(getattr(p,'reporting_readiness',None)), 'preflight has no read-only reporting readiness composition'
fixture=Path('.claude/scripts/test/factory-receipt-coverage-batch.sh').read_text()
for marker in ("<<'PY'\n", "\ncases=r'''\n", ' assert batch_calls,'):
 assert fixture.count(marker)==1,'coverage fixture splice marker changed: '+repr(marker)
source=fixture.split("<<'PY'\n",1)[1]
prefix=source.split("\ncases=r'''",1)[0]
setup=source.split("\ncases=r'''\n",1)[1].split(' assert batch_calls,',1)[0]
cases=r'''
 ps=importlib.util.spec_from_file_location('actual_preflight',scripts/'factory-preflight.py');pre=importlib.util.module_from_spec(ps);ps.loader.exec_module(pre)
 config={'repository':'org/repo','receipt_policy':policy,'receipt_archive':{'approval_path':str(approval),'trust_path':str(trust),'store':store,'trust_mode':'profile'}}
 before=out('rev-parse',ref);approval_bytes=approval.read_bytes();trust_bytes=trust.read_bytes()
 class ReadState(PipelineState):
  def request(self,path,method='GET',payload=None):
   assert method=='GET' and payload is None,'readiness attempted a state mutation'
   return super().request(path,method,payload)
 def check(source=runs,state=None):
  return pre.reporting_readiness(config,source,state or ReadState(),interval_end=end,history_head=context['history'],campaign=campaign,page_size=1)
 def passed(value,key):return value['checks'][key]['status']=='passed'
 class Unavailable(ReadState):
  def request(self,path,method='GET',payload=None):
   raise RuntimeError('private provider diagnostic must not reach JSON')
 unavailable=check(state=Unavailable())
 assert unavailable['checks']['protected_origin']['status']=='failed',unavailable
 assert 'private provider diagnostic' not in json.dumps(unavailable)
 # Synthetic local SQLite failure at the actual reconstruction boundary.
 import sqlite3
 from unittest.mock import patch
 with patch('sqlite3.connect',side_effect=sqlite3.OperationalError('private database diagnostic')):
  database_failure=check()
 assert database_failure['checks']['retained_interval']['status']=='failed',database_failure
 assert 'private database diagnostic' not in json.dumps(database_failure)
 for item in sources:item.expired=True
 result=check();assert passed(result,'protected_origin') and passed(result,'retained_interval'),result
 assert all(result['checks'][name]['status']=='not_checked' for name in ('installed_app','private_capability','native_cadence','operator_cutover')),result
 assert 'ready' not in result,'local proof claims overall activation readiness'
 assert out('rev-parse',ref)==before and approval.read_bytes()==approval_bytes and trust.read_bytes()==trust_bytes
 local=pre.reporting_readiness(config,runs,ReadState());assert passed(local,'protected_origin') and local['checks']['retained_interval']['status']=='not_checked'
 wrong=pre.reporting_readiness(config,runs,ReadState(),interval_end=end,history_head=context['history'],campaign='f'*64,page_size=1)
 assert wrong['checks']['retained_interval']['status']=='failed',wrong
 changed=json.loads(trust_bytes);changed['profiles'][0]['status']='revoked';trust.write_text(json.dumps(changed))
 assert check()['checks']['protected_origin']['status']=='failed','zero active profiles accepted for readiness'
 current=copy.deepcopy(changed['profiles'][0]);current.update(id='current-active',status='active');changed['profiles'].append(current);trust.write_text(json.dumps(changed))
 withdrawn=check();assert passed(withdrawn,'retained_interval'),withdrawn
 trust.write_bytes(trust_bytes)
 class Changed(Runs):
  def request(self,target,**kwargs):
   value=super().request(target,**kwargs)
   if '/actions/workflows/' in target and value['workflow_runs']:value['workflow_runs'][0]['repository']['id']=999
   return value
 assert check(source=Changed())['checks']['retained_interval']['status']=='failed'
 broken=json.loads(approval_bytes);broken['private']=True;approval.write_text(json.dumps(broken))
 assert check()['checks']['protected_origin']['status']=='failed';approval.write_bytes(approval_bytes)
 class TrustRace(ReadState):
  def read_pull_requests(self,repo,numbers):
   value=super().read_pull_requests(repo,numbers);trust.write_bytes(trust_bytes+b' ');return value
 raced=check(state=TrustRace());assert raced['checks']['retained_interval']['status']=='failed',raced;trust.write_bytes(trust_bytes)
 assert out('rev-parse',ref)==before,'readiness changed protected Git state'
 print('PASS actual expired-artifact retained proof, withdrawn annotations, foreign/private/race negatives; GET-only state')
'''
exec(compile(prefix+"\ncases=r'''\n"+setup+cases+"\n'''\nexec(compile(fixture+pipeline+cases,'readiness-real-git','exec'))\n",'readiness-wrapper','exec'))
PYTEST
