#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PYTEST'
import copy,hashlib,importlib.util,json,os,sqlite3,subprocess,sys,tempfile
from unittest.mock import patch
from pathlib import Path
root=Path(sys.argv[1]);helper=root/'.claude/scripts/factory-claude-probe.py';assert helper.exists(),'bounded native subscription capability probe absent'
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
m=module('routing',root/'.claude/scripts/factory-routing.py');native=module('native_probe',helper)
def reject(fn):
    try:fn()
    except (ValueError,KeyError,TypeError,OSError):return
    raise AssertionError('invalid routing accepted')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
with tempfile.TemporaryDirectory() as temporary:
    base=Path(temporary).resolve();private=base/'private';private.mkdir(mode=0o700);candidate=base/'app';candidate.mkdir();(candidate/'src').mkdir();(candidate/'src/main.py').write_text('print("app")\n')
    subprocess.run(['/usr/bin/git','init','-q',str(candidate)],check=True);subprocess.run(['/usr/bin/git','-C',str(candidate),'add','src/main.py'],check=True)
    cli=private/'claude';cli.write_text('''#!/usr/bin/env python3
import json,sys,os
from pathlib import Path
args=sys.argv[1:]
if '--version' in args:print('fixture Claude CLI 1')
elif '--help' in args:print('--safe-mode --tools --strict-mcp-config --mcp-config --no-session-persistence --disable-slash-commands --model --output-format --print')
elif args[:2]==['auth','status']:print(json.dumps({'loggedIn':os.environ.get('CLAUDE_CODE_OAUTH_TOKEN') in {'fixture-implementation','fixture-review'},'authMethod':'fixture-auth','apiProvider':'firstParty','subscriptionType':'max'}))
else:
    model=args[args.index('--model')+1]
    if 'fixture-worker' in args:Path(__file__).with_name('worker-started').write_text('started')
    print(json.dumps({'type':'result','subtype':'success','is_error':False,'modelUsage':{('wrong-model' if 'malformed-worker' in args else model):{'inputTokens':1,'outputTokens':1}},'total_cost_usd':0.125,'result':'OK'}))
''');cli.chmod(0o755)
    executable=Path(sys.executable).resolve();model='fixture-model'
    def runtime(location,method='fixture-auth'):
        return {'kind':'claude-cli','model':model,'billing':'subscription','location':location,'allowed_model_usage':[model],
                'command':[str(cli),'--safe-mode','--model','{model}','--output-format','json','--no-session-persistence','--print','fixture-worker','{task}'],
                'probe':{'argv':[str(executable),str(helper),'--binary',str(cli),'--model','{model}','--auth-method',method,'--subscription-type','max','--live'],
                         'trusted_files':{str(path):sha(path) for path in [executable,helper,cli,root/'.claude/scripts/factory-supervisor.py',root/'.claude/scripts/factory-runtime.py']},'timeout':30}}
    generic=private/'generic-probe.py';generic.write_text('import json\nprint(json.dumps('+repr({'schema_version':1,'available':True,'model':None,'capabilities':['acceptance-accounting','security-scan','isolated-run'],'version':'fixture','quota':'unknown','reset_at':None,'estimated_api_usd':None,'actual_spend_usd':None})+'))\n')
    command_runtime={'kind':'command','model':None,'billing':'unknown','location':'actions','allowed_model_usage':[],'command':['/usr/bin/true'],
                     'probe':{'argv':[str(executable),str(generic)],'trusted_files':{str(executable):sha(executable),str(generic):sha(generic),'/usr/bin/true':sha(Path('/usr/bin/true'))},'timeout':5}}
    profile={'schema_version':1,'enabled':True,'repository':'org/repo','source_roots':['src'],'stacks':{'python':{'tools':[str(executable)],'acceptance':[str(executable),'-m','pytest']}},
             'runtimes':{'primary':runtime('local','wrong-auth'),'fallback':runtime('local'),'reviewer':runtime('actions'),'checks':command_runtime},
             'roles':{role:{'primary':name,'fallbacks':['fallback'] if role in {'planning','implementation'} else [],'capabilities':sorted(m.FLOORS[role])} for role,name in [('planning','primary'),('implementation','primary'),('review','reviewer'),('verification','checks'),('security','checks')]}}
    config=private/'profile.json';config.write_text(json.dumps(profile));config.chmod(0o600);assert m.protected(config,[candidate])==profile
    os.environ['FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN']='fixture-implementation'
    os.environ['FACTORY_REVIEW_CLAUDE_OAUTH_TOKEN']='fixture-review'
    os.environ['CLAUDE_CODE_OAUTH_TOKEN']='coordinator-must-not-forward'
    profile['runtimes']['reviewer']['probe']['argv']+=['--credential-kind','review']
    assert m.choose(profile,'review','actions',candidate)['runtime']=='reviewer'
    with patch.dict(os.environ,{'FACTORY_REVIEW_CLAUDE_OAUTH_TOKEN':''}):
        assert m.choose(profile,'review','actions',candidate)['blocked']=='capacity-unavailable'
    decision=m.choose(profile,'implementation','local',candidate);assert decision['runtime']=='fallback' and decision['fallback_index']==1 and decision['fallback_reason']=='primary-unavailable' and decision['independent_verdict'] is False
    assert native.observe(cli,model,'fixture-auth','max',False)['available'] is False
    assert native.observe(cli,model,'fixture-auth','max',True)['estimated_api_usd']==0.125
    print('AC-1: protected profile, pinned real subprocess probes, strict native auth/model JSON and explicit equivalent fallback select the configured model without claiming independent verification')
    store=m.supervisor.runtime.Store(private/'runtime.sqlite');Path(store.path).chmod(0o600);store.enqueue('T-1','a'*64,[])
    result=m.run(profile,'implementation','local',candidate,Path(store.path),'T-1',private/'attempts',timeout=10)
    assert result['worker_started'] is True and result['engineering_verified'] is False and result['actual_spend_usd'] is None and result['estimated_api_usd']==0.125 and result['usage_scope']=='conversation'
    assert store.get('T-1')['state']=='verifying' and (private/'worker-started').exists()
    with store.transaction() as db:assert db.execute('SELECT COUNT(*) FROM runtime_route_events').fetchone()[0]==1
    malformed=copy.deepcopy(profile)
    malformed['runtimes']['fallback']['command'].append('malformed-worker')
    store.enqueue('T-4','a'*64,[])
    invalid=m.run(malformed,'implementation','local',candidate,Path(store.path),'T-4',private/'attempts',timeout=10)
    assert invalid['exit_code']==2 and invalid['reason']=='structured-runtime-outcome-invalid' and store.get('T-4')['state']=='blocked'
    print('AC-2: actual routed foreground worker persists model/token/client-estimate observations privately, advances only to verifying and never equates subscription spend with API estimates')
    exhausted=copy.deepcopy(profile);quota=private/'quota.py';quota.write_text('import json\nprint(json.dumps('+repr({'schema_version':1,'available':False,'model':model,'capabilities':sorted(native.CAPABILITIES),'version':'quota fixture','quota':'exhausted','reset_at':'2026-10-13T10:00:00Z','estimated_api_usd':None,'actual_spend_usd':None})+'))\n')
    exhausted['runtimes']['primary']['probe']={'argv':[str(executable),str(quota)],'trusted_files':{str(executable):sha(executable),str(quota):sha(quota),str(cli):sha(cli)},'timeout':5};exhausted['roles']['implementation']['fallbacks']=[]
    store.enqueue('T-2','a'*64,[]);(private/'worker-started').unlink()
    result=m.run(exhausted,'implementation','local',candidate,Path(store.path),'T-2',private/'attempts',timeout=10)
    assert result['blocked']=='capacity-unavailable' and result['worker_started'] is False and store.get('T-2')['state']=='queued' and store.get('T-2')['attempt']==0 and not (private/'worker-started').exists()
    assert m.choose(exhausted,'implementation','local',candidate)['observations'][0]['observation']['reset_at']=='2026-10-13T10:00:00Z'
    print('AC-3: exhausted capacity checkpoints a durable route decision, keeps approved task queued with no attempt and requires explicit equivalent fallback without relaxing role requirements')
    for changed in [{'roles':{**profile['roles'],'review':profile['roles']['implementation']}},{'stacks':{}},{'source_roots':['../secret']}]:reject(lambda changed=changed:m.validate({**profile,**changed}))
    weak=copy.deepcopy(profile);weak['roles']['review']['capabilities']=['foreground'];reject(lambda:m.validate(weak))
    (candidate/'src/main.rs').write_text('fn main() {}');reject(lambda:m.choose(profile,'implementation','local',candidate));(candidate/'src/main.rs').unlink()
    (candidate/'src/main.xyz').write_text('unsupported');reject(lambda:m.choose(profile,'implementation','local',candidate));(candidate/'src/main.xyz').unlink()
    config.chmod(0o644);reject(lambda:m.protected(config,[candidate]));config.chmod(0o600)
    marker=private/'fsmonitor-executed';evil=private/'fsmonitor';evil.write_text('#!/bin/sh\ntouch '+str(marker)+'\n');evil.chmod(0o755)
    subprocess.run(['/usr/bin/git','-C',str(candidate),'config','core.fsmonitor',str(evil)],check=True);assert m.stack_readiness(profile,candidate)==['python'] and not marker.exists()
    ledger=module('ledger',root/'.claude/scripts/factory-ledger.py')
    authority=base/'authority';(authority/'specs/active').mkdir(parents=True);(authority/'tasks').mkdir()
    approved=authority/'specs/active/001-fixture.md';approved.write_text('---\nid: 001\nstatus: approved\n---\n\n1. **AC-1**: fixture\n')
    (authority/'tasks/TASKS.md').write_text('## Active\n- [ ] T-3 | spec:001 | deps:\n')
    policy={'repository':'org/repo','specs':{'001':{'path':'specs/active/001-fixture.md','sha256':sha(approved),'ac_ids':['AC-1'],'allowed_paths':['src/*']}},'runtime':{'services':[],'routing_profile_sha256':hashlib.sha256(m.canonical(exhausted).encode()).hexdigest(),'roles_by_task':{'T-3':'implementation'}}}
    config.write_text(json.dumps(exhausted));policy_path=authority/'policy.json';policy_path.write_text(json.dumps(policy))
    reject(lambda:ledger.routing_contract(policy,config,authority,candidate,private/'fresh.sqlite','T-3','planning'))
    altered=copy.deepcopy(policy);altered['runtime']['routing_profile_sha256']='0'*64
    reject(lambda:ledger.routing_contract(altered,config,authority,candidate,private/'fresh.sqlite','T-3'))
    prefix=[str(executable),str(root/'.claude/scripts/factory-ledger.py'),'--authority-root',str(authority),'--policy',str(policy_path),'--db',str(private/'fresh.sqlite'),'--task','T-3','--cwd',str(candidate),'--attempts',str(private/'ledger-attempts'),'--routing-config',str(config)]
    result=subprocess.run(prefix,capture_output=True,text=True);assert result.returncode==2,result.stderr
    observed=json.loads(result.stdout);assert observed['blocked']=='capacity-unavailable' and observed['worker_started'] is False
    assert ledger.runtime.Store(private/'fresh.sqlite').get('T-3')['attempt']==0
    assert subprocess.run([*prefix,'--','/usr/bin/true'],capture_output=True).returncode!=0
    assert subprocess.run([arg for arg in prefix if arg not in {'--routing-config',str(config)}]+['--','/usr/bin/true'],capture_output=True).returncode!=0
    with sqlite3.connect(private/'fresh.sqlite') as db:db.execute("UPDATE runtime_route_repository SET repository='foreign/repo'")
    reject(lambda:ledger.routing_contract(policy,config,authority,candidate,private/'fresh.sqlite','T-3'))
    config.write_text(json.dumps(profile))
    cli.write_text(cli.read_text()+'\n# changed runtime\n');reject(lambda:m.choose(profile,'implementation','local',candidate))
    print('AC-4: unsupported stacks/extensions, missing capabilities, wrong authority location, unsafe config modes and changed executable pins block; candidate fsmonitor hooks do not execute; actual approved-ledger CLI rejects profile/task-role/command overrides and foreign namespaces')
PYTEST
