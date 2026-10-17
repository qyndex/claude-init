#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-7/AC-8: bounded fixed fresh PR observations, never persisted trust."""
import copy,importlib.util,json,os,pathlib,sys,tempfile
spec=importlib.util.spec_from_file_location('gitstate',pathlib.Path('.claude/scripts/factory-git-state.py'));g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp);pr={'number':7,'merged':True,'mergedAt':'2026-10-15T01:00:00Z','mergeCommit':{'oid':'b'*40},'baseRepository':{'databaseId':101,'nameWithOwner':'org/repo'}}
 response={'data':{'repository':{'databaseId':101,'nameWithOwner':'org/repo','p0':pr}}};stub=root/'gh'
 stub.write_text('#!'+sys.executable+'\n'+'''import json,os,pathlib,sys
root=pathlib.Path('''+repr(str(root))+''')
assert sys.argv[1:]==['api','--hostname','github.com','--method','POST','graphql','--input','-']
payload=json.load(sys.stdin);assert payload['query'].startswith('query ReceiptPullRequests(') and 'mutation' not in payload['query']
assert set(payload['variables'])=={'owner','name'}|{'n'+str(i) for i in range(len(payload['variables'])-2)}
for i in range(len(payload['variables'])-2):
 assert payload['variables']['n'+str(i)]==7+i
 assert 'p'+str(i)+':pullRequest(number:$n'+str(i)+'){number merged mergedAt mergeCommit{oid} baseRepository{databaseId nameWithOwner}}' in payload['query']
assert payload['variables']['owner']=='org' and payload['variables']['name']=='repo' and 'followRenames:false' in payload['query']
assert os.environ.get('GH_TOKEN')=='fixture-token'
assert not any(k.startswith(('SLACK_','FACTORY_','ANTHROPIC_')) for k in os.environ)
(root/'called').write_text('fixed same-repo selected-field PR query; no credential values retained')
print((root/'response.json').read_text())
''');stub.chmod(0o755)
 old=dict(os.environ);os.environ.update(PATH=str(root)+os.pathsep+os.environ['PATH'],SLACK_SENTINEL='do-not-copy',FACTORY_SENTINEL='do-not-copy')
 try:
  (root/'response.json').write_text(json.dumps(response));api=g.API('org/repo','fixture-token')
  value=api.read_pull_requests(101,[7]);assert value['pull_requests'][7]=={'number':7,'merged':True,'merged_at':pr['mergedAt'],'merge_commit_sha':'b'*40,'base':{'repo':{'id':101,'full_name':'org/repo'}}} and value['calls']==1 and 0<value['raw_bytes']<=2097152
  assert (root/'called').exists();cases=1
  def invalid(value,repo=101,numbers=None):
   global cases
   (root/'response.json').write_text(json.dumps(value))
   try:api.read_pull_requests(repo,[7] if numbers is None else numbers)
   except ValueError:cases+=1
   else:raise AssertionError('malformed PR batch accepted')
  for repo,numbers in ((True,[7]),(0,[7]),(101,[]),(101,[True]),(101,[0]),(101,[2147483648]),(101,[7,7]),(101,list(range(1,34))),(101,['7'])):invalid(response,repo,numbers)
  for key,bad in (('databaseId',True),('databaseId',102),('nameWithOwner','foreign/repo'),('p0',None)):
   value=copy.deepcopy(response);value['data']['repository'][key]=bad;invalid(value)
  for key,bad in (('number',True),('number',8),('merged',1),('merged',False),('mergeCommit',None),('mergedAt',1),('mergedAt','2026-10-15T00:00:00.1234567Z'),('mergedAt','2026-10-15T00:00:00+24:00'),('mergeCommit',{'oid':'../foreign'}),('baseRepository',None),('baseRepository',{'databaseId':True,'nameWithOwner':'org/repo'}),('baseRepository',{'databaseId':102,'nameWithOwner':'org/repo'})):
   value=copy.deepcopy(response);value['data']['repository']['p0'][key]=bad;invalid(value)
  for value in ({'errors':[],'data':response['data']},{'data':{'repository':None}},{'data':{'repository':dict(response['data']['repository'],extra={})}},{'data':{'repository':{'databaseId':101,'nameWithOwner':'org/repo'}}}):invalid(value)
  value=copy.deepcopy(response);del value['data']['repository']['p0']['mergedAt'];invalid(value)
  value=copy.deepcopy(response);value['data']['repository']['p0']['extra']=1;invalid(value)
  value=copy.deepcopy(response);value['data']['repository']['p0']['mergedAt']=None;(root/'response.json').write_text(json.dumps(value));assert api.read_pull_requests(101,[7])['pull_requests'][7]['merged_at'] is None;cases+=1
  value=copy.deepcopy(response);value['data']['repository']['p1']=dict(pr,number=8);(root/'response.json').write_text(json.dumps(value));two=api.read_pull_requests(101,[7,8]);assert set(two['pull_requests'])=={7,8};cases+=1
  # Same instance must observe newly changed current metadata rather than cache it.
  value['data']['repository']['p0']['mergeCommit']['oid']='c'*40;(root/'response.json').write_text(json.dumps(value));assert api.read_pull_requests(101,[7,8])['pull_requests'][7]['merge_commit_sha']=='c'*40;cases+=1
  (root/'response.json').write_text('{"data":{},"data":{}}')
  try:api.read_pull_requests(101,[7])
  except ValueError:cases+=1
  else:raise AssertionError('duplicate JSON accepted')
  stub.write_text('#!'+sys.executable+'\nimport sys;sys.exit(9)\n');stub.chmod(0o755)
  try:api.read_pull_requests(101,[7])
  except ValueError as error:assert 'no fallback' in str(error);cases+=1
  else:raise AssertionError('failed batch silently fell back')
  stub.write_text('#!'+sys.executable+'\nimport sys;sys.stdout.write("x"*3000000)\n');stub.chmod(0o755)
  try:api.read_pull_requests(101,[7])
  except ValueError as error:assert 'output limit' in str(error);cases+=1
  else:raise AssertionError('oversized PR response accepted')
  print(str(cases)+' fixed fresh PR batch boundary cases passed; no live calls or extra permissions')
 finally:os.environ.clear();os.environ.update(old)
PY
