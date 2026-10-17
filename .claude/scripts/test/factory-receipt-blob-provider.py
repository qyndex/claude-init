"""Concrete fixed-query adapter fixtures: real Git blobs and synthetic upstream PR facts."""
import importlib.util
import json
import os
from pathlib import Path
import sys


def attach(state_class, work, directory, pull_requests=None):
    spec = importlib.util.spec_from_file_location('fixture_batch_api', Path('.claude/scripts/factory-git-state.py'))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    executable = Path(directory)/'blob-provider-bin'; executable.mkdir(exist_ok=True)
    if pull_requests is not None:
        (executable/'pull-requests.json').write_text(json.dumps(pull_requests))
    stub = executable/'gh'
    stub.write_text('#!'+sys.executable+'\n'+'''import json,pathlib,subprocess,sys
payload=json.load(sys.stdin);values=payload['variables']
assert sys.argv[1:]==['api','--hostname','github.com','--method','POST','graphql','--input','-']
assert 'mutation' not in payload['query'] and values['owner']+'/'+values['name']=='org/repo'
repository={'databaseId':101,'nameWithOwner':'org/repo'}
if payload['query'].startswith('query ReceiptPullRequests('):
 facts=json.loads(pathlib.Path('''+repr(str(executable/'pull-requests.json'))+''').read_bytes())
 for n in range(len(values)-2):
  number=values['n'+str(n)];pr=facts[str(number)]
  repository['p'+str(n)]={'number':pr['number'],'merged':pr['merged'],'mergedAt':pr['merged_at'],'mergeCommit':{'oid':pr['merge_commit_sha']},'baseRepository':{'databaseId':pr['base']['repo']['id'],'nameWithOwner':pr['base']['repo']['full_name']}}
else:
 assert payload['query'].startswith('query ReceiptBlobs(')
 objects=[values['oid'+str(n)] for n in range(len(values)-2)]
 result=subprocess.run(['git','-C','''+repr(str(work))+''','cat-file','--batch'],input=('\\n'.join(objects)+'\\n').encode(),capture_output=True,check=True).stdout
 for n,expected in enumerate(objects):
  header,unused,result=result.partition(b'\\n');oid,kind,size=header.decode().split();size=int(size)
  raw,result=result[:size],result[size+1:]
  assert oid==expected and kind=='blob'
  repository['o'+str(n)]={'__typename':'Blob','oid':oid,'byteSize':len(raw),'isBinary':False,'isTruncated':False,'text':raw.decode('utf-8')}
 assert not result
print(json.dumps({'data':{'repository':repository}}))
''')
    stub.chmod(0o755)

    def invoke(self, name, repository_id, selectors):
        before = os.environ.get('PATH')
        os.environ['PATH'] = str(executable)+os.pathsep+(before or '')
        try:
            return getattr(module.API(self.repo, 'offline-fixture-token'),name)(repository_id, selectors)
        finally:
            if before is None:del os.environ['PATH']
            else:os.environ['PATH'] = before
    def read_blobs(self, repository_id, entries):
        return invoke(self,'read_blobs',repository_id,entries)
    state_class.read_blobs = read_blobs
    if pull_requests is not None:
        def read_pull_requests(self, repository_id, numbers):
            return invoke(self,'read_pull_requests',repository_id,numbers)
        state_class.read_pull_requests=read_pull_requests
