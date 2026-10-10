#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import copy,hashlib,importlib.util,json,os,sys,types
from datetime import datetime,timedelta,timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
root=Path(sys.argv[1]);path=root/'.claude/scripts/factory-git-state.py'
m=types.ModuleType('hosted');m.__file__=str(path)
source=Path(os.environ.get('POLICY_APPROVAL_SOURCE',str(path)))
exec(compile(source.read_text(),str(path),'exec'),m.__dict__)
assert hasattr(m,'attest_policy'), 'protected no-bypass policy approval not implemented'
now=datetime(2026,10,10,2,tzinfo=timezone.utc)
policy={'id':7,'name':'state-protection','target':'branch','source_type':'Repository','source':'org/repo',
        'enforcement':'active','bypass_actors':[],'conditions':{'ref_name':{'include':['refs/heads/state'],'exclude':[]}},
        'rules':[{'type':'deletion'},{'type':'non_fast_forward'}],'node_id':'RRS_fixture',
        'created_at':'2026-10-10T00:00:00Z','updated_at':'2026-10-10T01:00:00.410Z'}
class API:
    repo='org/repo'
    def __init__(self,p):self.policy=p
    def request(self,path):assert path=='repos/org/repo/rulesets/7';return copy.deepcopy(self.policy)
def reject(fn):
    try:fn()
    except (ValueError,KeyError,TypeError):return
    raise AssertionError('unsafe policy approval accepted')
hidden=copy.deepcopy(policy);hidden.pop('bypass_actors')
reject(lambda:m.verify_policy(hidden,'org/repo',7,now=now))
m.verify_policy(policy,'org/repo',7,now=now)
bypass=copy.deepcopy(policy);bypass['bypass_actors']=[{'actor_type':'RepositoryRole','actor_id':5}]
reject(lambda:m.verify_policy(bypass,'org/repo',7,now=now))
reject(lambda:m.attest_policy(API(hidden),7,now));reject(lambda:m.attest_policy(API(bypass),7,now))
approved=m.attest_policy(API(policy),7,now);approvals={'7':approved}
m.verify_policy(hidden,'org/repo',7,approvals,now)
# GitHub varies timezone formatting and an actor-relative field; normalize only those differences.
zone=copy.deepcopy(hidden);zone['created_at']='2026-10-10T11:00:00+11:00';zone['updated_at']='2026-10-10T12:00:00.410+11:00';zone['current_user_can_bypass']=False
m.verify_policy(zone,'org/repo',7,approvals,now)
for key,value in [('id',8),('source','foreign/repo'),('target','tag'),('source_type','Organization'),('name','changed'),('node_id','changed'),('conditions',{}),('rules',[]),('updated_at','2026-10-10T01:00:00.411Z'),('created_at','2026-10-10T00:00:01Z')]:
    changed=copy.deepcopy(hidden);changed[key]=value;reject(lambda:m.verify_policy(changed,'org/repo',7,approvals,now))
for key,value in [('schema_version',True),('repository','foreign/repo'),('ruleset_id',8),('bypass_actors',[{}]),('policy_sha256','f'*64),('observed_at','2026-10-10T02:00:01Z'),('observed_at','2026-10-10T01:00:01Z')]:
    bad=copy.deepcopy(approved);bad[key]=value;reject(lambda:m.verify_policy(hidden,'org/repo',7,{'7':bad},now))
for missing in ('rules','updated_at','source'):
    changed=copy.deepcopy(policy);changed.pop(missing);reject(lambda:m.attest_policy(API(changed),7,now))
recent=copy.deepcopy(policy);recent['updated_at']=m.digest.stamp(now-timedelta(seconds=59));reject(lambda:m.attest_policy(API(recent),7,now))
wrong=copy.deepcopy(policy);wrong['source']='foreign/repo';reject(lambda:m.attest_policy(API(wrong),7,now))
wrong=copy.deepcopy(policy);wrong['enforcement']='disabled';reject(lambda:m.attest_policy(API(wrong),7,now))
# Actual GitState consumes the approval before it imports any state bytes.
class StateAPI(API):
    def request(self,path):
        suffix=path.removeprefix('repos/org/repo')
        if suffix=='':return {'full_name':self.repo,'archived':False,'default_branch':'main','private':False}
        if suffix=='/rules/branches/state':return [{'type':kind,'ruleset_id':7} for kind in ('deletion','non_fast_forward')]
        if suffix=='/rulesets/7':return copy.deepcopy(self.policy)
        if suffix=='/git/ref/heads/state':return {'ref':'refs/heads/state','object':{'type':'commit','sha':'a'*40}}
        if suffix=='/git/commits/'+'a'*40:return {'sha':'a'*40,'tree':{'sha':'b'*40}}
        if suffix=='/git/trees/'+'b'*40+'?recursive=1':return {'truncated':False,'tree':[]}
        raise AssertionError(path)
stream=hashlib.sha256(m.canonical(['org/repo','C1','main']).encode()).hexdigest()
reject(lambda:m.GitState(StateAPI(hidden),'state',stream,'a'*40))
assert m.GitState(StateAPI(hidden),'state',stream,'a'*40,approvals).bytes is None

spec=importlib.util.spec_from_file_location('operator',root/'.claude/scripts/factory-attest-state-policy.py')
operator=importlib.util.module_from_spec(spec);spec.loader.exec_module(operator)
client=operator.OperatorAPI('org/repo')
def envelope(command,**kwargs):
    assert command==['gh','api','--hostname','github.com','--method','GET','repos/org/repo/rulesets/7']
    assert 'input' not in kwargs and 'env' not in kwargs
    return SimpleNamespace(returncode=0,stdout=json.dumps(policy).encode(),stderr=b'')
with patch.object(operator.subprocess,'run',envelope):assert client.request('repos/org/repo/rulesets/7')['bypass_actors']==[]
reject(lambda:client.request('repos/foreign/repo/rulesets/7'));reject(lambda:client.request('repos/org/repo/git/refs'))
workflow=(root/'.github/workflows/factory-hosted-digest.yml').read_text()
assert 'FACTORY_REPORTING_POLICY_APPROVALS: ${{ vars.FACTORY_REPORTING_POLICY_APPROVALS }}' in workflow
assert "'policy_approvals':json.loads(" in workflow and 'FACTORY_APP_PRIVATE_KEY' not in workflow
assert 'administration:' not in workflow
print('factory-policy-approval: hidden-field rejection, visible no-bypass approval, settled UTC fingerprint, changed policy/source/clock rejection and GET-only credential separation passed')
PYTEST
