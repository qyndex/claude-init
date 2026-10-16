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
source=Path('.claude/scripts/test/factory-receipt-coverage-batch.sh').read_text().split("<<'PY'\n",1)[1]
prefix=source.split("\ncases=r'''",1)[0]
setup=source.split("\ncases=r'''\n",1)[1].split(' assert batch_calls,',1)[0]
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
 # Baseline renders genuine withdrawn retained proof as authenticated.
 with sqlite3.connect(retained) as src,sqlite3.connect(report) as dst:
  for name,sql in src.execute("SELECT name,sql FROM sqlite_master WHERE type='table'"):
   dst.execute(sql)
   for row in src.execute('SELECT * FROM '+name):dst.execute('INSERT INTO '+name+' VALUES('+','.join('?' for _ in row)+')',row)
 entries=json.loads(view.prepare(Report(),end)['payload'])['merges']
 assert len(entries)==2 and all(row['evidence_status']=='withdrawn' for row in entries),entries
 print('PASS actual retained withdrawn trust is visible and never authenticated')

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
