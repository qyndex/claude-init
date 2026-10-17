#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
import base64,hashlib,importlib.util,json,os,pathlib,sys,tempfile,subprocess
spec=importlib.util.spec_from_file_location('gitstate',pathlib.Path('.claude/scripts/factory-git-state.py'));g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
with tempfile.TemporaryDirectory() as tmp:
 root=pathlib.Path(tmp);raw=b'{"public":"fixture"}\n';sha=subprocess.check_output(['git','hash-object','--stdin'],input=raw).decode().strip()
 entry={'path':'receipt-archive/materials/aa/'+'a'*64+'.json','sha':sha,'size':len(raw)}
 response={'data':{'repository':{'databaseId':101,'nameWithOwner':'org/repo','o0':{'__typename':'Blob','oid':sha,'byteSize':len(raw),'isBinary':False,'isTruncated':False,'text':raw.decode()}}}}
 (root/'response.json').write_text(json.dumps(response));stub=root/'gh'
 stub.write_text('#!'+sys.executable+'\n'+'''import json,os,pathlib,sys
root=pathlib.Path('''+repr(str(root))+''')
assert sys.argv[1:]==['api','--hostname','github.com','--method','POST','graphql','--input','-']
payload=json.load(sys.stdin)
assert payload['query'].startswith('query') and 'mutation' not in payload['query']
assert os.environ.get('GH_TOKEN')=='fixture-token'
assert not any(k.startswith(('SLACK_','FACTORY_','ANTHROPIC_')) for k in os.environ)
(root/'called').write_text('fixed GitHub.com read-only query, no secret values retained')
print((root/'response.json').read_text())
''');stub.chmod(0o755)
 before=dict(os.environ);os.environ.update(PATH=str(root)+os.pathsep+os.environ['PATH'],SLACK_SENTINEL='must-not-leak',FACTORY_SENTINEL='must-not-leak')
 try:
  api=g.API('org/repo','fixture-token')
  result=api.read_blobs(101,[entry])
  assert base64.b64decode(result['blobs'][sha]['content'])==raw and result['calls']==1 and 0<result['raw_bytes']<=2097152
  assert (root/'called').exists()
  print('fixed same-repository GraphQL Blob query returns exact Git bytes through actual bounded gh stub')
  import copy
  cases=1
  def reject(value, selectors=None, identity=101):
   global cases
   (root/'response.json').write_text(value if type(value) is str else json.dumps(value))
   try:api.read_blobs(identity,[entry] if selectors is None else selectors)
   except ValueError:cases+=1
   else:raise AssertionError('invalid blob batch accepted')
  for value in (None,[],{}, {'data':None},{'data':{'repository':None}},dict(response,errors=[]),dict(response,errors=[{'message':'partial'}]),dict(response,extensions={})):
   reject(value)
  for key,value in [('databaseId',True),('databaseId',102),('databaseId',101.0),('nameWithOwner','foreign/repo'),('o1',{})]:
   bad=copy.deepcopy(response);bad['data']['repository'][key]=value;reject(bad)
  bad=copy.deepcopy(response);del bad['data']['repository']['o0'];reject(bad)
  bad=copy.deepcopy(response);bad['data']['repository']['o0']=None;reject(bad)
  for key,value in [('__typename','Commit'),('oid','f'*40),('byteSize',True),('byteSize',len(raw)+1),('byteSize',float(len(raw))),('isBinary',None),('isBinary',True),('isTruncated',True),('text',None),('text',False),('text','x'*len(raw)),('text','\ud800'),('unexpected','field')]:
   bad=copy.deepcopy(response);bad['data']['repository']['o0'][key]=value;reject(bad)
  reject(json.dumps(response).replace('"o0":','"o0": null, "o0":',1));reject('{')
  for selectors in ([],[entry]*33,[entry,entry],[dict(entry,path='reports/'+'a'*64+'.json')],[dict(entry,path='../authority.json')],[dict(entry,extra=True)],[dict(entry,size=True)],[dict(entry,sha='not-a-git-sha')],[None]):
   (root/'called').unlink(missing_ok=True);reject(response,selectors);assert not (root/'called').exists()
  for identity in (True,0,101.0,'101',2**63):
   (root/'called').unlink(missing_ok=True);reject(response,identity=identity);assert not (root/'called').exists()
  raw2=b'{"public":"second"}';sha2=subprocess.check_output(['git','hash-object','--stdin'],input=raw2).decode().strip();entry2=dict(entry,path='receipt-archive/materials/bb/'+'b'*64+'.json',sha=sha2,size=len(raw2))
  good=copy.deepcopy(response);good['data']['repository']['o1']=dict(good['data']['repository']['o0'],oid=sha2,byteSize=len(raw2),text=raw2.decode())
  (root/'response.json').write_text(json.dumps(good));batch=api.read_blobs(101,[entry,entry2]);assert set(batch['blobs'])=={sha,sha2};cases+=1
  try:api.request('graphql','POST',{})
  except ValueError:cases+=1
  else:raise AssertionError('generic GraphQL passthrough enabled')

  large=[dict(entry,size=600000),dict(entry2,size=600000)]
  (root/'called').unlink(missing_ok=True);reject(response,large);assert not (root/'called').exists()
  # A live child produces too much output; the real bounded runner must reject
  # while reading, before JSON decoding. No actual network/credentials are used.
  (root/'response.json').write_text('x'*2097153)
  try:api.read_blobs(101,[entry])
  except ValueError as error:assert 'output limit' in str(error);cases+=1
  else:raise AssertionError('oversized subprocess response accepted')
  stub.write_text('#!'+sys.executable+'\nimport sys;sys.exit(9)\n');stub.chmod(0o755)
  try:api.read_blobs(101,[entry])
  except ValueError as error:assert str(error)=='blob batch API failed; no fallback';cases+=1
  else:raise AssertionError('failed API silently fell back')
  print(str(cases)+' strict bounded Blob transport cases passed; no live API or extra permission')

 finally:os.environ.clear();os.environ.update(before)
PY
