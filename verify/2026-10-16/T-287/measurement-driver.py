from pathlib import Path
import json,tempfile,subprocess
saved=Path('/var/folders/40/pjsx1gg17p91kdvfrzgjc2_00000gn/T/t287-full-staged-e_pl7qbz')
c=json.loads((saved/'context.json').read_bytes());c.update(work=str(saved/'git'),trust=str(saved/'receipt-trust.json'),approval=str(saved/'receipt-bootstrap.json'),mode='projection',database=str(Path(tempfile.mkdtemp(prefix='t287-measured-db-'))/'fresh.sqlite'))
text=Path('.claude/scripts/test/factory-receipt-history-reader.py').read_text()
inject=r'''
 measured={'calls':0,'canonical_response_bytes':0,'categories':{},'blob_batches':0,'blob_raw_bytes':0}
 underlying=HistoryState.request;batch=HistoryState.read_blobs
 def measured_request(self,target,method='GET',payload=None):
  value=underlying(self,target,method,payload)
  kind=next((kind for part,kind in (('/git/trees/','trees'),('/git/commits/','commits'),('/git/blobs/','blobs'),('/pulls/','pulls'),('/compare/','compare'),('/rulesets/','rules'),('/git/ref/','ref'),('/commits?','history')) if part in target),'other')
  measured['calls']+=1;measured['canonical_response_bytes']+=len(a.canonical(value));measured['categories'][kind]=measured['categories'].get(kind,0)+1
  return value
 def measured_batch(self,repository_id,entries):
  value=batch(self,repository_id,entries);measured['blob_batches']+=1;measured['blob_raw_bytes']+=value['raw_bytes'];return value
 HistoryState.request=measured_request;HistoryState.read_blobs=measured_batch
'''
text=text.replace(" before=out('rev-parse',ref)"," before=out('rev-parse',ref)\n"+inject,1)
line="  result=a.reconstruct_interval(HistoryState(),policy,db,trust,store,approval,stream,interval_end=end,history_head=context['selected'],campaign=context['campaign'])"
assert line in text
text=text.replace(line,"  try:\n "+line+"\n  finally:\n   measured['total_calls']=measured['calls']+measured['blob_batches'];measured['total_response_bytes']=measured['canonical_response_bytes']+measured['blob_raw_bytes'];measured['sqlite_exists']=db.exists();print(json.dumps(measured),file=sys.stderr)",1)
run=Path('/private/tmp/t287-instrumented-history-reader.py');run.write_text(text)
p=subprocess.run(['python3',str(run)],input=json.dumps(c).encode(),capture_output=True)
print(p.stdout.decode(),end='');print(p.stderr.decode(),end='');raise SystemExit(p.returncode)
