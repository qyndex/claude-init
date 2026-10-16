#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
"""AC-6/AC-8: bounded data-only archive namespaces and complete subtree discovery."""
import pathlib,sys,json,copy,importlib.util,hashlib,tempfile
text=pathlib.Path('.claude/scripts/test/factory-hosted-digest.sh').read_text().split("<<'PYTEST'\n",1)[1].split('with tempfile.TemporaryDirectory()',1)[0]
sys.argv=['test',str(pathlib.Path.cwd())];exec(compile(text,'existing-state-fixture','exec'))
api=GitAPI();stream='c'*64;tree=api.trees['b'*40]
paths=['README.md','reports/'+'0'*64+'.json','receipt-archive/objects/aa/'+'a'*64+'.json','receipt-archive/materials/bb/'+'b'*64+'.json','receipt-archive/index/'+'c'*64+'/000/000/000/000000000000.json','receipt-archive/discovery/'+'c'*64+'.json','receipt-archive/progress/'+'c'*64+'.json','receipt-archive/outcomes/'+'c'*64+'/aa/'+'a'*64+'.json','receipt-archive/pending/'+'c'*64+'/000/000/000/000000000000.json','receipt-archive/pending/'+'c'*64+'/identities/aa/'+'a'*64+'.json']
for path in paths:
 data=b'opaque encrypted existing bytes' if path.startswith('reports/') else b'{}';sha=m.git_hash(data);api.blobs[sha]=data;tree.append({'path':path,'type':'blob','mode':'100644','sha':sha,'size':len(data)})
state=m.GitState(api,'factory-reporting-state',stream,api.head,bootstrap_existing=True)
before=copy.deepcopy(tree);state.checkpoint(b'{"new":"report"}')
after=api.trees[api.commits[api.head]['tree']['sha']];assert all(entry in after for entry in before);assert all(api.blobs[e['sha']]==b'opaque encrypted existing bytes' for e in after if e['path'].startswith('reports/0'))
s=importlib.util.spec_from_file_location('paths','.claude/scripts/factory-state-paths.py');p=importlib.util.module_from_spec(s);s.loader.exec_module(p)
count=2
for path in ['.github/workflows/run.yml','receipt-archive/run.py','receipt-archive/objects/zz/'+'a'*64+'.json','receipt-archive/objects/ab/'+'a'*64+'.json','receipt-archive/index/'+'c'*64+'/latest.json','receipt-archive/discovery/other.json','receipt-archive/pending/'+'c'*64+'/latest.json','receipt-archive/pending/'+'c'*64+'/identities/ab/'+'a'*64+'.json','receipt-archive/outcomes/'+'c'*64+'/ab/'+'a'*64+'.json','receipt-archive/outcomes/'+'c'*64+'/latest.json','receipt-archive/progress/other.json','receipt-archive/progress/'+'c'*64+'/cursor.json','reports/../README.md','receipt-archive/index/'+'c'*64+'/000000000000.json','receipt-archive/index/'+'c'*64+'/000/000/001/000000000000.json','receipt-archive/materials/bb/'+'b'*64+'.sh']:
 try:p.validate_entry({'path':path,'type':'blob','mode':'100644','sha':'a'*40})
 except ValueError:count+=1
 else:raise AssertionError('unsafe path '+path)
for mode in ('100755','120000','160000'):
 try:p.validate_entry(dict(before[2],mode=mode))
 except ValueError:count+=1
 else:raise AssertionError('unsafe mode')
segment={'schema_version':1,'repository':'org/repo','stream':stream,'number':0,'records':[{'run_id':1,'attempt':1,'artifact_id':2,'record_sha256':'d'*64}]}
assert p.validate_segment(segment,'org/repo',stream,0)==segment;count+=1
for mutation in (lambda x:x.update(unknown=True),lambda x:x.update(number=1),lambda x:x['records'].append(copy.deepcopy(x['records'][0])),lambda x:x['records'][0].update(run_id=True),lambda x:x['records'][0].update(record_sha256='bad'),lambda x:x.update(records=[]),lambda x:x.update(records=[dict(x['records'][0],run_id=i+1) for i in range(257)])):
 bad=copy.deepcopy(segment);mutation(bad)
 try:p.validate_segment(bad,'org/repo',stream,0)
 except ValueError:count+=1
 else:raise AssertionError('invalid index accepted')
# More than1024 lifetime entries across immutable subtrees; one page per invocation.
class Pages:
 repo='org/repo'
 def request(self,path):
  sha=path.rsplit('/',1)[1]
  if sha=='f'*40:return {'sha':sha,'truncated':False,'tree':[{'path':'receipt-archive','type':'tree','mode':'040000','sha':'e'*40}]}
  if sha=='e'*40:return {'sha':sha,'truncated':False,'tree':[{'path':'objects','type':'tree','mode':'040000','sha':'d'*40}]}
  if sha=='d'*40:return {'sha':sha,'truncated':False,'tree':[{'path':f'{i:02x}','type':'tree','mode':'040000','sha':f'{i:040x}'} for i in range(16)]}
  i=int(sha,16);return {'sha':sha,'truncated':False,'tree':[{'path':f'{i:02x}'+f'{j:062x}'+'.json','type':'blob','mode':'100644','sha':'a'*40,'size':2} for j in range(100)]}
entries=[];cursor=None
for _ in range(30):
 scan=p.scan_tree(Pages(),'repos/org/repo','f'*40,cursor=cursor,page_budget=1);entries+=scan['entries'];cursor=scan['cursor']
 if scan['complete']:break
assert scan['complete'] and cursor is None and len([x for x in entries if x['type']=='blob'])==1600;count+=1
try:p.scan_tree(Pages(),'repos/org/repo','a'*40,cursor={'root':'f'*40,'pending':[]})
except ValueError:count+=1
else:raise AssertionError('foreign cursor')
try:p.scan_tree(Pages(),'repos/foreign/repo','f'*40)
except ValueError:count+=1
else:raise AssertionError('foreign API root')
bad=dict(before[2],size=1048577)
try:p.validate_entry(bad)
except ValueError:count+=1
else:raise AssertionError('oversized archive entry')
class MalformedPages(Pages):
 def request(self,name):return {'sha':'f'*40,'truncated':False,'tree':['unknown entry']}
try:p.scan_tree(MalformedPages(),'repos/org/repo','f'*40)
except ValueError:count+=1
else:raise AssertionError('unknown tree entry')
class TruncatedPages(Pages):
 def request(self,name):return {'sha':'f'*40,'truncated':True,'tree':[]}
try:p.scan_tree(TruncatedPages(),'repos/org/repo','f'*40)
except ValueError:count+=1
else:raise AssertionError('truncated tree accepted')
print(f'{count} state path/index/resumable tree cases passed; path/index suite performs no CAS writes')
PY
