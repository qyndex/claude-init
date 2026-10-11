#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import importlib.util,json,os,sqlite3,sys,tempfile
from pathlib import Path
from unittest.mock import patch
root=Path(sys.argv[1]);spec=importlib.util.spec_from_file_location('supervisor',root/'.claude/scripts/factory-supervisor.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
assert callable(getattr(m,'worker_environment',None)),'worker authority credentials are not isolated from inherited environment'
forbidden=['GH_TOKEN','GITHUB_TOKEN','FACTORY_APP_PRIVATE_KEY','FACTORY_FEEDBACK_STATE_KEY','FACTORY_SLACK_BOT_TOKEN','FACTORY_REPORTING_STATE_TOKEN','AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_SESSION_TOKEN','ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_OAUTH_TOKEN','PYTHONPATH','PYTHONSTARTUP','LD_PRELOAD','DYLD_INSERT_LIBRARIES','FACTORY_UNKNOWN_AUTHORITY','HTTP_PROXY','HTTPS_PROXY']
source={name:'fixture-authority-only' for name in forbidden};source.update(PATH=os.environ['PATH'],HOME=os.environ['HOME'],LANG='C',FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN='fixture-worker-only')
env=m.worker_environment(source)
assert all(name not in env for name in forbidden if name!='CLAUDE_CODE_OAUTH_TOKEN')
assert env['CLAUDE_CODE_OAUTH_TOKEN']=='fixture-worker-only' and 'FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN' not in env
assert env['PATH']==source['PATH'] and env['HOME']==source['HOME'] and env['LANG']=='C'
assert 'CLAUDE_CODE_OAUTH_TOKEN' not in m.worker_environment({name:source[name] for name in forbidden})
print('AC-1: deny-by-default environment drops GitHub/App/Slack/encryption/cloud/provider credentials, proxy and interpreter injection while preserving explicit ordinary runtime settings')
with tempfile.TemporaryDirectory() as temporary:
    root=Path(temporary);database=root/'runtime.sqlite';store=m.runtime.Store(database);store.enqueue('T-1','a'*64,[])
    worker=[sys.executable,'-c','import json,os;from pathlib import Path;Path(os.environ["FACTORY_RUN_DIR"],"observed.json").write_text(json.dumps(dict(os.environ)))']
    with patch.dict(os.environ,source):assert m.supervise(database,'T-1',worker,root,root/'attempts',timeout=10,lease=3)==0
    attempt=next((root/'attempts').glob('T-1-*'));observed=json.loads((attempt/'observed.json').read_text())
    assert all(name not in observed for name in forbidden if name!='CLAUDE_CODE_OAUTH_TOKEN') and observed['CLAUDE_CODE_OAUTH_TOKEN']=='fixture-worker-only'
    assert observed['TMPDIR']==observed['FACTORY_RUN_DIR']==str(attempt.resolve()) and observed['FACTORY_RESOURCE_NAMESPACE']==attempt.name
    assert store.get('T-1')['state']=='verifying' and not json.loads((attempt/'outcome.json').read_text())['engineering_verified']
    print('AC-2: actual foreground worker through guardian receives only the dedicated implementation subscription credential and assigned run namespace; success grants no engineering or merge verdict')
    store.enqueue('T-2','a'*64,[])
    with patch.dict(os.environ,{name:'fixture-authority-only' for name in forbidden}):assert m.supervise(database,'T-2',worker,root,root/'attempts',timeout=10,lease=3)==0
    second=next((root/'attempts').glob('T-2-*'));observed=json.loads((second/'observed.json').read_text());assert all(name not in observed for name in forbidden)
    print('AC-3: absent explicit implementation credential does not borrow coordinator/reviewer OAuth or API keys; real worker still records a bounded supervised verifying outcome')
    store.enqueue('T-3','a'*64,[])
    assert m.supervise(database,'T-3',[sys.executable,'-c','import time;time.sleep(30)'],root,root/'attempts',timeout=1,lease=3)==1
    assert store.get('T-3')['state']=='blocked'
    print('AC-4: filtered worker environment preserves actual timeout cleanup and lease fencing; native same-user filesystem access remains an explicitly unproven isolation boundary')
PYTEST
