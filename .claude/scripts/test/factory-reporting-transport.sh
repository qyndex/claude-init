#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: actual bounded subprocess routing, no live credential or API calls."""
import base64,hashlib,importlib.util,json,os,tempfile
from pathlib import Path
scripts=Path('.claude/scripts').resolve()
path=scripts/'factory-reporting-transport.py'
assert path.exists(),'missing protected reporting role transport'
spec=importlib.util.spec_from_file_location('transport',path);t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
count=0
with tempfile.TemporaryDirectory() as tmp:
 root=Path(tmp);record=root/'calls';response=root/'response';response.write_text('{}')
 stub=root/'gh';stub.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
with Path(os.environ['HOME'],'calls').open('a') as f:f.write(json.dumps({'argv':sys.argv[1:],'token':os.environ.get('GH_TOKEN'),'unsafe':[k for k in os.environ if 'SLACK' in k or 'PRIVATE_KEY' in k or k=='FACTORY_REPORTING_STATE_TOKEN']})+'\\n')
sys.stdout.buffer.write(Path(os.environ['HOME'],'response').read_bytes())
''');stub.chmod(0o755)
 saved=dict(os.environ);os.environ.update(PATH=str(root)+os.pathsep+saved['PATH'],HOME=str(root),FACTORY_SLACK_BOT_TOKEN='forbidden-test-sentinel',FACTORY_REPORTING_APP_PRIVATE_KEY='forbidden-test-key',FACTORY_REPORTING_STATE_TOKEN='forbidden-test-state')
 env={'GITHUB_REPOSITORY':'org/repo','FACTORY_REPORTING_STATE_REPOSITORY':'org/repo','GH_TOKEN':'source-fixture','FACTORY_REPORTING_STATE_TOKEN':'legacy-fixture'}
 def reject(fn,reason):
  global count
  before=len(record.read_text().splitlines()) if record.exists() else 0
  try:fn()
  except ValueError as e:assert reason in str(e),(reason,str(e));count+=1
  else:raise AssertionError('accepted '+reason)
  return before
 try:
  config=t.build_config(env);assert config=={'repository':'org/repo','writer_mode':'legacy','writer_app_id':None};count+=1
  selected=dict(env,FACTORY_REPORTING_APP_WRITER_ENABLED='true',FACTORY_REPORTING_APP_ID='5340785',FACTORY_REPORTING_APP_TOKEN='writer-fixture')
  api=t.create_api(selected);assert api.repo=='org/repo';assert not any('fixture' in str(v) for v in t.build_config(selected).values());count+=1
  for endpoint,token in [('repos/org/repo/actions/runs/7','source-fixture'),('repos/org/repo/pulls/8','source-fixture'),('repos/org/repo/contents/.claude/a.py?ref='+'a'*40,'source-fixture'),('repos/org/repo','writer-fixture'),('repos/org/repo/git/trees/'+'b'*40,'writer-fixture'),('repos/org/repo/rulesets/1','writer-fixture'),('repos/org/repo/git/ref/heads/factory%2Freporting','writer-fixture'),('repos/org/repo/actions/runs?branch=release%2Fmain&per_page=100&page=1','source-fixture')]:
   assert api.request(endpoint)=={};row=json.loads(record.read_text().splitlines()[-1]);assert row['token']==token and row['unsafe']==[];assert row['argv'][:5]==['api','--hostname','github.com','--method','GET'];count+=1
  # Digest.prepare uses the exact collection endpoint with query parameters.
  response.write_text('[]');before=(api.budget.calls,api.budget.bytes)
  assert api.get('repos/org/repo/pulls?state=closed&sort=updated&direction=desc&per_page=100')==[]
  row=json.loads(record.read_text().splitlines()[-1]);assert row['token']=='source-fixture' and row['unsafe']==[]
  assert row['argv'][-1]=='repos/org/repo/pulls?state=closed&sort=updated&direction=desc&per_page=100'
  assert (api.budget.calls,api.budget.bytes)==(before[0]+1,before[1]+2);count+=1
  for endpoint,method,payload,raw in [('repos/org/repo/pulls','POST',{},False),('repos/org/repo/pulls','PATCH',{},False),('repos/org/repo/pulls','GET',None,True),('repos/other/repo/pulls','GET',None,False),('repos/org/repo/pull','GET',None,False)]:
   before=reject(lambda:api.request(endpoint,method,payload,raw=raw),'reporting');assert len(record.read_text().splitlines())==before
  response.write_text('{}')
  api.request('repos/org/repo/git/refs/heads/factory%2Freporting','PATCH',{'sha':'c'*40,'force':False});count+=1
  for endpoint,method,payload in [('graphql','POST',{}),('repos/other/repo/actions/runs','GET',None),('repos/org/repo/actions/runs/7','POST',{}),('repos/org/repo/pulls/8','PATCH',{}),('repos/org/repo/rulesets/1','PATCH',{}),('repos/org/repo/git/refs/heads/main','PATCH',{'sha':'a'*40,'force':True}),('repos/org/repo/git/refs/heads/main','DELETE',None),('repos/org/repo/git/ref/heads/%2E%2E','GET',None),('repos/org/repo/git/ref/heads/%252F','GET',None),('repos/org/repo/actions/runs?x=%2f','GET',None),('repos/org/repo/actions/runs#x','GET',None),('repos/org/repo/contents/../a','GET',None)]:
   before=reject(lambda:api.request(endpoint,method,payload),'reporting');assert len(record.read_text().splitlines())==before
  for key,value in [('FACTORY_REPORTING_APP_WRITER_ENABLED','TRUE'),('FACTORY_REPORTING_APP_WRITER_ENABLED',True),('FACTORY_REPORTING_APP_ID','0'),('FACTORY_REPORTING_APP_ID','true'),('FACTORY_REPORTING_APP_TOKEN',''),('FACTORY_REPORTING_STATE_REPOSITORY','foreign/repo'),('GH_TOKEN','')]:
   bad=dict(selected);bad[key]=value;reject(lambda:t.create_api(bad),'reporting')
  legacy=t.create_api(env);legacy.request('repos/org/repo');assert json.loads(record.read_text().splitlines()[-1])['token']=='legacy-fixture';count+=1
  fallback=dict(env);fallback.pop('FACTORY_REPORTING_STATE_TOKEN');t.create_api(fallback).request('repos/org/repo');assert json.loads(record.read_text().splitlines()[-1])['token']=='source-fixture';count+=1
  # Every paginated provider call is explicitly metered; no implicit gh pagination.
  response.write_text(json.dumps({'artifacts':[{'id':1}]}));assert api.request('repos/org/repo/actions/runs/7/artifacts',paginate=True)==[{'artifacts':[{'id':1}]}];count+=1
  assert '--paginate' not in json.loads(record.read_text().splitlines()[-1])['argv'];count+=1
  assert api.request('repos/org/repo/actions/runs/7/artifacts?per_page=100',paginate=True)==[{'artifacts':[{'id':1}]}];count+=1
  api.request('repos/org/repo/actions/workflows/7/runs?created=2026-10-15T00%3A00%3A00Z..2026-10-15T00%3A01%3A00Z');count+=1
  raw=b'{"fixture":true}';sha=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
  entry={'path':'receipt-archive/materials/aa/'+'a'*64+'.json','sha':sha,'size':len(raw)}
  blob={'data':{'repository':{'databaseId':101,'nameWithOwner':'org/repo','o0':{'__typename':'Blob','oid':sha,'byteSize':len(raw),'isBinary':False,'isTruncated':False,'text':raw.decode()}}}}
  response.write_text(json.dumps(blob));before=(api.budget.calls,api.budget.bytes);value=api.read_blobs(101,[entry]);assert base64.b64decode(value['blobs'][sha]['content'])==raw
  assert (api.budget.calls,api.budget.bytes)==(before[0]+1,before[1]+response.stat().st_size);assert json.loads(record.read_text().splitlines()[-1])['token']=='writer-fixture';count+=1
  pr={'data':{'repository':{'databaseId':101,'nameWithOwner':'org/repo','p0':{'number':7,'merged':True,'mergedAt':'2026-10-15T01:00:00Z','mergeCommit':{'oid':'d'*40},'baseRepository':{'databaseId':101,'nameWithOwner':'org/repo'}}}}}
  response.write_text(json.dumps(pr));before=(api.budget.calls,api.budget.bytes);value=api.read_pull_requests(101,[7]);assert value['pull_requests'][7]['merge_commit_sha']=='d'*40
  assert (api.budget.calls,api.budget.bytes)==(before[0]+1,before[1]+response.stat().st_size);assert json.loads(record.read_text().splitlines()[-1])['token']=='source-fixture';count+=1
  response.write_text(json.dumps({'artifacts':[{'id':1}]*100}));before=api.budget.calls;reject(lambda:api.request('repos/org/repo/actions/runs/7/artifacts',paginate=True),'capacity');assert api.budget.calls==before+10;count+=1

  response.write_text(json.dumps({'artifacts':[{'id':1}]}));reject(lambda:api.request('repos/org/repo/actions/runs/7/artifacts?per_page=1',paginate=True),'pagination')
  response.write_text(json.dumps({'workflow_runs':[],'total_count':1000}));reject(lambda:api.request('repos/org/repo/actions/workflows/7/runs',paginate=True),'pagination')
  response.write_bytes(b'{"x":1,"x":2}');reject(lambda:api.request('repos/org/repo'),'JSON')
  response.write_bytes(b'x'*2097153);reject(lambda:api.request('repos/org/repo'),'output')
  response.write_text('{}');api.budget.calls=2048;before=reject(lambda:api.request('repos/org/repo'),'capacity');assert len(record.read_text().splitlines())==before
  api=t.create_api(selected);api.budget.bytes=33554432;reject(lambda:api.request('repos/org/repo'),'capacity')
  assert all(not row['unsafe'] for row in map(json.loads,record.read_text().splitlines()));count+=1
 finally:os.environ.clear();os.environ.update(saved)
print(str(count)+' protected reporting transport cases passed; offline subprocess fixtures only')
PY
