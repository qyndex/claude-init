#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy,importlib.util,sys
from pathlib import Path
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-slack-file-canary.py';assert path.exists(),'one-allocation live file canary is absent'
spec=importlib.util.spec_from_file_location('canary',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
fixture=(root/'.claude/scripts/test/factory-slack-attachment.sh').read_text().split("<<'PYTEST'\n",1)[1].split('fixture=',1)[0];ns={};exec(fixture,ns)
class Client(ns['Client']):
    def verify_attachment_scopes(self):assert not self.bad_scope,'file scope missing'
    bad_scope=False
class API:
    repo='org/repo'
    def __init__(self):self.count=1;self.identity=100
    def request(self,path,method='GET',payload=None):
        assert method=='GET' and payload is None and path=='repos/org/repo/actions/workflows/factory-slack-file-canary.yml/runs?per_page=100'
        return {'total_count':self.count,'workflow_runs':[{'id':self.identity,'head_branch':'main','event':'workflow_dispatch'}]}
def rejects(fn):
    try:fn()
    except (ValueError,AssertionError):return
    raise AssertionError('canary allocated despite uncertainty')
config={'enabled':True,'attachments_enabled':True,'repository':'org/repo','destination':'C1','team_id':'T1','branch':'main'}
a=API();c=Client();result=m.run(config,a,c,100,1);assert result['status']=='verified-new' and c.allocations==c.posts==1, (result,c.allocations,c.posts)
assert b'ATTACHMENT ACTIVATION CANARY' in c.bytes and b'daily reporting state is unchanged' in c.bytes, c.bytes
print('AC-1: real attachment fixture proves isolated labelled bytes and exact private file receipt')
a.count=2;assert m.run(config,a,c,101,1)['status']=='verified-existing' and c.allocations==1
assert m.run(config,a,c,100,2)['status']=='verified-existing' and c.allocations==1
print('AC-2: fresh invocation and retry verify existing receipt without another allocation')
for count,identity,attempt in [(2,100,1),(1,101,1),(1,100,2),(0,100,1)]:
 a=API();a.count=count;a.identity=identity;c=Client();rejects(lambda:m.run(config,a,c,100,attempt));assert c.allocations==0
lost=Client();lost.drop=True;a=API();rejects(lambda:m.run(config,a,lost,100,1));assert lost.allocations==1
lost.hidden=True;rejects(lambda:m.run(config,a,lost,100,2));assert lost.allocations==1
lost.hidden=False;assert m.run(config,a,lost,100,2)['status']=='verified-existing' and lost.allocations==1
print('AC-3: previous ambiguous and lost-response runs fail closed or reconcile without reallocation')
for changed in [{'enabled':False},{'attachments_enabled':False},{'repository':'foreign/repo'}]:
 c=Client();rejects(lambda:m.run(dict(config,**changed),API(),c,100,1));assert c.allocations==0
c=Client();c.bad_scope=True;rejects(lambda:m.run(config,API(),c,100,1));assert c.allocations==0
workflow=(root/'.github/workflows/factory-slack-file-canary.yml').read_text();assert 'contents: read' in workflow and 'actions: read' in workflow and 'environment: factory-reporting' in workflow and 'factory-reporting-${{ github.repository }}' in workflow
print('AC-4: disabled foreign missing-grant inputs block and protected workflow has read-only Git permissions')
PY
