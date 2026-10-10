#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
import importlib.util,json,os,sys
from pathlib import Path
root=Path(sys.argv[1]);spec=importlib.util.spec_from_file_location('slack',root/'.claude/scripts/factory-slack-digest.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
os.environ['FACTORY_SLACK_BOT_TOKEN']='xoxb-fixture'
class Response:
    def __init__(self,scopes,body):self.headers={'x-oauth-scopes':scopes};self.body=body
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def read(self,limit):return json.dumps(self.body).encode()
class Opener:
    def __init__(self,scopes):self.scopes=scopes;self.requests=[];self.bad=False
    def open(self,request,timeout):
        self.requests.append(request)
        assert request.full_url.startswith('https://slack.com/api/')
        assert not any(x in request.full_url for x in ['Upload','complete','postMessage'])
        body={'ok':True,'team_id':'T1','bot_id':'B1'} if request.full_url.endswith('auth.test') else {'ok':True,'messages':[]}
        if self.bad:body={'ok':False,'error':'invalid_auth'}
        return Response(self.scopes,body)
def rejects(fn):
    try:fn()
    except ValueError:return
    raise AssertionError('missing grant accepted')
c=m.http_client({'attachments_enabled':True});c.opener=Opener('files:write, groups:history,files:read')
assert hasattr(c,'verify_attachment_scopes'), 'attachment scope preflight is absent'
m.preflight(c,'T1','C1');c.verify_attachment_scopes();assert len(c.opener.requests)==2
print('AC-1: inherited attachment HTTP reads authenticated granted scopes without upload or message')
for scopes in ['', 'files:read','files:write','files:read.extra,files:write', 'Files:read,files:write']:
    c.opener=Opener(scopes);m.preflight(c,'T1','C1');rejects(c.verify_attachment_scopes)
print('AC-2: absent partial and similar-name grants fail closed')
c.opener=Opener('files:read,files:write');m.preflight(c,'T1','C1');c.verify_attachment_scopes()
c.opener=Opener('groups:history');m.preflight(c,'T1','C1');rejects(c.verify_attachment_scopes)
c.opener.bad=True;rejects(lambda:m.preflight(c,'T1','C1'))
print('AC-3: successful reauthentication replaces stale grants and API failure blocks preflight')
workflow=(root/'.github/workflows/factory-hosted-digest.yml').read_text();assert "if config['attachments_enabled']:\n              client.verify_attachment_scopes()" in workflow
legacy=m.http_client({'attachments_enabled':False});legacy.opener=Opener('groups:history');m.preflight(legacy,'T1','C1')
print('AC-4: protected opt-in workflow gates attachments and legacy reporting needs no file grants')
PY
