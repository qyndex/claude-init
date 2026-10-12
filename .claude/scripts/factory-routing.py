#!/usr/bin/env python3
"""Protected role routing; capability probes never replace independent verdicts."""
import argparse
from datetime import datetime,timezone
import hashlib
import importlib.util
import json
import math
import os
import pwd
from pathlib import Path
import re
import signal
import sqlite3
import stat
import subprocess
import tempfile
import time
import uuid

class LazySupervisor:
    def __init__(self):self.module=None
    def __getattr__(self,name):
        if self.module is None:
            spec=importlib.util.spec_from_file_location('supervisor',Path(__file__).with_name('factory-supervisor.py'))
            self.module=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.module)
        return getattr(self.module,name)

supervisor=LazySupervisor()
FLOORS={'planning':{'foreground','model-selection','structured-output'},'implementation':{'foreground','model-selection','structured-output'},'review':{'foreground','model-selection','structured-output','tool-free','separate-run'},'verification':{'acceptance-accounting','isolated-run'},'security':{'security-scan','isolated-run'},'browser':{'browser-e2e','isolated-run'},'reporting':{'delivery-receipts','durable-state'}}
LOCATIONS={'planning':'local','implementation':'local','review':'actions','verification':'actions','security':'actions','browser':'actions','reporting':'actions'}
FIELDS={'schema_version','enabled','repository','source_roots','stacks','roles','runtimes'}
SOURCE_TYPES={'.py':'python','.js':'typescript','.jsx':'typescript','.ts':'typescript','.tsx':'typescript','.vue':'typescript','.svelte':'typescript','.rs':'rust','.go':'go','.java':'java','.kt':'java','.rb':'ruby','.cs':'dotnet','.fs':'dotnet','.php':'php','.sh':'shell','.sql':'sql','.tf':'terraform','.c':'cpp','.h':'cpp','.cpp':'cpp','.hpp':'cpp','.swift':'swift','.ex':'elixir','.exs':'elixir','.dart':'dart','.scala':'scala','.lua':'lua','.zig':'zig'}


def require(condition,message):
    if not condition:raise ValueError(message)


def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)


def decode(raw):
    def pairs(items):
        result={}
        for key,value in items:require(key not in result,'duplicate routing field');result[key]=value
        return result
    return json.loads(raw,object_pairs_hook=pairs,parse_constant=lambda value:(_ for _ in ()).throw(ValueError('nonfinite JSON')))


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def strings(value,minimum=0,maximum=100):
    return isinstance(value,list) and minimum<=len(value)<=maximum and all(isinstance(item,str) and 0<len(item)<=1000 for item in value) and len(set(value))==len(value)


def argv(value):
    return isinstance(value,list) and 1<=len(value)<=40 and all(isinstance(item,str) and len(item)<=20000 and '\0' not in item for item in value) and bool(value[0]) and Path(value[0]).is_absolute()


def relative(value):return isinstance(value,str) and bool(value) and not Path(value).is_absolute() and '..' not in Path(value).parts


ASSESSMENT_CAPABILITIES={'foreground','model-selection','structured-output','tool-free','config-isolation','hook-failure-block'}


def validate_assessment(runtime):
    """Validate only an optional assessment definition; never probe or launch."""
    if 'assessment' not in runtime:
        return
    assessment=runtime['assessment']
    require(runtime['kind']=='claude-cli' and runtime['location']=='local' and isinstance(assessment,dict) and set(assessment)=={'argv','trusted_files','version','capabilities','observation'},'assessment schema invalid')
    version=assessment['version']
    require(isinstance(version,str) and re.fullmatch(r'2\.1\.[0-9]+',version) and int(version.split('.')[2])>=295,'assessment native failure-block version unsupported')
    require(strings(assessment['capabilities']) and set(assessment['capabilities'])==ASSESSMENT_CAPABILITIES,'assessment capability observation incomplete')
    args=assessment['argv'];require(argv(args) and len(args)==18,'assessment argv invalid')
    expected=[args[0],'--print','--model','{model}','--output-format','json','--tools','','--disallowedTools','mcp__*','--strict-mcp-config','--mcp-config',args[12],'--setting-sources','','--settings',args[16],'--no-session-persistence']
    require(args==expected and Path(args[12]).is_absolute() and Path(args[16]).is_absolute(),'assessment argv not exact tool-free foreground contract')
    observation=assessment['observation'];require(isinstance(observation,dict) and set(observation)=={'path','sha256'} and isinstance(observation['path'],str) and Path(observation['path']).is_absolute() and isinstance(observation['sha256'],str) and re.fullmatch(r'[a-f0-9]{64}',observation['sha256']),'assessment observation binding invalid')
    files=assessment['trusted_files'];references={args[0],args[12],args[16],observation['path']}
    require(len(references)==4 and isinstance(files,dict) and set(files)==references,'assessment exact referenced artifact pins required')
    for path,sha in files.items():require(isinstance(sha,str) and re.fullmatch(r'[a-f0-9]{64}',sha),'assessment hash pin invalid')
    require(args[0] in runtime['probe']['trusted_files'] and runtime['probe']['trusted_files'][args[0]]==files[args[0]],'assessment executable not bound to protected planning runtime')
    require(files[observation['path']]==observation['sha256'],'assessment observation pin differs')


