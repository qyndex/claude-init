#!/usr/bin/env bash
set -euo pipefail
ROOT="${REPORTING_ACTIONS_TEST_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import copy,importlib.util,os,sys,tempfile
assert (Path(sys.argv[1])/'.claude/scripts/factory-reporting-preflight.py').is_file(), 'protected reporting Actions not implemented'
spec=importlib.util.spec_from_file_location('preflight',Path(sys.argv[1])/'.claude/scripts/factory-reporting-preflight.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def reject(fn):
    try:fn()
    except (ValueError,OSError):return
    raise AssertionError('unsafe reporting runner accepted')
class API:
    repo='org/repo'
    def __init__(self):
        self.repository={'id':1,'full_name':self.repo,'default_branch':'main','private':False,'owner':{'type':'Organization','login':'org'}}
        self.group={'id':7,'name':'factory-reporting','default':False,'visibility':'selected','restricted_to_workflows':True,'selected_workflows':['org/repo/.github/workflows/factory-digest.yml@refs/heads/main'],'allows_public_repositories':True}
        self.repositories=[{'id':1,'full_name':self.repo}]
        self.runners=[{'status':'online','os':'linux','labels':[{'name':'self-hosted'},{'name':'factory-reporting'}]}]
    def get(self,path):return self.repository if path.startswith('repos/') else self.group
    def request(self,path,**opts):
        assert opts['paginate'] is True
        return [{'repositories':self.repositories}] if path.endswith('/repositories') else [{'runners':self.runners}]
api=API();assert m.policy(api,7,'refs/heads/main')['group']=='org/factory-reporting'
reject(lambda:m.policy(api,7,'refs/heads/feature'))
for field,value in [('default',True),('visibility','all'),('restricted_to_workflows',False),('selected_workflows',['org/repo/.github/workflows/ci.yml@refs/heads/main']),('name','injected\nname')]:
    bad=copy.deepcopy(api);bad.group[field]=value;reject(lambda:m.policy(bad,7,'refs/heads/main'))
bad=copy.deepcopy(api);bad.repository['full_name']='foreign/repo';reject(lambda:m.policy(bad,7,'refs/heads/main'))
bad=copy.deepcopy(api);bad.repositories.append({'id':2,'full_name':'org/other'});reject(lambda:m.policy(bad,7,'refs/heads/main'))
for field,value in [('status','offline'),('os','windows'),('labels',[])]:
    bad=copy.deepcopy(api);bad.runners[0][field]=value;reject(lambda:m.policy(bad,7,'refs/heads/main'))
with tempfile.TemporaryDirectory() as tmp:
    root=Path(tmp);state=root/'state';state.mkdir(mode=0o700);workspace=root/'workspace';workspace.mkdir()
    env={'GITHUB_REPOSITORY':'org/repo','FACTORY_REPORTING_STATE_DIR':str(state),'FACTORY_REPORTING_CHANNEL':'C1','FACTORY_REPORTING_TEAM_ID':'T1','FACTORY_REPORTING_START':'2026-10-01T00:00:00Z','GITHUB_WORKSPACE':str(workspace)}
    result=m.runtime_config(env);assert result['database']==str(state.resolve()/'reporting.sqlite') and not (state/'reporting.sqlite').exists()
    assert not any('TOKEN' in field for field in result)
    state.chmod(0o755);reject(lambda:m.runtime_config(env));state.chmod(0o700)
    nested=workspace/'state';nested.mkdir(mode=0o700);reject(lambda:m.runtime_config(dict(env,FACTORY_REPORTING_STATE_DIR=str(nested))))
    link=root/'link';link.symlink_to(state);reject(lambda:m.runtime_config(dict(env,FACTORY_REPORTING_STATE_DIR=str(link))))
    db=state/'reporting.sqlite';db.touch(mode=0o644);reject(lambda:m.runtime_config(env));db.chmod(0o600);assert m.runtime_config(env)['enabled'] is True
    reject(lambda:m.runtime_config(dict(env,FACTORY_REPORTING_START='2026-10-01T00:00:00')))
workflow=(Path(sys.argv[1])/'.github/workflows/factory-digest.yml').read_text()
assert 'pull_request:' not in workflow and 'pull_request_target:' not in workflow
assert 'FACTORY_APP_PRIVATE_KEY' not in workflow and 'contents: write' not in workflow and 'pull-requests: write' not in workflow
assert "vars.FACTORY_REPORTING_ENABLED == 'true'" in workflow and 'environment: factory-reporting' in workflow
assert 'needs: preflight' in workflow and 'group: ${{ needs.preflight.outputs.group }}' in workflow
assert 'ref: ${{ github.sha }}' in workflow and 'persist-credentials: false' in workflow
print('factory-reporting-actions: restricted workflow/repository/runner policy, POSIX private state and workspace exclusion passed')
PY
