#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
# AC-1, AC-2, AC-4, AC-10: trusted foreground logical console ingress.
import sys
from pathlib import Path
root=Path(sys.argv[1])
console=root/'.claude/scripts/factory-intake-console.py'
assert console.is_file(), 'protected foreground console entry is absent'
# Reuse maintained protected real-Git/fake-assessor builder, not classifier mocks.
fixture=(root/'.claude/scripts/test/factory-intake-proposed-scope.sh').read_text().split("<<'PY'\n",1)[1].rsplit("\nPY",1)[0]
fixture=fixture.split(' # AC-3, AC-6, AC-7:',1)[0]
fixture=fixture.replace("assert set(context['request'])=={'text','repository','ref','request_id','revision'}", "assert {'text','repository','ref','request_id','revision'}<=set(context['request'])<={'text','repository','ref','request_id','revision','proposal'}")
fixture=fixture.replace("with sqlite3.connect(Path(__file__).with_name('runtime.sqlite'),timeout=.1) as db:db.execute('BEGIN IMMEDIATE');db.rollback()","with sqlite3.connect(Path(__file__).with_name('runtime.sqlite'),timeout=.1) as db:\n row=db.execute('SELECT document FROM intake_requests WHERE id=?',(context['request']['request_id'],)).fetchone()\n assert row is not None and json.loads(row[0])['text']==mode,'assessment preceded immutable request commit'\n db.execute('BEGIN IMMEDIATE');db.rollback()")
fixture=fixture.replace('pins=[controller,', 'pins=[console,controller,controller.with_name(\'factory-ledger.py\'),')
fixture=fixture.replace(" policy={'repository'"," profile['mandatory_intake']={'required':True,'contract':str(private/'intake.json'),'database':str(private/'runtime.sqlite')};save()\n policy={'repository'",1)
tail=r"""
 import runpy
 driver=private/'console-driver.py'
 driver.write_text(runpy.run_path(str(root/'.claude/scripts/test/intake-private-diagnostics.py'))['driver_prefix']('console')+'import pwd,runpy,sys\nfrom types import SimpleNamespace\npwd.getpwuid=lambda uid:SimpleNamespace(pw_dir='+repr(str(account_home))+')\nentry=sys.argv.pop(1);sys.argv[0]=entry;runpy.run_path(entry,run_name=\"__main__\")\n')
 def foreground(lines,*args,success=True,sanitized=False):
  command=[str(Path(sys.executable).resolve()),'-I','-S',str(driver),str(console),'--root',str(candidate),*args]
  process=subprocess.run(command,input=lines,text=True,capture_output=True,timeout=60,env={'PATH':'/usr/bin:/bin','HOME':'/attacker','LANG':'C','LC_ALL':'C','FACTORY_PLANNING_CLAUDE_OAUTH_TOKEN':'fixture-planning'})
  assert (process.returncode==0)==success,process.stderr
  if sanitized:
   assert process.returncode==2 and process.stderr=='Console blocked by protected ingress checks.\n',process.stderr
   assert process.stdout=='',process.stdout
  return [json.loads(line) for line in process.stdout.splitlines()]
 records=foreground('status\nstatus\npropose:src/login.py\n')
 assert records[0]['event']=='session' and records[0]['native_delivery']=='unavailable'
 current=records[0]['session'];turns=records[1:]
 assert len(turns)==3 and turns[0]['disposition']==turns[1]['disposition']=='status'
 assert turns[0]['receipt']['request_id']!=turns[1]['receipt']['request_id'],'same-text submissions collapsed'
 assert turns[2]['disposition']=='new_feature' and turns[2]['next_action']=='draft',turns[2]
 assert turns[2]['native_delivery']=='unavailable' and not (candidate/'src/login.py').exists()
 repeated=foreground('status\n','--session',current,'--retry-token',turns[0]['receipt']['delivery_token'])
 assert repeated[1]['receipt']==turns[0]['receipt'],'exact issued retry minted new request'
 foreground('changed text\n','--session',current,'--retry-token',turns[0]['receipt']['delivery_token'],success=False)
 resumed=foreground('how does this work?\n','--session',current)
 assert resumed[0]['session']==current and resumed[1]['disposition']=='answer'
 foreign=store.new_session()
 foreground('clarify\n','--session',foreign,'--parent',turns[2]['receipt']['request_id'],success=False)
 linked=foreground('clarify\n','--session',current,'--parent',turns[2]['receipt']['request_id'])
 assert linked[1]['next_action']=='question',linked[1]
 with store.transaction() as db:
  previous=db.execute('SELECT document FROM intake_requests WHERE id=?',(turns[2]['receipt']['request_id'],)).fetchone()[0]
  child=db.execute('SELECT document FROM intake_requests WHERE id=?',(linked[1]['receipt']['request_id'],)).fetchone()[0]
  assert json.loads(child)['parent_request']==turns[2]['receipt']['request_id']
  assert json.loads(previous)['text']=='propose:src/login.py'
  for record in turns:
   document=json.loads(db.execute('SELECT document FROM intake_requests WHERE id=?',(record['receipt']['request_id'],)).fetchone()[0])
   assert document['actor']=='local:'+str(os.getuid()) and document['repository']=='fixture/intake'
   assert document['ref']==ref and document['session']==current
  assert db.execute('SELECT assessment_count FROM intake_requests WHERE id=?',(turns[0]['receipt']['request_id'],)).fetchone()[0]==0
  assert db.execute('SELECT assessment_count FROM intake_requests WHERE id=?',(turns[2]['receipt']['request_id'],)).fetchone()[0]==1
  assert db.execute('SELECT count(*) FROM intake_task_starts').fetchone()[0]==0
  assert db.execute('SELECT count(*) FROM intake_pending_native').fetchone()[0]==0,'unsupported delivery fabricated pending consumption'
 foreground('status\n','--session','0'*32,success=False)
 saved=intake_config.read_bytes();changed=json.loads(saved);changed['enabled']=False;intake_config.write_text(json.dumps(changed))
 foreground('status\n',success=False)
 intake_config.write_bytes(saved)
 # AC-10: malformed authenticated contracts and real SQLite failures sanitize
 # diagnostics and never assess or launch dependent work.
 registry=account_home/'.local/state/factory-required-intake/registry.json'
 latch=account_home/'.factory-intake-required'
 saved_registry=registry.read_bytes();saved_latch=latch.read_bytes()
 before_count=(private/'count').read_bytes()
 for malformed in ([] if os.environ.get('CONSOLE_FAILURE_CASE')=='database' else [[],None]):
  intake_config.write_text(json.dumps(malformed))
  binding=hashlib.sha256(core.canonical(malformed).encode()).hexdigest()
  registered=json.loads(saved_registry);registered['roots'][str(authority)]['contract_sha256']=binding
  latched=json.loads(saved_latch);latched['bindings'][str(authority)]=binding
  registry.write_text(json.dumps(registered));latch.write_text(json.dumps(latched))
  foreground('new feature\n',success=False,sanitized=True)
  assert (private/'count').read_bytes()==before_count
 intake_config.write_bytes(saved);registry.write_bytes(saved_registry);latch.write_bytes(saved_latch)
 database=private/'runtime.sqlite'
 database_saved=database.read_bytes();database.write_bytes(b'private-database-failure-marker')
 foreground('new feature\n',success=False,sanitized=True)
 assert database.read_bytes()==b'private-database-failure-marker'
 assert (private/'count').read_bytes()==before_count
 database.write_bytes(database_saved)
 print('console: real foreground stdin/subprocess, protected registry, distinct/retried ingress, logical resume and private proposal lineage; native delivery unavailable, no task launch')
"""
exec(compile(fixture+tail,'console-fixture','exec'))
PYTEST