def validate(profile):
    require(isinstance(profile,dict) and set(profile) in (FIELDS,FIELDS|{'mandatory_intake'}) and type(profile['schema_version']) is int and profile['schema_version']==1 and type(profile['enabled']) is bool,'routing schema invalid')
    mandatory=profile.get('mandatory_intake')
    if mandatory is not None:
        require(profile['enabled'] and isinstance(mandatory,dict) and set(mandatory)=={'required','contract','database'}
                and mandatory['required'] is True,'mandatory intake descriptor invalid')
        for name in ('contract','database'):
            require(isinstance(mandatory[name],str) and Path(mandatory[name]).is_absolute()
                    and Path(mandatory[name]).resolve()==Path(mandatory[name]),'mandatory intake path invalid')
        require(Path(mandatory['contract']).parent==Path(mandatory['database']).parent,'mandatory intake store binding invalid')
    if not profile['enabled']:
        require(profile['repository'] is None and profile['source_roots']==[] and profile['stacks']=={} and profile['roles']=={} and profile['runtimes']=={},'disabled template must remain neutral');return
    require(isinstance(profile['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',profile['repository']),'routing repository invalid')
    require(strings(profile['source_roots'],1) and all(relative(root) for root in profile['source_roots']),'source roots invalid')
    require(isinstance(profile['stacks'],dict) and bool(profile['stacks']),'explicit stack adapter mapping required')
    for name,adapter in profile['stacks'].items():
        require(re.fullmatch(r'[a-z][a-z0-9_-]{0,31}',name) and isinstance(adapter,dict) and set(adapter)=={'tools','acceptance'} and strings(adapter['tools'],1) and all(Path(tool).is_absolute() for tool in adapter['tools']) and strings(adapter['acceptance'],1),'stack adapter invalid')
        require(Path(adapter['acceptance'][0]).name not in {'true','echo','ls','pwd','printf',':'},'no-op stack acceptance forbidden')
    require(isinstance(profile['roles'],dict) and {'planning','implementation','review','verification','security'}<=set(profile['roles'])<=set(FLOORS) and isinstance(profile['runtimes'],dict) and bool(profile['runtimes']),'required factory roles missing')
    for name,runtime in profile['runtimes'].items():
        require(re.fullmatch(r'[a-z][a-z0-9_-]{0,63}',name) and set(runtime) in ({'kind','model','billing','location','probe','command','allowed_model_usage'}, {'kind','model','billing','location','probe','command','allowed_model_usage','assessment'}),'runtime fields invalid')
        require(runtime['kind'] in {'claude-cli','command'} and runtime['location'] in {'local','actions'},'unsupported runtime/location')
        require(runtime['billing']==('subscription' if runtime['kind']=='claude-cli' else 'unknown'),'metered fallback unsupported in initial runtime')
        require((runtime['kind']=='command' and runtime['model'] is None and runtime['allowed_model_usage']==[]) or (runtime['kind']=='claude-cli' and isinstance(runtime['model'],str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:/-]{0,159}',runtime['model']) and strings(runtime['allowed_model_usage'],1) and runtime['model'] in runtime['allowed_model_usage']),'model usage mapping invalid')
        require(argv(runtime['command']) and not any(arg.split('=',1)[0] in {'--bg','--background','--dangerously-skip-permissions','--allow-dangerously-skip-permissions','--bare'} or arg in {'bypassPermissions','--permission-mode=bypassPermissions'} for arg in runtime['command']),'foreground scoped command required')
        if runtime['kind']=='claude-cli':
            require('{model}' in runtime['command'] and all(flag in runtime['command'] for flag in ('--safe-mode','--model','--output-format','json')) and any(flag in runtime['command'] for flag in ('--print','-p')),'scoped foreground structured model selector missing')
            require(not any(arg=='--settings' or arg.startswith('--settings=') for arg in runtime['command']),'inline authentication/settings override forbidden')
        probe=runtime['probe'];require(set(probe)=={'argv','trusted_files','timeout'} and argv(probe['argv']) and type(probe['timeout']) is int and 1<=probe['timeout']<=30 and isinstance(probe['trusted_files'],dict) and probe['argv'][0] in probe['trusted_files'] and runtime['command'][0] in probe['trusted_files'],'probe definition invalid')
        for path,sha in probe['trusted_files'].items():require(Path(path).is_absolute() and isinstance(sha,str) and re.fullmatch(r'[a-f0-9]{64}',sha),'probe/runtime hash pin invalid')
        validate_assessment(runtime)
    for role,route in profile['roles'].items():
        require(set(route)=={'primary','fallbacks','capabilities'} and isinstance(route['primary'],str) and strings(route['fallbacks'],0,2) and strings(route['capabilities'],1) and FLOORS[role]<=set(route['capabilities']),'role capabilities weakened')
        options=[route['primary'],*route['fallbacks']];require(len(set(options))==len(options),'duplicate fallback')
        for name in options:
            require(name in profile['runtimes'] and profile['runtimes'][name]['location']==LOCATIONS[role],'role authority location differs')
            if role in {'planning','implementation','review'}:require(profile['runtimes'][name]['kind']=='claude-cli','model role requires explicit Claude subscription runtime')
            if role=='review':require('--no-session-persistence' in profile['runtimes'][name]['command'] and not any(arg in {'--continue','--resume','-c','-r'} for arg in profile['runtimes'][name]['command']),'review must be a separate fresh run')

    for name,runtime in profile['runtimes'].items():
        require('assessment' not in runtime or name==profile['roles']['planning']['primary'],'assessment only permitted on primary planning runtime')


def protected(path,candidate_roots):
    require(path.is_absolute() and path.resolve()==path and path.is_file() and not path.is_symlink() and path.stat().st_uid==os.getuid() and stat.S_IMODE(path.stat().st_mode)==0o600,'routing config must be protected owned 0600')
    parent=path.parent;require(parent.stat().st_uid==os.getuid() and stat.S_IMODE(parent.stat().st_mode)==0o700,'routing parent must be private owned 0700')
    for root in candidate_roots:require(root.resolve()!=parent and root.resolve() not in parent.parents,'routing config cannot live in candidate checkout')
    profile=decode(path.read_text());validate(profile);return profile


bounded_spec=importlib.util.spec_from_file_location('bounded_process',Path(__file__).with_name('factory-bounded-process.py'))
bounded=importlib.util.module_from_spec(bounded_spec);bounded_spec.loader.exec_module(bounded)

def stack_readiness(profile,root):
    metadata_env={'PATH':os.defpath,'HOME':'/nonexistent','GIT_CONFIG_NOSYSTEM':'1','GIT_CONFIG_GLOBAL':'/dev/null','GIT_TERMINAL_PROMPT':'0','GIT_OPTIONAL_LOCKS':'0','LC_ALL':'C'}
    git=['/usr/bin/git','-c','core.fsmonitor=false','-c','core.hooksPath=/dev/null','-c','core.untrackedCache=false','-C',str(root)]
    require(Path(bounded.run([*git,'rev-parse','--show-toplevel'],env=metadata_env,cwd=root,timeout=10).stdout.decode().strip()).resolve()==root.resolve(),'routing requires repository root')
    files=bounded.run([*git,'ls-files','--cached','--others','--exclude-standard','-z'],env=metadata_env,cwd=root,timeout=10).stdout.decode().split('\0');detected=set()
    for name in files:
        if not name or name.startswith('.git/'):continue
        if name.startswith('.claude/') and not any(source.startswith('.claude/') and (name==source or name.startswith(source.rstrip('/')+'/')) for source in profile['source_roots']):continue
        language=SOURCE_TYPES.get(Path(name).suffix)
        if language is None:
            require(Path(name).suffix.lower() in {'','.md','.rst','.txt','.json','.yml','.yaml','.toml','.ini','.cfg','.lock','.xml','.csv','.svg','.png','.jpg','.jpeg','.gif','.ico','.html','.css','.scss','.sass','.less','.map','.snap','.sum','.mod','.pdf','.woff','.woff2','.ttf','.eot','.webp','.mp4','.zip','.gitignore','.tfvars'},'unsupported source extension requires reviewed stack adapter');continue
        require(any(source=='.' or name==source or name.startswith(source.rstrip('/')+'/') for source in profile['source_roots']),'application source outside configured roots')
        detected.add(language)
    require(bool(detected),'no declared application source discovered; configure an explicit supported profile')
    require(detected<=set(profile['stacks']),'detected stack lacks configured adapter')
    for name in detected:
        for tool in profile['stacks'][name]['tools']:require(Path(tool).is_file() and os.access(tool,os.X_OK),'stack tool unavailable')
    return sorted(detected)


def pins(runtime):
    for name,sha in runtime['probe']['trusted_files'].items():
        path=Path(name);require(path.resolve()==path and path.is_file() and digest(path)==sha,'runtime/probe pin changed')


def render(argv,model,task=None):
    result=[]
    for value in argv:
        value=value.replace('{model}',model or '')
        if task is not None:value=value.replace('{task}',task)
        require('{model}' not in value and '{task}' not in value,'unresolved runtime placeholder');result.append(value)
    return result


def probe(runtime):
    if runtime['kind']=='claude-cli':require(not any(os.environ.get(name) for name in ('ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY')),'metered provider credential/route forbidden')
    pins(runtime);argv=render(runtime['probe']['argv'],runtime['model'])
    environment=supervisor.worker_environment(os.environ)
    environment.pop('CLAUDE_CODE_OAUTH_TOKEN',None)
    if runtime['kind']=='claude-cli':
        credential='FACTORY_REVIEW_CLAUDE_OAUTH_TOKEN' if runtime['location']=='actions' else 'FACTORY_IMPLEMENTATION_CLAUDE_OAUTH_TOKEN'
        if os.environ.get(credential):environment[credential]=os.environ[credential]
    with tempfile.TemporaryDirectory() as temporary:
        observed=bounded.run(argv,cwd=temporary,env=environment,timeout=runtime['probe']['timeout'])
        require(observed.returncode==0,'runtime probe failed');result=decode(observed.stdout)
    pins(runtime)
    require(set(result)=={'schema_version','available','model','capabilities','version','quota','reset_at','estimated_api_usd','actual_spend_usd'} and type(result['schema_version']) is int and result['schema_version']==1 and type(result['available']) is bool and result['model']==runtime['model'] and strings(result['capabilities']) and isinstance(result['version'],str) and 0<len(result['version'])<=200 and result['quota'] in {'available','exhausted','unknown'} and result['actual_spend_usd'] is None,'runtime observation invalid')
    cost=result['estimated_api_usd'];require(cost is None or (type(cost) in {float,int} and math.isfinite(cost) and 0<=cost<=1000000),'usage estimate invalid')
    if result['reset_at'] is not None:
        require(isinstance(result['reset_at'],str),'quota reset type invalid');value=datetime.fromisoformat(result['reset_at'].replace('Z','+00:00'));require(value.tzinfo is not None and result['quota']=='exhausted','quota reset invalid')
    require(result['quota']!='exhausted' or result['available'] is False,'exhausted runtime cannot be available')
    return result


def choose(profile,role,platform,root,probe_fn=probe):
    require(start_installation(Path(root).resolve()) is None,'registered capacity API requires controlled start action; unavailable')
    validate(profile);require(profile['enabled'] is True,'routing not configured/enabled');require(role in profile['roles'] and platform==LOCATIONS[role],'role unavailable on this authority platform')
    stacks=stack_readiness(profile,root);route=profile['roles'][role];observations=[]
    for index,name in enumerate([route['primary'],*route['fallbacks']]):
        runtime=profile['runtimes'][name];result=probe_fn(runtime)
        observations.append({'runtime':name,'observation':result})
        require(set(route['capabilities'])<=set(result['capabilities']),'runtime lacks role capability; no weaker fallback')
        if result['available'] and result['quota']!='exhausted':
            return {'schema_version':1,'role':role,'runtime':name,'model':runtime['model'],'fallback_index':index,'fallback_reason':None if index==0 else 'primary-unavailable','stacks':stacks,'profile_sha256':hashlib.sha256(canonical(profile).encode()).hexdigest(),'observations':observations,'independent_verdict':False}
    return {'schema_version':1,'role':role,'blocked':'capacity-unavailable','profile_sha256':hashlib.sha256(canonical(profile).encode()).hexdigest(),'observations':observations,'independent_verdict':False}



def start_bytes(path,private_file=False):
    path=Path(path)
    require(path.is_absolute() and path.resolve()==path and not path.is_symlink(),'start control path not canonical')
    if private_file:
        require(path.parent.stat().st_uid==os.getuid() and stat.S_IMODE(path.parent.stat().st_mode)==0o700,'start control parent not private')
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)
    try:
        info=os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink==1 and info.st_size<=8000000,'start control file invalid')
        if private_file:require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'start control file not private')
        with os.fdopen(fd,'rb',closefd=False) as stream:raw=stream.read(8000001)
        require(len(raw)<=8000000,'start control bytes exceeded');return raw
    finally:os.close(fd)


