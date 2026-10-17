#!/usr/bin/env bash
# Spec014 AC-2/6/7/8: real retained Git proof feeds typed reporting projection.
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
from pathlib import Path
import importlib.util,json
render_spec=importlib.util.spec_from_file_location('render_unit',Path('.claude/scripts/factory-slack-digest.py'));render_module=importlib.util.module_from_spec(render_spec);render_spec.loader.exec_module(render_module)
render_fixture={'repository':'org/repo','display_from':'start','display_until':'end','merges':[{'pr':7,'title':'Feature','merge_sha':'b'*40,'delivery_evidence':[{'task':'T-1','spec':'001','producer_run':20}],'evidence_status':'authenticated'}]}
legacy_text=render_module.render(json.dumps(render_fixture))
assert legacy_text == 'Factory delivery — org/repo\nstart to end (Australia/Sydney)\nMerged PRs: 1; product acceptance remains separate.\n#7 Feature — T-1/spec 001\nhttps://github.com/org/repo/pull/7 — merge bbbbbbbbbbbb\nEvidence: https://github.com/org/repo/actions/runs/20\nMissing historical check records are not treated as a pass.'
render_fixture['merges'][0]['evidence_status']='withdrawn'
withdrawn_text=render_module.render(json.dumps(render_fixture))
assert 'WITHDRAWN' in withdrawn_text and 'T-1/spec 001' in withdrawn_text and '/actions/runs/20' in withdrawn_text,withdrawn_text
print('PASS actual renderer explicitly labels withdrawn evidence while preserving proof attribution')
fixture_source=Path('.claude/scripts/test/factory-receipt-coverage-batch.sh').read_text()
for marker in ("<<'PY'\n", "\ncases=r'''\n", ' assert batch_calls,'):
 assert fixture_source.count(marker)==1, 'coverage fixture splice marker changed: '+repr(marker)
