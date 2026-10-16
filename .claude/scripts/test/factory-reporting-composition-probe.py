"""Offline saved real-history composition probe; no production input or cloud access."""
import argparse
import json
from pathlib import Path

parser=argparse.ArgumentParser(allow_abbrev=False)
parser.add_argument('--snapshot',type=Path,required=True)
args=parser.parse_args()
context=json.loads((args.snapshot/'context.json').read_bytes())
context.update(work=str((args.snapshot/'git').resolve()),trust=str((args.snapshot/'receipt-trust.json').resolve()),approval=str((args.snapshot/'receipt-bootstrap.json').resolve()))
reader=Path('.claude/scripts/test/factory-receipt-history-reader.py').read_text()
exec(compile(reader.split('\ndef main():',1)[0],'history-provider-functions','exec'))
fixture=Path('.claude/scripts/test/factory-receipt-cas.sh').read_text().split("<<'PY'\n",1)[1].split(" store={'repository'",1)[0]
pipeline=Path('.claude/scripts/test/factory-receipt-projection-windows.sh').read_text().split("cases=r'''\n",1)[1].split(' # Two distinct approved tasks',1)[0]
provider=Path('.claude/scripts/test/factory-receipt-history.sh').read_text().split("cases=r'''\n",1)[1].split(' total=1001;end=',1)[0]
case=r'''
 import shutil,sqlite3
 from types import SimpleNamespace
 git('fetch',context['work'],ref);loaded=out('rev-parse','FETCH_HEAD');git('update-ref',ref,loaded,initial)
 shutil.copyfile(context['trust'],trust);shutil.copyfile(context['approval'],approval)
 policy=context['policy'];store=context['store'];stream=context['stream'];end=context['end']
 initial=json.loads(approval.read_bytes())['bootstrap_sha'];tree=json.loads(approval.read_bytes())['bootstrap_tree'];before=out('rev-parse',ref)
 ts=importlib.util.spec_from_file_location('composition_transport',scripts/'factory-reporting-transport.py');t=importlib.util.module_from_spec(ts);ts.loader.exec_module(t)
 backend=HistoryState();source=runs(context['metadata'],policy,'2026-10-15T00:00:00Z',end)
 original=t.process.run;provider_bin=root/'blob-provider-bin';counts={'rest':0,'graphql':0}
 def http_provider(command,**kwargs):
  assert command[:5]==['gh','api','--hostname','github.com','--method'] and command[5]=='GET' or command==['gh','api','--hostname','github.com','--method','POST','graphql','--input','-']
  if command[6]=='graphql':
   counts['graphql']+=1
   selected=dict(kwargs['env']);selected['PATH']=str(provider_bin)+os.pathsep+selected['PATH'];kwargs['env']=selected
   return original(command,**kwargs)
  target=command[6];assert command[5]=='GET';counts['rest']+=1
  value=source.request(target) if '/actions/workflows/' in target else source.get(target) if '/actions/runs/' in target else backend.request(target)
  return SimpleNamespace(returncode=0,stdout=json.dumps(value).encode(),stderr=b'')
 t.process.run=http_provider
 api=t.RoutedAPI('org/repo','offline-source-fixture','offline-writer-fixture')
 ds=importlib.util.spec_from_file_location('composition_discovery',scripts/'factory-receipt-discovery.py');d=importlib.util.module_from_spec(ds);ds.loader.exec_module(d)
 try:
  coverage=d.coverage(api,api,policy,trust,store,approval,stream,interval_end=end,projection_end=end,history_head=context['selected'],campaign=context['campaign'])
  assert coverage['coverage_complete'] and coverage['retained_attempts']==1001,coverage
  print(json.dumps({'phase':'ready-coverage','calls':api.budget.calls,'bytes':api.budget.bytes,'actual_provider_calls':counts}),flush=True)
  rs=importlib.util.spec_from_file_location('composition_transfer',scripts/'factory-reporting-receipts.py');transfer=importlib.util.module_from_spec(rs);rs.loader.exec_module(transfer)
  report=root/'report.sqlite';dg=importlib.util.spec_from_file_location('composition_digest',scripts/'factory-digest.py');digest=importlib.util.module_from_spec(dg);dg.loader.exec_module(digest);digest.Digest(report,'org/repo','C1','2026-10-15T00:00:00Z',receipt_mode='durable')
  result=transfer.project_reporting(api,api,policy,report.resolve(),trust,store,approval,stream,interval_end=end,history_head=context['selected'],campaign=context['campaign'])
  assert result['coverage_complete'] and result['facts_count']==1001,result
  with sqlite3.connect(report) as sql:assert all(sql.execute('SELECT count(*) FROM '+name).fetchone()[0]==1001 for name in transfer.DEFINITIONS)
  assert out('rev-parse',ref)==before and git('show',ref+':'+oldpath).stdout==b'opaque existing encrypted feedback envelope'
  print(json.dumps({'phase':'ready-plus-typed-transfer','result':result,'calls':api.budget.calls,'bytes':api.budget.bytes,'cache_bytes':api._immutable_bytes,'actual_provider_calls':counts,'actual_retained_facts':1001,'read_only':True,'global_coverage':False,'task_credit':False}),flush=True)
 finally:t.process.run=original
'''
exec(compile(fixture+pipeline+provider+case,'saved-real-history-composition','exec'))