def start_installation(root):
    """Stdlib-only OS registry read; no candidate environment/config selection."""
    home=Path(pwd.getpwuid(os.getuid()).pw_dir)
    require(home.is_absolute() and home.resolve()==home and home.is_dir(),'start OS home not canonical')
    directory=home/'.local/state/factory-required-intake';latch=home/'.factory-intake-required'
    if not directory.exists() and not latch.exists():return None
    require(directory.resolve()==directory and directory.is_dir() and directory.stat().st_uid==os.getuid()
            and stat.S_IMODE(directory.stat().st_mode)==0o700 and latch.exists(),'start registry missing or unsafe')
    latched=decode(start_bytes(latch));info=latch.stat()
    require(info.st_uid==os.getuid() and stat.S_IMODE(info.st_mode)==0o600,'start latch not private')
    records=decode(start_bytes(directory/'registry.json',True))
    require(isinstance(latched,dict) and set(latched)=={'schema_version','bindings'} and type(latched['schema_version']) is int
            and latched['schema_version']==1 and isinstance(latched['bindings'],dict)
            and isinstance(records,dict) and set(records)=={'schema_version','roots'} and type(records['schema_version']) is int
            and records['schema_version']==1 and isinstance(records['roots'],dict)
            and set(records['roots'])==set(latched['bindings']) and 0<len(records['roots'])<=1000,'start registry schema differs')
    fields={'repository','authority_root','candidate_root','contract','database','profile','policy','contract_sha256'}
    matched=[]
    for key,entry in records['roots'].items():
        require(isinstance(entry,dict) and set(entry)==fields and entry['authority_root']==key
                and isinstance(entry['repository'],str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',entry['repository'])
                and isinstance(entry['contract_sha256'],str) and re.fullmatch(r'[a-f0-9]{64}',entry['contract_sha256'])
                and latched['bindings'][key]==entry['contract_sha256'],'start registry entry differs')
        for name in fields-{'repository','contract_sha256'}:
            require(isinstance(entry[name],str) and Path(entry[name]).is_absolute() and Path(entry[name]).resolve()==Path(entry[name]),'start registry path malformed')
        if str(root) in {entry['candidate_root'],entry['authority_root']}:matched.append(entry)
    require(len(matched)<=1,'start registry selection ambiguous')
    return matched[0] if matched else None


def start_boundary(profile,root,database,task,role,request_id=None,action_id=None):
    """Read-only bootstrap before model probes, helper execution or runtime writes."""
    root=Path(root).resolve();database=Path(database);entry=start_installation(root)
    detected=False
    if database.exists():
        require(database.is_absolute() and database.resolve()==database and database.is_file() and not database.is_symlink(),'start database not canonical')
        with sqlite3.connect(database.as_uri()+'?mode=ro',uri=True) as db:
            db.execute('PRAGMA trusted_schema=OFF')
            tables={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            detected='runtime_intake_required' in tables or any(name.startswith('intake_') for name in tables)
    descriptor=profile.get('mandatory_intake') if isinstance(profile,dict) else None
    if entry is None:
        require(not detected and descriptor is None and request_id is None and action_id is None,'required start installation unavailable')
        return None
    require(str(root)==entry['candidate_root'] and str(database)==entry['database'],'start candidate/store installation differs')
    config=decode(start_bytes(entry['contract'],True))
    require(hashlib.sha256(canonical(config).encode()).hexdigest()==entry['contract_sha256'],'start contract pin differs')
    require(isinstance(config,dict) and config.get('repository')==entry['repository']
            and all(config.get(name)==entry[name] for name in ('candidate_root','authority_root','database','profile','policy')),'start installation contract differs')
    expected_profile=decode(start_bytes(entry['profile'],True))
    require(canonical(profile)==canonical(expected_profile),'start supplied profile differs')
    directory=Path(__file__).resolve().parent;ledger_path=directory/'factory-ledger.py'
    files=config.get('trusted_files')
    require(isinstance(files,dict) and str(ledger_path) in files
            and all(ledger_path!=Path(entry[name]) and Path(entry[name]) not in ledger_path.parents for name in ('candidate_root','authority_root')),
            'start bootstrap ledger pin missing or candidate-owned')
    require(hashlib.sha256(start_bytes(ledger_path)).hexdigest()==files[str(ledger_path)],'start ledger bootstrap changed')
    spec=importlib.util.spec_from_file_location('routing_start_ledger',ledger_path)
    ledger=importlib.util.module_from_spec(spec);spec.loader.exec_module(ledger)
    controller=ledger.intake_boundary(entry['authority_root'],database,entry['policy'],task,request_id,entry['profile'])
    require(controller is not None,'required start controller unavailable')
    policy=decode(start_bytes(entry['policy'],True))
    require(policy.get('runtime',{}).get('roles_by_task',{}).get(task)==role,'start role differs from protected task role')
    controller.start_scope(request_id,task,action_id)
    # T241 owns durable start reconciliation; T242/243 assemble the guarded
    # wrapper/claim protocol. Direct native safe-mode suppresses project hooks.
    raise ValueError('mandatory guarded worker start unavailable until wrapper and owned claim protocol are assembled')


def worker_usage(attempt, runtime):
    path=attempt/'worker.log'
    require(path.is_file() and not path.is_symlink() and path.stat().st_size<=1000000,'structured worker output missing/oversized')
    result=decode(path.read_bytes())
    require(isinstance(result,dict) and result.get('type')=='result' and result.get('subtype')=='success' and result.get('is_error') is False,'structured worker outcome failed')
    models=result.get('modelUsage')
    require(isinstance(models,dict) and runtime['model'] in models and set(models)<=set(runtime['allowed_model_usage']),'worker model usage differs from protected routing')
    tokens={}
    for name,usage in models.items():
        require(isinstance(usage,dict),'worker model usage invalid')
        tokens[name]={}
        for field in ('inputTokens','outputTokens','cacheReadInputTokens','cacheCreationInputTokens'):
            value=usage.get(field)
            require(value is None or (type(value) is int and 0<=value<=1000000000),'worker token count invalid')
            tokens[name][field]=value
    estimate=result.get('total_cost_usd')
    require(estimate is None or (type(estimate) in {float,int} and math.isfinite(estimate) and 0<=estimate<=1000000),'worker client estimate invalid')
    return {'usage':'reported','usage_scope':'conversation','models':tokens,'estimated_api_usd':estimate,'estimated_api_usd_scope':'conversation','actual_spend_usd':None}


def run(profile,role,platform,root,database,task,attempts,timeout=1800,resources=None,*,intake_request=None,intake_action=None):
    require(isinstance(task,str) and re.fullmatch(r'T-[1-9][0-9]*',task),'runtime task ID invalid')
    root=Path(root).resolve()
    start_boundary(profile,root,database,task,role,intake_request,intake_action)
    require(platform=='local' and role in {'planning','implementation'},'only local planning/implementation can launch workers here')
    database=Path(database);attempts=Path(attempts)
    require(database.is_absolute() and database.resolve()==database and database.parent!=root.resolve() and root.resolve() not in database.parents and database.parent.stat().st_uid==os.getuid() and stat.S_IMODE(database.parent.stat().st_mode)==0o700,'runtime state must be private outside candidate')
    if database.exists():require(database.is_file() and database.stat().st_uid==os.getuid() and stat.S_IMODE(database.stat().st_mode)==0o600,'private runtime database owner/mode invalid')
    require(attempts.is_absolute() and attempts.resolve()==attempts and attempts.parent==database.parent,'attempt storage must be in private runtime root')
    if attempts.exists():require(attempts.is_dir() and stat.S_IMODE(attempts.stat().st_mode)==0o700,'attempt storage mode invalid')
    else:attempts.mkdir(mode=0o700)
    validate(profile)
    old_umask=os.umask(0o077)
    try:store=supervisor.runtime.Store(database)
    finally:os.umask(old_umask)
    require(stat.S_IMODE(database.stat().st_mode)==0o600,'runtime state creation mode invalid')
    identity=uuid.uuid4().hex
    with store.transaction() as db:
        db.execute('CREATE TABLE IF NOT EXISTS runtime_route_repository(id INTEGER PRIMARY KEY,repository TEXT NOT NULL)')
        old=db.execute('SELECT repository FROM runtime_route_repository WHERE id=1').fetchone();require(old is None or old[0]==profile['repository'],'foreign runtime routing store')
        if old is None:db.execute('INSERT INTO runtime_route_repository VALUES(1,?)',(profile['repository'],))
    decision=choose(profile,role,platform,root)
    with store.transaction() as db:
        db.execute('CREATE TABLE IF NOT EXISTS runtime_route_events(id TEXT PRIMARY KEY,task TEXT NOT NULL,decision TEXT NOT NULL,outcome TEXT)')
        db.execute('INSERT INTO runtime_route_events VALUES(?,?,?,NULL)',(identity,task,canonical(decision)))
    if 'blocked' in decision:
        outcome={'blocked':decision['blocked'],'worker_started':False}
        with store.transaction() as db:db.execute('UPDATE runtime_route_events SET outcome=? WHERE id=?',(canonical(outcome),identity))
        return {'route_id':identity,**outcome}
    runtime=profile['runtimes'][decision['runtime']];pins(runtime)
    before={path.name for path in attempts.iterdir()};expected_fence=store.get(task)['fence']+1
    code=supervisor.supervise(database,task,render(runtime['command'],runtime['model'],task),root,attempts,timeout=timeout,resources=resources)
    outcome={'exit_code':code,'engineering_verified':False,'actual_spend_usd':None,'estimated_api_usd':None,'usage':'unknown'}
    if code==0 and runtime['kind']=='claude-cli':
        try:
            created=[path for path in attempts.glob(task+'-*') if path.name not in before]
            require(len(created)==1,'worker attempt identity ambiguous')
            observed=decode((created[0]/'outcome.json').read_bytes())
            require(observed['task']==task and observed['fence']==expected_fence and observed['exit_code']==0,'worker attempt binding differs')
            outcome.update(worker_usage(created[0],runtime))
        except (ValueError,KeyError,TypeError,OSError):
            row=store.get(task)
            if row['state']=='verifying' and row['fence']==expected_fence:
                try:store.transition(task,row['owner'],row['fence'],'blocked')
                except supervisor.runtime.Blocked:pass  # A lost lease cannot regain task authority.
            outcome.update(exit_code=2,reason='structured-runtime-outcome-invalid')
    with store.transaction() as db:db.execute('UPDATE runtime_route_events SET outcome=? WHERE id=?',(canonical(outcome),identity))
    return {'route_id':identity,'worker_started':True,**outcome}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--config',required=True);parser.add_argument('--root',required=True);parser.add_argument('--role',required=True);parser.add_argument('--platform',choices=['local','actions'],default='local');args=parser.parse_args()
    root=Path(args.root).resolve()
    require(start_installation(root) is None,'registered routing CLI requires controlled start action; capacity-only invocation unsupported')
    profile=protected(Path(args.config),[root]);print(canonical(choose(profile,args.role,args.platform,root)))


if __name__=='__main__':
    try:main()
    except (ValueError,KeyError,TypeError,OSError,subprocess.SubprocessError,sqlite3.Error):
        import sys
        print('Factory runtime blocked; inspect protected role/stack configuration and capacity.',file=sys.stderr);sys.exit(2)
