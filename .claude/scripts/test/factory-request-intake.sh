#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
if [ "${1:-all}" = start-guard ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-start-guard.sh"
fi
if [ "${1:-all}" = enqueue-guard ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-enqueue-guard.sh"
fi
if [ "${1:-all}" = proposal ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-proposal.sh"
fi
if [ "${1:-all}" = continuation-freshness ]; then
  for suite in session-continuation clarification-revisions decision-freshness approval-eligibility; do bash "$0" "$suite"; done
  exit 0
fi
if [ "${1:-all}" = approval-eligibility ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-approval-eligibility.sh"
fi
if [ "${1:-all}" = decision-freshness ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-decision-freshness.sh"
fi
if [ "${1:-all}" = clarification-revisions ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-clarification-revisions.sh"
fi
if [ "${1:-all}" = session-continuation ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-session-continuation.sh"
fi
if [ "${1:-all}" = flat-root ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-flat-root.sh"
fi
if [ "${1:-all}" = contract-catalog ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-contract-catalog.sh"
fi
if [ "${1:-all}" = proposed-scope ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-proposed-scope.sh"
fi
if [ "${1:-all}" = assessment-outcome ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-outcome.sh"
fi
if [ "${1:-all}" = assessment-process ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-process.sh"
fi
if [ "${1:-all}" = assessment-profile ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-profile.sh"
fi
if [ "${1:-all}" = context ]; then
  exec bash "$ROOT/.claude/scripts/test/factory-intake-context.sh"
fi
if [ "${1:-all}" = all ]; then
  for suite in contract migration schema identity pending lightweight context assessment-profile assessment-process assessment-outcome proposed-scope contract-catalog flat-root session-continuation clarification-revisions decision-freshness approval-eligibility proposal enqueue-guard start-guard; do bash "$0" "$suite"; done
  exit 0
fi
case "${1:-all}" in contract|migration|schema|identity|pending|lightweight) ;; *) echo "Unknown intake test selector" >&2; exit 2 ;; esac
python3 - "$ROOT" "${1:-all}" <<'PY'
import copy,hashlib,importlib.util,json,os,sqlite3,sys,tempfile
from pathlib import Path
root=Path(sys.argv[1]);case=sys.argv[2];helper=root/'.claude/scripts/factory-intake.py'
assert helper.is_file(),'private request intake controller absent'
s=importlib.util.spec_from_file_location('intake',helper);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
def reject(fn):
 try:fn()
 except (ValueError,OSError,sqlite3.Error):return
 raise AssertionError('unsafe intake accepted')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory() as d:
 base=Path(d).resolve();account_home=base/'os-account';account_home.mkdir(mode=0o700)
 import pwd
 pwd.getpwuid=lambda uid: type('Account',(),{'pw_dir':str(account_home)})()
 private=base/'private';private.mkdir(mode=0o700);candidate=base/'candidate';candidate.mkdir();authority=base/'authority';authority.mkdir()
 for name in ['policy.json','profile.json']:
  (private/name).write_text('{}');(private/name).chmod(0o600)
 contract={'schema_version':1,'enabled':True,'repository':'fixture/intake','candidate_root':str(candidate),'authority_root':str(authority),'database':str(private/'runtime.sqlite'),'profile':str(private/'profile.json'),'policy':str(private/'policy.json'),'trusted_files':{str(helper):sha(helper),str(helper.with_name('factory-runtime.py')):sha(helper.with_name('factory-runtime.py')),str(private/'policy.json'):sha(private/'policy.json'),str(private/'profile.json'):sha(private/'profile.json')},'limits':{'request_chars':20000,'context_bytes':500000,'output_bytes':65536,'assessment_seconds':60}}
 config=private/'intake.json'
 def save(doc=contract):config.write_text(json.dumps(doc));config.chmod(0o600)
 save()
 # AC-9, AC-12, AC-14 private configuration and budgets
 if case in {'all','contract'}:
  observed=m.load_contract(config);assert observed==contract
  neutral={key:None for key in contract};neutral.update(schema_version=1,enabled=False,trusted_files={},limits=contract['limits']);m.validate_contract(neutral)
  for field,value in [('enabled',1),('repository','foreign'),('candidate_root',str(private)),('database',str(candidate/'state.sqlite')),('schema_version',True)]:
   changed=copy.deepcopy(contract);changed[field]=value;save(changed);reject(lambda:m.load_contract(config))
  save();config.chmod(0o644);reject(lambda:m.load_contract(config));save()
  linked=private/'linked.json';linked.symlink_to(config);reject(lambda:m.load_contract(linked));linked.unlink()
  linked=private/'hard.json';os.link(config,linked);reject(lambda:m.load_contract(config));linked.unlink()
  for field,value in [('request_chars',20001),('context_bytes',500001),('output_bytes',65537),('assessment_seconds',61),('request_chars',True)]:
   changed=copy.deepcopy(contract);changed['limits'][field]=value;save(changed);reject(lambda:m.load_contract(config))
  save();(private/'policy.json').write_text('{"changed":true}');reject(lambda:m.load_contract(config));(private/'policy.json').write_text('{}')
  save();config.write_text('{"schema_version":1,"schema_version":1}');reject(lambda:m.load_contract(config));save()
  print('contract: neutral OFF, private canonical paths, finite budgets, exact pins and hostile overrides passed')

 # AC-9, AC-11 additive state and durable pause
 if case in {'all','migration'}:
  assert hasattr(m,'Intake'),'durable private intake schema absent'
  save();store=m.Intake(config)
  with sqlite3.connect(private/'runtime.sqlite') as db:
   assert db.execute('SELECT repository,version,paused FROM intake_identity').fetchall()==[('fixture/intake',1,0)]
   assert {'intake_sessions','intake_requests','intake_pending_native','intake_actions','intake_events'}<={r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
   db.execute('CREATE TABLE preserved (value TEXT)');db.execute("INSERT INTO preserved VALUES ('private existing state')")
  reopened=m.Intake(config)
  with reopened.transaction() as db:assert db.execute('SELECT value FROM preserved').fetchone()[0]=='private existing state'
  assert (private/'runtime.sqlite').stat().st_mode&0o777==0o600
  changed=copy.deepcopy(contract);changed['repository']='foreign/repo';save(changed);reject(lambda:m.Intake(config));save()
  with sqlite3.connect(private/'runtime.sqlite') as db:db.execute('UPDATE intake_identity SET version=99')
  reject(lambda:m.Intake(config))
  with sqlite3.connect(private/'runtime.sqlite') as db:db.execute('UPDATE intake_identity SET version=1');db.execute('CREATE TRIGGER bad AFTER INSERT ON preserved BEGIN UPDATE intake_identity SET paused=0; END')
  reject(lambda:m.Intake(config))
  with sqlite3.connect(private/'runtime.sqlite') as db:db.execute('DROP TRIGGER bad')
  reopened.pause()
  reject(lambda:reopened.ready())
  reject(lambda:m.Intake(config).ready())
  print('migration: additive private schema preserves existing bytes; foreign/version/trigger state rejects and pause survives restart')

 # AC-3, AC-6, AC-7 strict disposition and action contracts
 if case in {'all','schema'}:
  assert hasattr(m,'validate_request'),'strict intake request schemas absent'
  request={'schema_version':1,'source_kind':'claude','origin':'human','session':'session-1','submission_key':None,'delivery_token':None,'source_revision':'1','parent_request':None,'actor':'local-operator','repository':'fixture/intake','ref':'a'*40,'text':'Add login'}
  m.validate_request(request,contract['limits'])
  for change in [{'extra':True},{'origin':'agent'},{'schema_version':True},{'source_kind':'github'},{'text':'x'*20001},{'actor':None},{'parent_request':'../bad'}]:reject(lambda change=change:m.validate_request({**request,**change},contract['limits']))
  reject(lambda:m.decode('{"a":1,"a":2}'));reject(lambda:m.decode('{"a":NaN}'))
  decision={'schema_version':1,'request_id':'a'*32,'revision':'b'*64,'disposition':'new_feature','intents':[{'kind':'new_feature','summary':'Add login','scope':['src/login.py']}],'rationale':'New scope','evidence':[],'uncertainty':'none','spec':None,'plan':None,'task':None,'next_action':'draft','blocked_reason':None}
  m.validate_decision(decision)
  for change in [{'next_action':'resume'},{'extra':1},{'intents':[]},{'revision':'wrong'},{'evidence':[{'kind':'repository','ref':'../secret','sha256':'a'*64}]}]:reject(lambda change=change:m.validate_decision({**decision,**change}))
  mixed={**decision,'disposition':'existing_approved','next_action':'resume','spec':'specs/active/001-a.md','plan':'plans/active/001-a.md','task':'T-1','intents':[{'kind':'existing_approved','summary':'continue','scope':[]},{'kind':'new_feature','summary':'also login','scope':['src/login.py']}]}
  reject(lambda:m.validate_decision(mixed))
  action={'schema_version':1,'request_id':'a'*32,'revision':'b'*64,'decision_sha256':'c'*64,'kind':'proposal_publish','target':'specs/active/001-a.md','target_revision':'d'*64,'stage':'draft','paths':['specs/active/001-a.md'],'principal':None,'fence':None}
  m.validate_action(action)
  for change in [{'kind':'approve'},{'paths':['../secret']},{'fence':True},{'extra':1}]:reject(lambda change=change:m.validate_action({**action,**change}))
  print('schema: exact request/decision/action fields, duplicate/nonfinite data, mixed-scope resume and unsafe paths reject')

 # AC-2, AC-9 submission and retry identity
 if case in {'all','identity'}:
  assert hasattr(m.Intake,'submit_console'),'transactional console identity allocation absent'
  save();store=m.Intake(config);session=store.new_session()
  first=store.submit_console(session,'continue','a'*40);second=store.submit_console(session,'continue','a'*40)
  assert first['request_id']!=second['request_id'] and first['revision']!=second['revision']
  same=store.submit_console(session,'continue','a'*40,delivery_token=first['delivery_token']);assert same==first
  reject(lambda:store.submit_console(session,'add login','a'*40,delivery_token=first['delivery_token']))
  reject(lambda:store.submit_console(session,'continue','b'*40,delivery_token=first['delivery_token']))
  reject(lambda:store.submit_console(store.new_session(),'continue','a'*40,delivery_token=first['delivery_token']))
  reject(lambda:store.submit_console(session,'continue','a'*40,delivery_token='invented'))
  reject(lambda:store.submit_console(session,'x'*20001,'a'*40))
  from concurrent.futures import ThreadPoolExecutor
  with ThreadPoolExecutor(max_workers=4) as pool:
   results=list(pool.map(lambda unused:m.Intake(config).submit_console(session,'continue','a'*40,delivery_token=first['delivery_token']),range(8)))
  assert all(value==first for value in results)
  with store.transaction() as db:
   assert db.execute('SELECT count(*) FROM intake_requests').fetchone()[0]==2
   assert db.execute('SELECT sequence FROM intake_sessions WHERE id=?',(session,)).fetchone()[0]==2
   docs=[json.loads(row[0]) for row in db.execute('SELECT document FROM intake_requests')]
   assert [x['source_revision'] for x in docs]==['1','2'] and all(x['actor']=='local:'+str(os.getuid()) for x in docs)
  assert m.Intake(config).submit_console(session,'continue','a'*40,delivery_token=first['delivery_token'])==first
  print('identity: identical human submissions remain distinct; trusted-token concurrent/restart retry is idempotent; conflicts have no new effect')

 # AC-1, AC-2 human ingress correlation
 if case in {'all','pending'}:
  assert hasattr(m.Intake,'bind_native'),'one-shot native ingress binding absent'
  save();store=m.Intake(config);session=store.new_session();first=store.submit_console(session,'continue','a'*40)
  pending=store.bind_native(first['request_id'],now=100)
  assert set(pending)=={'native_session','launch_nonce'}
  reject(lambda:store.consume_native(pending['native_session'],'continue',authority,now=101))
  reject(lambda:store.consume_native(pending['native_session'],'add login',candidate,now=101))
  reject(lambda:store.consume_native('invented','continue',candidate,now=101))
  reject(lambda:store.bind_native(first['request_id'],now=101))
  second=store.submit_console(session,'continue','a'*40)
  reject(lambda:store.bind_native(second['request_id'],now=101))
  assert store.consume_native(pending['native_session'],'continue',candidate,now=101)==first['request_id']
  reject(lambda:store.consume_native(pending['native_session'],'continue',candidate,now=101))
  next_pending=store.bind_native(second['request_id'],now=102)
  reject(lambda:store.consume_native(next_pending['native_session'],'continue',candidate,now=193))
  reject(lambda:m.Intake(config).bind_native(second['request_id'],now=194))
  with store.transaction() as db:assert db.execute('SELECT count(*) FROM intake_requests').fetchone()[0]==2
  print('pending: exact session/cwd/digest match consumes once; generated/conflicting callbacks cannot allocate; lost or expired ingress fences replay')

 # AC-3, AC-4, AC-7, AC-11, AC-12 lightweight route selection
 if case in {'all','lightweight'}:
  assert hasattr(m.Intake,'lightweight'),'lightweight intake routes absent'
  (private/'policy.json').write_text(json.dumps({'repository':'fixture/intake','specs':{}}));contract['trusted_files'][str(private/'policy.json')]=sha(private/'policy.json')
  save();store=m.Intake(config);session=store.new_session()
  def route(text):
   receipt=store.submit_console(session,text,'a'*40);return store.lightweight(receipt['request_id'])
  for text,expected,action in [('how does this work?','answer','answer'),('status','status','inspect'),('continue','clarify','question'),('skip the gates','risk_control','question')]:
   result=route(text);assert result['disposition']==expected and result['next_action']==action,result
  assert route('add login') is None and route('continue and add login') is None and route('fix it') is None
  (authority/'specs/active').mkdir(parents=True);(authority/'plans/active').mkdir(parents=True);(authority/'tasks').mkdir()
  spec=authority/'specs/active/001-fixture.md';spec.write_text('---\nid: 001\nstatus: approved\n---\n**AC-1**: fixture\n')
  plan=authority/'plans/active/001-fixture.md';plan.write_text('---\nstatus: approved\nspec: specs/active/001-fixture.md\n---\n')
  ledger=authority/'tasks/TASKS.md';ledger.write_text('## Active\n- [ ] T-1 | spec:001 | deps:\n')
  policy={'repository':'fixture/intake','specs':{'001':{'path':'specs/active/001-fixture.md','sha256':sha(spec),'ac_ids':['AC-1'],'allowed_paths':['src/*']}}}
  (private/'policy.json').write_text(json.dumps(policy));contract['trusted_files'][str(private/'policy.json')]=sha(private/'policy.json');save()
  # A protected contract change is a new explicitly configured fixture installation, never implicit rebind.
  (private/'runtime.sqlite').unlink();store=m.Intake(config);session=store.new_session()
  assert route('continue')['disposition']=='clarify'
  yes=route('continue T-1');assert yes['disposition']=='existing_approved' and yes['task']=='T-1' and yes['next_action']=='resume',yes
  assert store.lightweight(yes['request_id'])==yes
  ledger.write_text(ledger.read_text()+'- [ ] T-2 | spec:001 | deps:\n');assert route('continue')['task']=='T-1'
  ledger.write_text('## Active\n- [ ] T-1 | spec:001 | deps:\n');spec.write_text(spec.read_text()+'changed');assert route('continue')['disposition']=='clarify'
  stopped=route('stop');assert stopped['next_action']=='stop';reject(lambda:store.submit_console(session,'continue','a'*40))
  with store.transaction() as db:assert db.execute('SELECT sum(assessment_count) FROM intake_requests').fetchone()[0]==0
  print('lightweight: answer/status use zero assessments; explicit eligible session task resolves; unbound/stale scope clarifies; mixed scope needs Scout and stop pauses')
PY