# AC-2: fixed legacy bytes and pending immutability do not depend on durable mode.
import tempfile,sqlite3
unit_spec=importlib.util.spec_from_file_location('digest_unit',Path('.claude/scripts/factory-digest.py'));unit=importlib.util.module_from_spec(unit_spec);unit_spec.loader.exec_module(unit)
with tempfile.TemporaryDirectory() as temporary:
 path=Path(temporary)/'legacy.sqlite'
 for mode in ('',None,'DURABLE',True,[]):
  try:unit.Digest(path,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode=mode)
  except ValueError:pass
  else:raise AssertionError('invalid receipt mode accepted: '+repr(mode))
 view=unit.Digest(path,'org/repo','C1','2026-10-15T00:00:00Z')
 assert view.receipt_mode=='legacy'
 with sqlite3.connect(path) as db:
  db.execute('CREATE TABLE delivery_receipts(task TEXT PRIMARY KEY, revision TEXT NOT NULL, receipt TEXT NOT NULL)')
  db.execute('CREATE TABLE delivery_provenance(task TEXT PRIMARY KEY, provenance TEXT NOT NULL)')
  receipt={'repository':'org/repo','pr':7,'merge_sha':'b'*40}
  proof={'run_id':20,'artifact_digest':'sha256:'+'d'*64,'receipt':{'repository':'org/repo','pull_request':7,'merged':True,'eligible':True,'merge_sha':'b'*40,'head_sha':'c'*40,'spec_sha256':'a'*64,'task_ids':['T-9'],'spec':'014'}}
  db.execute('INSERT INTO delivery_receipts VALUES(?,?,?)',('T-9','a'*64,json.dumps(receipt)))
  db.execute('INSERT INTO delivery_provenance VALUES(?,?)',('T-9',json.dumps(proof)))
 class UnitAPI:
  repo='org/repo'
  def request(self,*args,**kw):return [[{'merged_at':'2026-10-15T01:00:00Z','number':7,'base':{'ref':'main','repo':{'full_name':'org/repo'}},'merge_commit_sha':'b'*40,'head':{'sha':'c'*40},'title':'Feature','html_url':'https://github.com/org/repo/pull/7'}]]
 expected={'schema_version':1,'repository':'org/repo','destination':'C1','from':'2026-10-15T00:00:00+00:00','until':'2026-10-15T23:00:00+00:00','timezone':'Australia/Sydney','display_from':'2026-10-15T11:00:00+11:00','display_until':'2026-10-16T10:00:00+11:00','product_acceptance':'not inferred from merge','merges':[{'pr':7,'title':'Feature','url':'https://github.com/org/repo/pull/7','merge_sha':'b'*40,'merged_at':'2026-10-15T01:00:00+00:00','late_discovered':False,'delivery_evidence':[{'task':'T-9','spec':'014','revision':'a'*64,'producer_run':20,'artifact_digest':'sha256:'+'d'*64}],'evidence_status':'authenticated','merge_time_checks':'not independently recorded'}]}
 row=view.prepare(UnitAPI(),'2026-10-15T23:00:00Z')
 assert row['payload'].encode()==json.dumps(expected,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
 prior=path.read_bytes();durable=unit.Digest(path,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode='durable')
 assert durable.prepare(UnitAPI(),'2026-10-16T00:00:00Z')==row
 assert path.read_bytes()==prior,'pending batch changed during receipt mode switch'
print('PASS invalid/default receipt modes, fixed byte-exact legacy payload and pending mode-switch immutability')

source=fixture_source.split("<<'PY'\n",1)[1]
prefix=source.split("\ncases=r'''",1)[0]
setup=source.split("\ncases=r'''\n",1)[1].split(' assert batch_calls,',1)[0]
prefix+="\nmarker=' first=a.checkpoint_projection('\nassert pipeline.count(marker)==1, 'projection fixture checkpoint marker changed'\npipeline=pipeline.replace(marker, \" projection_parent=out('rev-parse',ref)\\n\"+marker,1)\n"
cases=r'''
 # Real Git/bootstrap/stages/coverage above; no caller authenticated flag.
 ds=importlib.util.spec_from_file_location('report_digest',scripts/'factory-digest.py');digest=importlib.util.module_from_spec(ds);ds.loader.exec_module(digest)
 class Report:
  repo='org/repo'
  def request(self,path,**kwargs):
   assert path=='repos/org/repo/pulls?state=closed&per_page=100' and kwargs=={'paginate':True}
   return [[dict(item.pr,merged_at='2026-10-15T01:00:00.123456Z',title='Feature',html_url='https://github.com/org/repo/pull/'+str(item.pr['number'])) for item in sources]]
 active=trust.read_bytes();revoked=json.loads(active);revoked['profiles'][0]['status']='revoked';trust.write_text(json.dumps(revoked))
 retained=root/'retained-only.sqlite';assert a.reconstruct_interval(PipelineState(),policy,retained,trust,store,approval,stream,interval_end=end,history_head=context['history'],campaign=campaign)['projection_complete']
 report=root/'report.sqlite';view=digest.Digest(report,'org/repo','C1','2026-10-15T00:00:00Z');view.receipt_mode='durable'
 # Raw copied tables without a coverage marker cannot authorize a durable report.
 with sqlite3.connect(retained) as src,sqlite3.connect(report) as dst:
  for name,sql in src.execute("SELECT name,sql FROM sqlite_master WHERE type='table'"):
   dst.execute(sql)
   for row in src.execute('SELECT * FROM '+name):dst.execute('INSERT INTO '+name+' VALUES('+','.join('?' for _ in row)+')',row)
 try:view.prepare(Report(),end)
 except ValueError as error:assert 'coverage marker missing' in str(error)
 else:raise AssertionError('unbound receipt tables authorized durable report')
 print('PASS raw receipt tables without validated coverage cannot authorize durable reporting')

 helper_spec=importlib.util.spec_from_file_location('report_receipts',scripts/'factory-reporting-receipts.py');helper=importlib.util.module_from_spec(helper_spec);helper_spec.loader.exec_module(helper)
 # Actual artifacts expire; only retained origin/materials/source observations remain.
 for item in sources:item.expired=True
 target=(root/'import-target.sqlite').resolve();destination=digest.Digest(target,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode='durable')
 with sqlite3.connect(target) as db:
  db.execute('CREATE TABLE tasks(id TEXT PRIMARY KEY, state TEXT)');db.execute("INSERT INTO tasks VALUES('sentinel','unchanged')")
  db.execute('CREATE TABLE opaque_feedback(value TEXT)');db.execute("INSERT INTO opaque_feedback VALUES('private unchanged')")
 class ReadState(PipelineState):
  def request(self,path,method='GET',payload=None):
   assert method=='GET' and payload is None,'production transfer attempted Git writes'
   return super().request(path,method,payload)
 kwargs=dict(interval_end=end,history_head=context['history'],campaign=campaign,page_size=1)
 before_head=out('rev-parse',ref)
 outcome=helper.project_reporting(runs,ReadState(),policy,target,trust,store,approval,stream,**kwargs)
 assert outcome=={'facts_count':2,'coverage_complete':True,'all_history_complete':False,'task_credit':False},outcome
 assert out('rev-parse',ref)==before_head
 with sqlite3.connect(target) as db:
  assert db.execute('SELECT * FROM tasks').fetchall()==[('sentinel','unchanged')]
  assert db.execute('SELECT * FROM opaque_feedback').fetchall()==[('private unchanged',)]
  assert db.execute('SELECT status FROM delivery_trust').fetchall()==[('withdrawn',),('withdrawn',)]
  assert db.execute('SELECT merged_at FROM delivery_times').fetchall()==[('2026-10-15T01:00:00.123456Z',)]*2
 snapshot=target.read_bytes()
 # AC-2: real projected withdrawn proof reaches the durable digest unchanged.
 import shutil
 withdrawn_copy=root/'withdrawn-digest.sqlite';shutil.copyfile(target,withdrawn_copy)
 withdrawn_view=digest.Digest(withdrawn_copy,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode='durable')
 withdrawn_entries=json.loads(withdrawn_view.prepare(Report(),end)['payload'])['merges']
 assert len(withdrawn_entries)==2 and all(row['evidence_status']=='withdrawn' and row['delivery_evidence'] for row in withdrawn_entries),withdrawn_entries
 print('PASS actual helper marker+withdrawn proof retains attribution through durable digest')
 # AC-7: an independently validated earlier protected campaign cannot shrink cache coverage.
 full_head=out('rev-parse',ref);saved_trust=trust.read_bytes();earlier='2026-10-15T22:00:00Z'
 try:
  git('update-ref',ref,projection_parent);trust.write_bytes(active)
  for item in sources:item.expired=False
  narrow_checkpoint=a.checkpoint_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=earlier,limit=2)
  assert narrow_checkpoint['frozen_complete']
  narrow_history=out('rev-parse',ref)
  narrow_stage=a.stage_projection(PipelineState(),policy,trust,store,approval,stream,interval_end=earlier,history_head=narrow_history,limit=2)
  assert narrow_stage['status']=='staged' and narrow_stage['facts_count']==2
  d.advance(runs,PipelineState(),policy,approval,stream,page_size=1)
  for _ in range(3):d.backfill(runs,PipelineState(),policy,approval,stream,interval_end=earlier,page_size=1)
  for _ in range(32):
   d.reconcile(runs,PipelineState(),policy,trust,store,approval,stream,review_rows=4)
   progress=json.loads(git('show',ref+':receipt-archive/progress/'+stream+'.json').stdout)
   if progress['scan']['complete']:break
  assert progress['scan']['complete']
  trust.write_bytes(saved_trust)
  for item in sources:item.expired=True
  narrow_coverage=d.coverage(runs,ReadState(),policy,trust,store,approval,stream,interval_end=earlier,projection_end=earlier,history_head=narrow_history,campaign=narrow_stage['campaign'],page_size=1)
  assert narrow_coverage['coverage_complete'],narrow_coverage
  try:helper.project_reporting(runs,ReadState(),policy,target,trust,store,approval,stream,interval_end=earlier,history_head=narrow_history,campaign=narrow_stage['campaign'],page_size=1)
  except ValueError as error:assert 'coverage regressed' in str(error),str(error)
  else:raise AssertionError('actual earlier protected projection moved coverage backwards')
  assert target.read_bytes()==snapshot
 finally:
  git('update-ref',ref,full_head);trust.write_bytes(saved_trust)
  for item in sources:item.expired=True
 print('PASS actual earlier protected projection rejects without changing reporting bytes')
 # AC-7: an actual complete projection cannot authorize an unverified later cutoff.
 wider=root/'unverified-cutoff.sqlite'
 import shutil
 shutil.copyfile(target,wider)
 future_view=digest.Digest(wider,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode='durable')
 before_wider=wider.read_bytes()
 try:future_view.prepare(Report(),'2026-10-16T00:00:00Z')
 except ValueError as error:assert 'coverage' in str(error),str(error)
 else:raise AssertionError('actual narrower projection authorized later report cutoff')
 assert wider.read_bytes()==before_wider
 print('PASS actual projection coverage bounds new digest cutoff')
 # AC-8: actual protected reads must not partially update hostile destinations.
 mutations={
  'trigger':"CREATE TRIGGER hostile AFTER INSERT ON delivery_receipts BEGIN SELECT 1; END",
  'schema':"ALTER TABLE delivery_receipts ADD COLUMN extra TEXT",
  'coverage-schema':"ALTER TABLE reporting_receipt_coverage ADD COLUMN extra TEXT",
  'foreign-coverage':"UPDATE reporting_receipt_coverage SET repository='other/repo'",
  'changed-origin':"UPDATE reporting_receipt_coverage SET coverage_from='2026-10-15T00:00:00.000001Z'",
  'receipt-conflict':"UPDATE delivery_receipts SET revision='conflict'",
  'provenance-conflict':"UPDATE delivery_provenance SET provenance='conflict'",
  'time-conflict':"UPDATE delivery_times SET merged_at='conflict'",
  'disappearing':"INSERT INTO delivery_times VALUES('not-retained','2026-10-15T01:00:00Z')",
 }
 for label,statement in mutations.items():
  hostile=root/('hostile-'+label+'.sqlite');shutil.copyfile(target,hostile)
  with sqlite3.connect(hostile) as db:db.execute(statement)
  unchanged=hostile.read_bytes()
  try:helper.project_reporting(runs,ReadState(),policy,hostile,trust,store,approval,stream,**kwargs)
  except ValueError:pass
  else:raise AssertionError('hostile destination accepted: '+label)
  assert hostile.read_bytes()==unchanged,'destination partially changed: '+label
 # A real SQLite authorizer fails the last insert after receipt writes execute.
 rollback=(root/'rollback.sqlite').resolve();digest.Digest(rollback,'org/repo','C1','2026-10-15T00:00:00Z')
 rollback_bytes=rollback.read_bytes();real_connect=helper.sqlite3.connect;writes=[]
 def failing_connect(path,*args,**kw):
  db=real_connect(path,*args,**kw)
  if Path(path)==rollback:
   def authorize(action,table,*rest):
    if action==sqlite3.SQLITE_INSERT:
     writes.append(table)
     if table=='reporting_receipt_coverage':return sqlite3.SQLITE_DENY
    return sqlite3.SQLITE_OK
   db.set_authorizer(authorize)
  return db
 helper.sqlite3.connect=failing_connect
 try:
  try:helper.project_reporting(runs,ReadState(),policy,rollback,trust,store,approval,stream,**kwargs)
  except sqlite3.DatabaseError as error:assert 'authorized' in str(error),str(error)
  else:raise AssertionError('mid-transfer SQLite failure swallowed')
 finally:helper.sqlite3.connect=real_connect
 assert 'delivery_receipts' in writes and 'reporting_receipt_coverage' in writes,writes
 assert rollback.read_bytes()==rollback_bytes,'failed transaction left partial projection or marker'
 print('PASS destination triggers/schema/conflicting/disappearing facts and final-insert rollback preserve bytes')
 # AC-7: missing, foreign or too-new origins cannot authorize a new batch.
 for label,statement in {
  'missing':"DELETE FROM reporting_receipt_coverage",
  'foreign':"UPDATE reporting_receipt_coverage SET repository='other/repo'",
  'origin':"UPDATE reporting_receipt_coverage SET coverage_from='2026-10-15T00:30:00Z'",
 }.items():
  invalid=root/('invalid-marker-'+label+'.sqlite');shutil.copyfile(target,invalid)
  with sqlite3.connect(invalid) as db:db.execute(statement)
  current=digest.Digest(invalid,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode='durable');unchanged=invalid.read_bytes()
  try:current.prepare(Report(),end)
  except ValueError as error:assert 'coverage' in str(error)
  else:raise AssertionError('unbound coverage accepted: '+label)
  assert invalid.read_bytes()==unchanged
 print('PASS missing/foreign/origin coverage gaps reject new batch without state change')
 # Actual changed source observations reject before any destination transaction.
 class MissingRuns(Runs):
  def request(self,path,**kwargs):
   value=super().request(path,**kwargs)
   if '/actions/workflows/' in path:return {'total_count':0,'workflow_runs':[]}
   return value
 try:helper.project_reporting(MissingRuns(),ReadState(),policy,target,trust,store,approval,stream,**kwargs)
 except ValueError:pass
 else:raise AssertionError('incomplete actual source observation imported proof')
 assert target.read_bytes()==snapshot
 try:helper.project_reporting(runs,ReadState(),policy,target,trust,store,approval,stream,receipt_db=retained,**kwargs)
 except TypeError:pass
 else:raise AssertionError('caller SQLite accepted as proof')
 assert target.read_bytes()==snapshot
 # Every call reconstructs internally from actual protected reads on a fresh DB.
 second=helper.project_reporting(runs,ReadState(),policy,target,trust,store,approval,stream,**kwargs)
 assert second==outcome and target.read_bytes()==snapshot
 print('PASS actual protected reconstruction+coverage transfer: expiry/read-only/restart/private/task preservation')
 import shutil
 for field in ('delivery_trust','delivery_times','delivery_interval'):
  clone=root/(field+'.sqlite');shutil.copyfile(target,clone)
  with sqlite3.connect(clone) as db:db.execute('DELETE FROM '+field)
  current=digest.Digest(clone,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode='durable')
  entry=json.loads(current.prepare(Report(),end)['payload'])['merges']
  assert all(item['evidence_status']=='missing' and item['delivery_evidence']==[] for item in entry),(field,entry)
 mismatch=root/'timestamp-mismatch.sqlite';shutil.copyfile(target,mismatch)
 with sqlite3.connect(mismatch) as db:db.execute("UPDATE delivery_times SET merged_at='2026-10-15T01:00:00.123457Z'")
 current=digest.Digest(mismatch,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode='durable')
 try:current.prepare(Report(),end)
 except ValueError as error:assert 'timestamp differs' in str(error)
 else:raise AssertionError('fractional timestamp mismatch authenticated')
 clone=root/'legacy.sqlite';shutil.copyfile(target,clone)
 current=digest.Digest(clone,'org/repo','C1','2026-10-15T00:00:00Z')
 assert all(row['evidence_status']=='authenticated' and all('trust_status' not in proof for proof in row['delivery_evidence']) for row in json.loads(current.prepare(Report(),end)['payload'])['merges'])
 print('PASS durable missing/withdrawn/fractional-time/interval facts fail closed; legacy default rendering unchanged')

 # Genuine current active profile re-evaluation, not a caller complete flag.
 trust.write_bytes(active)
 assert helper.project_reporting(runs,ReadState(),policy,target,trust,store,approval,stream,**kwargs)==outcome
 actual=destination.prepare(Report(),end);active_entries=json.loads(actual['payload'])['merges']
 assert all(row['evidence_status']=='authenticated' for row in active_entries),active_entries
 class Transport:
  sent=[]
  def lookup(self,key):return {'receipt':None,'authoritative_absence':True}
  def send(self,key,payload,channel):
   self.sent.append(payload)
   return {'key':key,'payload_sha256':hashlib.sha256(payload.encode()).hexdigest(),'destination':channel,'message_id':'fixture-message'}
 transport=Transport();destination.deliver(actual['key'],transport)
 confirmed=destination.batch(actual['key']);message=render_module.render(confirmed['payload'])
 revoked=json.loads(active);revoked['profiles'][0]['status']='revoked';trust.write_text(json.dumps(revoked))
 assert helper.project_reporting(runs,ReadState(),policy,target,trust,store,approval,stream,**kwargs)==outcome
 assert destination.batch(actual['key'])==confirmed and transport.sent==[confirmed['payload']]
 assert render_module.render(confirmed['payload'])==message and 'WITHDRAWN' not in message
 with sqlite3.connect(target) as db:assert db.execute('SELECT status FROM delivery_trust').fetchall()==[('withdrawn',)]*2
 print('PASS actual active/withdrawn reevaluation preserves already-delivered immutable payload and fixture message')
'''
exec(compile(prefix+'\nexec(compile(fixture+pipeline+'+repr(setup+cases)+',"real-retained-reporting-transfer","exec"))','retained-fixture-bootstrap','exec'))
PY
