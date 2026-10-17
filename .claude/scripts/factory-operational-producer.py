#!/usr/bin/env python3
"""Protected historical queue observations and completed-run retention only.

The empty fixed registry is inactive until separately reviewed registration.
Profiles pin historical inputs and stable producer bytes, not a self-referential
producer commit. No current readiness/delivery/task/merge authority is granted.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import re
import stat
import subprocess
import zipfile
from urllib.parse import quote


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


proof = module('operational_contract', 'factory-operational-proof.py')
evidence = module('operational_queue_observation', 'factory-reporting-queue-evidence.py')
queue = module('operational_queue', 'factory-reporting-queue.py')
transport = module('operational_transport', 'factory-reporting-transport.py')
state = transport.state
require = proof.require
SIGNER = '.github/workflows/factory-operational-proof.yml'
RETAINER = '.github/workflows/factory-operational-proof-retain.yml'
REGISTRY = 'factory/operational-proof-profiles.json'


def load_registry(root):
    path = Path(root) / REGISTRY
    require(path.parent.resolve() == path.parent and not path.is_symlink(), 'protected registry path invalid')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, 'rb') as stream:
        require(stat.S_ISREG(os.fstat(stream.fileno()).st_mode), 'protected registry not regular')
        raw = stream.read(262145)
    document = proof.decode(raw, 262144)
    proof.fields(document, 'schema_version profiles')
    require(type(document['schema_version']) is int and document['schema_version'] == 1 and type(document['profiles']) is list and len(document['profiles']) <= 16, 'registry shape invalid')
    ids = set()
    for item in document['profiles']:
        validate_entry(item)
        require(item['profile_id'] not in ids, 'duplicate profile'); ids.add(item['profile_id'])
    return document


def validate_entry(entry):
    proof.fields(entry, 'profile_id status repository branch original producer retainer selections queue_config original_state retention')
    proof.text(entry['profile_id'], r'[A-Za-z0-9][A-Za-z0-9_.-]{0,99}')
    require(entry['status'] in ('active', 'inactive', 'withdrawn'), 'profile status invalid')
    proof.repository(entry['repository']); proof.branch(entry['branch'])
    proof.fields(entry['original'], 'source_sha workflow_path workflow_id runtime'); proof.source(entry['original'])
    require(entry['original']['workflow_path'] == evidence.WORKFLOW, 'historical workflow differs')
    proof.fields(entry['producer'], 'workflow_path workflow_id runtime')
    proof.source(dict(entry['producer'], source_sha='0'*40))
    require(entry['producer']['workflow_path'] == SIGNER, 'producer workflow differs')
    proof.fields(entry['retainer'], 'workflow_path workflow_id runtime')
    proof.source(dict(entry['retainer'],source_sha='0'*40))
    require(entry['retainer']['workflow_path'] == RETAINER, 'retainer workflow differs')
    proof.fields(entry['selections'], 'drill recovery repeat')
    ids = set()
    for selector in entry['selections'].values():
        proof.fields(selector, 'run_id attempt')
        proof.integer(selector['run_id']); proof.integer(selector['attempt'])
        require(selector['run_id'] not in ids, 'repeated historical selector'); ids.add(selector['run_id'])
    queue.validate_config(entry['queue_config'], repository=entry['repository']['name'], default_branch=entry['branch'])
    proof.fields(entry['original_state'], 'branch bootstrap_sha frozen_sha')
    proof.fields(entry['retention'], 'branch bootstrap_sha')
    for item in (entry['original_state'], entry['retention']):
        proof.branch(item['branch']); proof.hexstr(item['bootstrap_sha'], 40)
        require(item['branch'] != entry['branch'], 'state must not be source branch')
    proof.hexstr(entry['original_state']['frozen_sha'], 40)
    return entry


def active(entry):
    validate_entry(entry); require(entry['status'] == 'active', 'operational profile inactive')


def role(repository, profile_id, original_source):
    return hashlib.sha256(proof.canonical(['factory-historical-queue-completion-v1', repository, profile_id, original_source])).hexdigest()


def read_blob(api, sha, maximum=262144):
    proof.hexstr(sha, 40)
    value = api.request('repos/'+api.repo+'/git/blobs/'+sha)
    require(type(value) is dict and value.get('sha') == sha and value.get('encoding') == 'base64' and type(value.get('size')) is int and 0 < value['size'] <= maximum and type(value.get('content')) is str and len(value['content']) <= maximum*2, 'historical blob invalid')
    try:raw = base64.b64decode(''.join(value['content'].split()), validate=True)
    except ValueError as exc:raise ValueError('historical blob encoding invalid') from exc
    require(len(raw) == value['size'] and state.git_hash(raw) == sha, 'historical blob identity differs')
    return raw


def git_bytes(root, *arguments, limit=2097152):
    safe = {key:os.environ[key] for key in ('PATH','HOME','LANG','LC_ALL') if key in os.environ}
    result = transport.process.run(['git','-C',str(root),*arguments],env=safe,cwd=root,timeout=10,limit=limit)
    require(result.returncode == 0, 'protected Git object unavailable')
    return result.stdout


def runtime_inventory(api, source, root=None):
    """Closed exact-source family: every top-level Python file, plus workflow."""
    result = set()
    if root is not None:
        raw = git_bytes(root,'ls-tree','-z',source+':.claude/scripts',limit=262144)
        for line in raw.decode('utf-8').split('\0'):
            if not line:continue
            metadata, name = line.split('\t',1)
            if name.endswith('.py'):
                require(metadata.split()[:2] in (['100644','blob'],['100755','blob']), 'runtime member not regular')
                proof.text(name,r'[A-Za-z0-9_.-]+\.py');result.add('.claude/scripts/'+name)
    else:
        values = api.request('repos/'+api.repo+'/contents/.claude/scripts?ref='+source)
        require(type(values) is list and len(values) <= 1024, 'runtime directory incomplete')
        for value in values:
            require(type(value) is dict and type(value.get('name')) is str, 'runtime directory invalid')
            if value['name'].endswith('.py'):
                proof.text(value['name'],r'[A-Za-z0-9_.-]+\.py')
                require(value.get('type') == 'file' and value.get('path') == '.claude/scripts/'+value['name'], 'runtime member not regular')
                require(value['path'] not in result, 'duplicate runtime member');result.add(value['path'])
    require(0 < len(result) < 128, 'runtime inventory bound exceeded')
    return result


def runtime_bytes(api, source, runtime, root=None):
    workflows = {path for path in runtime if path.startswith('.github/workflows/')}
    require(len(workflows) == 1 and set(runtime) == runtime_inventory(api,source,root) | workflows, 'closed runtime inventory differs')
    for path, expected in runtime.items():
        if root is not None:
            # Actual source SHA was independently bound to native API/protected profile.
            env = {key:os.environ[key] for key in ('PATH','HOME','LANG','LC_ALL') if key in os.environ}
            result = transport.process.run(['git','-C',str(root),'ls-tree',source,'--',path], env=env, cwd=root, timeout=10, limit=4096)
            require(result.returncode == 0, 'runtime tree unavailable')
            line = result.stdout.decode().strip().split('\t')
            require(len(line) == 2 and line[1] == path and line[0].split()[:2] in (['100644','blob'],['100755','blob']), 'runtime file not regular')
            result = transport.process.run(['git','-C',str(root),'show',source+':'+path], env=env, cwd=root, timeout=10, limit=2097152)
            require(result.returncode == 0, 'runtime bytes unavailable'); raw = result.stdout
        else:
            # Offline seam / bounded native Contents API; never a caller hash assertion.
            value = api.request('repos/'+api.repo+'/contents/'+path+'?ref='+source)
            require(type(value) is dict and value.get('type') == 'file' and value.get('path') == path and value.get('encoding') == 'base64' and type(value.get('size')) is int and 0 < value['size'] <= 1048576 and type(value.get('content')) is str and len(value['content']) <= 2097152, 'runtime content invalid')
            try:raw = base64.b64decode(''.join(value['content'].split()), validate=True)
            except ValueError as exc:raise ValueError('runtime content encoding invalid') from exc
            require(len(raw) == value['size'] and state.git_hash(raw) == value.get('sha'), 'runtime Git identity differs')
        require(hashlib.sha256(raw).hexdigest() == expected, 'reviewed runtime differs')


def native_repository(api, entry):
    value = api.request('repos/'+api.repo)
    require(type(value) is dict and type(value.get('id')) is int and value['id'] == entry['repository']['id'] and value.get('full_name') == api.repo == entry['repository']['name'] and type(value.get('private')) is bool and value['private'] == entry['repository']['private'] and value.get('default_branch') == entry['branch'] and value.get('archived') is False, 'native repository differs')


def run_binding(run, entry, source, workflow, *, completed, events=('workflow_dispatch',)):
    require(type(run) is dict, 'native run missing')
    for key in ('id','run_attempt','workflow_id'):proof.integer(run.get(key))
    require(run['workflow_id'] == workflow['workflow_id'] and run.get('path') == workflow['workflow_path'] and run.get('head_sha') == source and run.get('head_branch') == entry['branch'] and run.get('event') in events, 'native source execution differs')
    for key in ('repository','head_repository'):
        value = run.get(key)
        require(type(value) is dict and type(value.get('id')) is int and value['id'] == entry['repository']['id'] and value.get('full_name') == entry['repository']['name'], 'native run repository differs')
    if completed:require(run.get('status') == 'completed' and run.get('conclusion') == 'success', 'native producer not completed successfully')


def resolve_profile(api, entry, run, *, root=None):
    active(entry); native_repository(api, entry)
    source = run.get('head_sha'); proof.hexstr(source, 40)
    run_binding(run, entry, source, entry['producer'], completed=False)
    runtime_bytes(api, source, entry['producer']['runtime'], root)
    runtime_bytes(api, entry['original']['source_sha'], entry['original']['runtime'], root)
    return {'schema_version':1, 'profile_id':entry['profile_id'], 'profile_sha256':hashlib.sha256(proof.canonical(entry)).hexdigest(), 'status':'active', 'repository':entry['repository'], 'branch':entry['branch'], 'original':entry['original'], 'producer':dict(entry['producer'],source_sha=source)}


def observe_runs(api, entry, now):
    active(entry); native_repository(api,entry)
    observed = []; previous = None
    for role_name, counts in (('drill',[1,0]),('recovery',[1]),('repeat',[0])):
        selector = entry['selections'][role_name]
        run = api.request(f'repos/{api.repo}/actions/runs/{selector["run_id"]}/attempts/{selector["attempt"]}')
        # Recovery/repeat may have been a scheduled run, preserving original contract.
        require(type(run) is dict and run.get('event') in (('workflow_dispatch',) if role_name == 'drill' else ('workflow_dispatch','schedule')), 'historical event differs')
        run_binding(run,entry,entry['original']['source_sha'],entry['original'],completed=True,events=('workflow_dispatch',) if role_name == 'drill' else ('workflow_dispatch','schedule'))
        require(run['id'] == selector['run_id'] and run['run_attempt'] == selector['attempt'], 'historical selector differs')
        created, started, ended = (evidence.instant(run.get(key)) for key in ('created_at','run_started_at','updated_at'))
        require(created <= started <= ended <= now and (previous is None or previous <= started), 'historical run clock differs'); previous = ended
        jobs = api.request(f'repos/{api.repo}/actions/runs/{run["id"]}/attempts/{run["run_attempt"]}/jobs?per_page=100&page=1')
        require(type(jobs) is dict and type(jobs.get('total_count')) is int and jobs['total_count'] == 1 and type(jobs.get('jobs')) is list and len(jobs['jobs']) == 1, 'historical jobs incomplete')
        job = jobs['jobs'][0]
        require(type(job) is dict and all(type(job.get(k)) is int for k in ('id','run_id','run_attempt')) and evidence.integer(job['id']) and job['run_id'] == run['id'] and job['run_attempt'] == run['run_attempt'] and job.get('head_sha') == entry['original']['source_sha'] and job.get('name') == 'monitor' and job.get('status') == 'completed' and job.get('conclusion') == 'success', 'historical job differs')
        steps = job.get('steps')
        require(type(steps) is list and 0 < len(steps) <= 32 and all(type(step) is dict and evidence.integer(step.get('number')) for step in steps) and len({step['number'] for step in steps}) == len(steps), 'historical steps invalid')
        selected = [step for step in steps if step.get('name') == evidence.STEP]
        require(len(selected) == 1 and selected[0].get('status') == 'completed' and selected[0].get('conclusion') == 'success', 'historical monitor step differs')
        raw = api.request(f'repos/{api.repo}/actions/jobs/{job["id"]}/logs', raw=True)
        require([item['notifications'] for item in evidence.results(raw)] == counts, 'historical log observations differ')
        observed.append({'role':role_name,'run_id':run['id'],'attempt':run['run_attempt'],'job_id':job['id'],'started_at':run['run_started_at'],'ended_at':run['updated_at'],'log_sha256':hashlib.sha256(raw).hexdigest(),'notifications':counts})
    return observed


def observe_state(api, entry, runs, *, state_view=None):
    """Re-read exact immutable historical lineage; other worker data stay opaque."""
    selected = entry['original_state']; root = 'repos/'+api.repo; commits = {}; trees = {}; documents = {}
    path = 'reports/'+queue.stream(entry['queue_config'])+'.json'
    # Prove membership in a protected branch, not just an arbitrary backdated Git DAG.
    protected = state.GitState(api,selected['branch'],queue.stream(entry['queue_config']),selected['bootstrap_sha'],bootstrap_existing=True,state_view=state_view)
    def ancestor(head):
        proof.hexstr(head,40)
        identity = selected['frozen_sha']
        comparison = api.request(root+'/compare/'+identity+'...'+head+'?per_page=1&page=2')
        require(type(comparison) is dict and comparison.get('base_commit',{}).get('sha') == identity and comparison.get('merge_base_commit',{}).get('sha') == identity and comparison.get('status') == ('identical' if identity == head else 'ahead') and type(comparison.get('behind_by')) is int and comparison['behind_by'] == 0 and all(type(comparison.get(key)) is int and comparison[key] >= 0 for key in ('ahead_by','total_commits')), 'historical frozen state not protected ancestor')
    ancestor(protected.head)

    def commit(sha):
        proof.hexstr(sha,40)
        if sha not in commits:
            value = api.request(root+'/git/commits/'+sha)
            require(type(value) is dict and value.get('sha') == sha and type(value.get('tree')) is dict and type(value.get('parents')) is list, 'historical commit invalid')
            proof.hexstr(value['tree'].get('sha'),40); commits[sha] = value
        return commits[sha]
    def entries(identity):
        value = api.request(root+'/git/trees/'+identity)
        require(type(value) is dict and value.get('sha') == identity and value.get('truncated') is False and type(value.get('tree')) is list and len(value['tree']) <= 1024, 'historical tree incomplete')
        seen = set()
        for item in value['tree']:
            require(type(item) is dict and type(item.get('path')) is str and item['path'] not in seen, 'historical duplicate path'); seen.add(item['path']); proof.hexstr(item.get('sha'),40)
        return value['tree']
    def tree(sha):
        identity = commit(sha)['tree']['sha']
        if identity not in trees:
            result = {}
            for item in entries(identity):
                name = item['path']
                if name in ('reports','receipt-archive'):
                    require(item.get('mode') == '040000' and item.get('type') == 'tree', 'historical directory invalid')
                    if name == 'receipt-archive':result[name] = ('040000',item['sha'])
                    else:
                        for leaf in entries(item['sha']):
                            require(leaf.get('mode') == '100644' and leaf.get('type') == 'blob' and re.fullmatch('[0-9a-f]{64}\\.json',leaf['path']), 'historical report path invalid')
                            result['reports/'+leaf['path']] = ('100644',leaf['sha'])
                else:
                    require(name == 'README.md' and item.get('mode') == '100644' and item.get('type') == 'blob', 'historical root path invalid');result[name] = ('100644',item['sha'])
            trees[identity] = result
        return trees[identity]
    def document(sha):
        item = tree(sha).get(path)
        if item is None:return None
        if item[1] not in documents:documents[item[1]] = queue.load_journal(read_blob(api,item[1]),entry['queue_config'])
        return documents[item[1]]
    final = document(selected['frozen_sha'])
    require(final is not None and len(final['events']) == 2, 'historical isolated role missing')
    drill,recovery = final['events']
    require(drill['kind'] == 'drill' and recovery['kind'] == 'recovery' and drill['status'] == recovery['status'] == 'confirmed' and drill['run_id'] == entry['selections']['drill']['run_id'] and drill['run_attempt'] == entry['selections']['drill']['attempt'] and recovery['incident'] == drill['key'], 'historical effects differ')
    cursor = selected['frozen_sha']; lineage = []; publications = []; prior = None
    for unused in range(24):
        if cursor == selected['bootstrap_sha']:break
        current = commit(cursor); parents = current['parents']
        require(len(parents) == 1 and type(parents[0]) is dict, 'historical ancestry ambiguous')
        parent = parents[0].get('sha'); oldtree = tree(parent); newtree = tree(cursor)
        lineage.append({'head':cursor,'parent':parent,'tree':current['tree']['sha']})
        if oldtree.get(path) != newtree.get(path):
            require({k:v for k,v in oldtree.items() if k != path} == {k:v for k,v in newtree.items() if k != path}, 'historical opaque sibling changed')
            old = document(parent); new = document(cursor)
            require(new is not None and (old is not None or parent == selected['bootstrap_sha']), 'historical role reset')
            queue.validate_transition(old,new,entry['queue_config'])
            when = evidence.instant(current.get('committer',{}).get('date'))
            require(prior is None or when <= prior, 'historical publication ordering differs'); prior = when
            before = [] if old is None else old['events']; after = new['events']
            changes = [row for i,row in enumerate(after) if i >= len(before) or row != before[i]]
            if old is not None or after:
                require(len(changes) == 1, 'historical publication lacks one effect')
                effect = changes[0]; expected = drill if effect['kind'] == 'drill' else recovery
                require(effect['kind'] in ('drill','recovery') and effect['key'] == expected['key'], 'historical unexpected effect')
                window = runs[0 if effect['kind'] == 'drill' else 1]
                require(evidence.instant(window['started_at']) <= evidence.instant(effect['cutoff']) <= when <= evidence.instant(window['ended_at']), 'historical effect outside run window')
                publications.append((effect['key'],effect['status']))
            else:publications.append((None,None))
        cursor = parent
    require(cursor == selected['bootstrap_sha'] and document(cursor) is None, 'historical bootstrap/24-commit bound differs')
    require((drill['key'],'confirmed') in publications and (recovery['key'],'confirmed') in publications, 'historical confirmations missing')
    ref = api.request(root+'/git/ref/heads/'+quote(selected['branch'],safe=''))
    require(type(ref) is dict and ref.get('ref') == 'refs/heads/'+selected['branch'] and ref.get('object',{}).get('type') == 'commit', 'historical state reference differs')
    ancestor(ref['object'].get('sha'))
    raw = read_blob(api,tree(selected['frozen_sha'])[path][1])
    return {'branch':selected['branch'],'head_sha':selected['frozen_sha'],'tree_sha':commit(selected['frozen_sha'])['tree']['sha'],'journal_path':path,'journal_sha256':hashlib.sha256(raw).hexdigest(),'lineage_sha256':hashlib.sha256(proof.canonical(lineage)).hexdigest(),'drill_key':drill['key'],'recovery_key':recovery['key'],'publication_count':len(publications)}


def produce(api, entry, run, *, now=None, root=None):
    now = datetime.now(timezone.utc) if now is None else now
    expected = resolve_profile(api,entry,run,root=root)
    runs = observe_runs(api,entry,now)
    view = None if root is None else {'mode':'archive','approval_path':str(Path(root)/'factory/receipt-archive-bootstrap.json')}
    historical = observe_state(api,entry,runs,state_view=view)
    value = {'schema_version':1,'type':'historical-queue-completion','purpose':'historical-operational-acceptance','profile_id':entry['profile_id'],'profile_sha256':expected['profile_sha256'],'repository':entry['repository'],'original':dict(entry['original'],runs=runs,state=historical),'verification':dict(expected['producer'],run_id=run['id'],attempt=run['run_attempt'],started_at=run['run_started_at'],verified_at=now.isoformat())}
    proof.validate_record(proof.canonical(value),expected,now=now)
    return value


def unpack(raw):
    require(type(raw) is bytes and 0 < len(raw) <= 2097152, 'operational artifact ZIP bound exceeded')
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            items = archive.infolist()
            require(len(items) == 2 and {item.filename for item in items} == {'evidence.json','provenance.sigstore.json'}, 'operational artifact paths differ')
            result = {}
            for item in items:
                maximum = 262144 if item.filename == 'evidence.json' else 1000000
                require(0 < item.file_size <= maximum and stat.S_IFMT(item.external_attr >> 16) in (0,stat.S_IFREG) and not item.flag_bits & 1, 'operational artifact member invalid')
                with archive.open(item) as stream:data = stream.read(maximum+1)
                require(len(data) == item.file_size <= maximum, 'operational ZIP expansion bound exceeded'); result[item.filename] = data
            return result['evidence.json'],result['provenance.sigstore.json']
    except (zipfile.BadZipFile,RuntimeError,OSError) as exc:raise ValueError('operational artifact invalid') from exc


def retain(api, entry, raw, bundle, completion_raw, completion_bundle, *, guard, state_view=None, _accept_existing=None):
    """Internal post-authentication CAS primitive, not a public trust callback CLI."""
    active(entry)
    value = proof.decode(raw,262144,True)
    require(value.get('profile_sha256') == hashlib.sha256(proof.canonical(entry)).hexdigest() and value.get('profile_id') == entry['profile_id'] and value.get('repository') == entry['repository'] and all(value.get('original',{}).get(k) == v for k,v in entry['original'].items()), 'retained record profile differs')
    require(type(bundle) is bytes and 0 < len(bundle) <= 1000000, 'retained bundle invalid')
    require(type(completion_bundle) is bytes and 0 < len(completion_bundle) <= 1000000, 'completion bundle invalid')
    completed = proof.decode(completion_raw,262144,True)
    require(completed.get('profile_sha256') == value['profile_sha256'] and completed.get('upstream',{}).get('record_sha256') == hashlib.sha256(raw).hexdigest() and completed['upstream'].get('bundle_sha256') == hashlib.sha256(bundle).hexdigest(), 'completion retention binding differs')
    data = proof.canonical({'schema_version':1,'type':'retained-historical-queue-completion','record':value,'bundle':base64.b64encode(bundle).decode(),'completion':completed,'completion_bundle':base64.b64encode(completion_bundle).decode()})
    require(len(data) <= 1048576, 'retained envelope exceeds bounded blob response')
    identity = role(api.repo,entry['profile_id'],entry['original']['source_sha'])
    for unused in range(3):
        require(guard() is True, 'protected profile changed before retention')
        current = state.GitState(api,entry['retention']['branch'],identity,entry['retention']['bootstrap_sha'],bootstrap_existing=True,state_view=state_view)
        if current.bytes is not None:
            require(current.bytes == data or (_accept_existing is not None and _accept_existing(current.bytes) is True), 'retained historical role immutable')
            return {'status':'already-applied','path':current.path,'head':current.head}
        require(guard() is True, 'protected profile changed before write')
        try:current.checkpoint(data)
        except (ValueError,RuntimeError):continue  # Fresh protected reload reconciles conflict/lost acknowledgement.
        return {'status':'applied','path':current.path,'head':current.head}
    # Reconcile the final uncertain write before declaring failure; never send a fourth.
    require(guard() is True, 'protected profile changed during uncertain retention')
    current = state.GitState(api,entry['retention']['branch'],identity,entry['retention']['bootstrap_sha'],bootstrap_existing=True,state_view=state_view)
    require(current.bytes == data or (current.bytes is not None and _accept_existing is not None and _accept_existing(current.bytes) is True), 'three bounded CAS attempts unresolved')
    return {'status':'already-applied','path':current.path,'head':current.head}


def protected_execution(api, root, env, workflow, event):
    require(env.get('GITHUB_ACTIONS') == 'true' and env.get('GITHUB_EVENT_NAME') == event and env.get('GITHUB_REPOSITORY') == api.repo, 'protected execution event differs')
    require(env.get('RUNNER_ENVIRONMENT') == 'github-hosted' and env.get('GITHUB_SERVER_URL') == 'https://github.com' and env.get('GITHUB_API_URL') == 'https://api.github.com', 'protected runner/host differs')
    sha = env.get('GITHUB_SHA'); proof.hexstr(sha,40)
    repository = api.request('repos/'+api.repo)
    branch = repository.get('default_branch'); proof.branch(branch)
    require(env.get('GITHUB_REF') == 'refs/heads/'+branch and env.get('GITHUB_WORKFLOW_SHA') == sha and env.get('GITHUB_WORKFLOW_REF') == api.repo+'/'+workflow+'@refs/heads/'+branch, 'protected workflow/source differs')
    ref = api.request('repos/'+api.repo+'/git/ref/heads/'+quote(branch,safe=''))
    require(ref.get('ref') == 'refs/heads/'+branch and ref.get('object',{}).get('type') == 'commit' and ref['object'].get('sha') == sha, 'protected main changed')
    safe = {key:os.environ[key] for key in ('PATH','HOME','LANG','LC_ALL') if key in os.environ}
    observed = transport.process.run(['git','-C',str(root),'rev-parse','HEAD'],env=safe,cwd=root,timeout=10,limit=4096)
    require(observed.returncode == 0 and observed.stdout.decode().strip() == sha, 'protected checkout differs')
    expected = runtime_inventory(api,sha,root) | {workflow,REGISTRY}
    scripts = Path(root)/'.claude/scripts'
    require(scripts.resolve() == scripts and scripts.is_dir(), 'protected scripts directory invalid')
    require({'.claude/scripts/'+path.name for path in scripts.iterdir() if path.name.endswith('.py')} == {path for path in expected if path.endswith('.py')}, 'untracked runtime shadow differs')
    for name in expected:
        path = Path(root)/name
        require(path.is_file() and not path.is_symlink() and path.resolve() == path, 'executing protected file not regular')
        require(path.stat().st_size <= 2097152 and path.read_bytes() == git_bytes(root,'show',sha+':'+name), 'executing protected bytes differ')
    return sha


def select_registry(root, identity):
    entries = [entry for entry in load_registry(root)['profiles'] if entry['profile_id'] == identity]
    require(len(entries) == 1, 'protected profile unavailable'); active(entries[0]); return entries[0]


def completed_artifact(api, run, identity):
    root = 'repos/'+api.repo
    jobs = api.request(f'{root}/actions/runs/{run["id"]}/attempts/{run["run_attempt"]}/jobs?per_page=100&page=1')
    require(type(jobs) is dict and type(jobs.get('total_count')) is int and jobs['total_count'] == 1 and type(jobs.get('jobs')) is list and len(jobs['jobs']) == 1, 'signer jobs ambiguous')
    job = jobs['jobs'][0]
    require(type(job) is dict and type(job.get('id')) is int and job['id'] > 0 and type(job.get('run_id')) is int and job['run_id'] == run['id'] and type(job.get('run_attempt')) is int and job['run_attempt'] == run['run_attempt'] and job.get('head_sha') == run['head_sha'] and job.get('name') == 'sign' and job.get('status') == 'completed' and job.get('conclusion') == 'success', 'signer job differs')
    response = api.request(f'{root}/actions/runs/{run["id"]}/artifacts?per_page=100&page=1')
    require(type(response) is dict and type(response.get('total_count')) is int and type(response.get('artifacts')) is list and 0 < response['total_count'] == len(response['artifacts']) <= 100, 'signer artifacts incomplete')
    selected = [item for item in response['artifacts'] if type(item) is dict and item.get('name') == f'factory-operational-proof-{identity}-{run["id"]}-{run["run_attempt"]}']
    require(len(selected) == 1, 'selected signer artifact missing or ambiguous')
    item = selected[0]
    require(type(item) is dict and type(item.get('id')) is int and item['id'] > 0 and item.get('name') == f'factory-operational-proof-{identity}-{run["id"]}-{run["run_attempt"]}' and item.get('expired') is False and type(item.get('size_in_bytes')) is int and 0 < item['size_in_bytes'] <= 2097152, 'signer artifact differs')
    binding = item.get('workflow_run')
    require(type(binding) is dict and type(binding.get('id')) is int and binding['id'] == run['id'] and binding.get('head_sha') == run['head_sha'], 'artifact run binding differs')
    zipped = api.request(f'{root}/actions/artifacts/{item["id"]}/zip',raw=True)
    raw,bundle = unpack(zipped)
    return raw,bundle,{'job_id':job['id'],'artifact_id':item['id'],'artifact_sha256':hashlib.sha256(zipped).hexdigest()}


def completion_profile(api, entry, upstream_run, observer_run, *, root=None):
    expected = resolve_profile(api,entry,upstream_run,root=root)
    run_binding(observer_run,entry,observer_run.get('head_sha'),entry['retainer'],completed=False,events=('workflow_run',))
    require(observer_run.get('status') == 'in_progress', 'observer must be actual running execution')
    runtime_bytes(api,observer_run['head_sha'],entry['retainer']['runtime'],root)
    return {'schema_version':1,'profile_id':entry['profile_id'],'profile_sha256':expected['profile_sha256'],'status':'active','repository':entry['repository'],'branch':entry['branch'],'upstream':expected['producer'],'observer':dict(entry['retainer'],source_sha=observer_run['head_sha'])}


def prepare_completion(api, entry, upstream_run, observer_run, *, root=None, runner=None, now=None):
    now = datetime.now(timezone.utc) if now is None else now
    run_binding(upstream_run,entry,upstream_run.get('head_sha'),entry['producer'],completed=True)
    expected = resolve_profile(api,entry,upstream_run,root=root)
    completed_profile = completion_profile(api,entry,upstream_run,observer_run,root=root)
    raw,bundle,metadata = completed_artifact(api,upstream_run,entry['profile_id'])
    proof.verify(raw,bundle,expected,upstream_run,runner=runner,now=now)
    upstream = dict(metadata,record_sha256=hashlib.sha256(raw).hexdigest(),bundle_sha256=hashlib.sha256(bundle).hexdigest(),
                    source_sha=upstream_run['head_sha'],workflow_path=upstream_run['path'],workflow_id=upstream_run['workflow_id'],
                    run_id=upstream_run['id'],attempt=upstream_run['run_attempt'],started_at=upstream_run['run_started_at'],
                    completed_at=upstream_run['updated_at'],status='completed',conclusion='success')
    observer = dict(completed_profile['observer'],run_id=observer_run['id'],attempt=observer_run['run_attempt'],started_at=observer_run['run_started_at'],verified_at=now.isoformat())
    value = {'schema_version':1,'type':'historical-queue-completion-observation','purpose':'historical-operational-acceptance','profile_id':entry['profile_id'],'profile_sha256':completed_profile['profile_sha256'],'repository':entry['repository'],'upstream':upstream,'verification':observer}
    completion_raw = proof.canonical(value); proof.validate_completion(completion_raw,completed_profile,now=now)
    return raw,bundle,completion_raw


def retained_materials(raw):
    envelope = proof.decode(raw,1048576,True)
    proof.fields(envelope,'schema_version type record bundle completion completion_bundle')
    require(type(envelope['schema_version']) is int and envelope['schema_version'] == 1 and envelope['type'] == 'retained-historical-queue-completion', 'retained envelope type differs')
    result = []
    for key in ('record','bundle','completion','completion_bundle'):
        if key in ('record','completion'):
            encoded = proof.canonical(envelope[key]); require(len(encoded) <= 262144, 'retained subject bound exceeded')
        else:
            require(type(envelope[key]) is str and len(envelope[key]) <= 1333336, 'retained signature encoding invalid')
            try:encoded = base64.b64decode(envelope[key],validate=True)
            except ValueError as exc:raise ValueError('retained signature invalid') from exc
            require(0 < len(encoded) <= 1000000, 'retained signature bound exceeded')
        result.append(encoded)
    return tuple(result)


def retained_profiles(api, entry, materials, *, root=None):
    """Source claims are lookup hints; approved bytes AND native certificates authorize.

    Durable replay cannot require forever-available Actions run metadata. This
    constructs strict expected profiles, but confers no authenticity by itself.
    The caller MUST verify_durable before crediting any retained observation.
    """
    active(entry); native_repository(api,entry)
    record = proof.decode(materials[0],262144,True); completed = proof.decode(materials[2],262144,True)
    require(type(record) is dict and type(record.get('verification')) is dict and type(completed) is dict and type(completed.get('verification')) is dict, 'retained source hints invalid')
    upstream = record['verification'].get('source_sha'); observer = completed['verification'].get('source_sha')
    proof.hexstr(upstream,40); proof.hexstr(observer,40)
    runtime_bytes(api,entry['original']['source_sha'],entry['original']['runtime'],root)
    runtime_bytes(api,upstream,entry['producer']['runtime'],root)
    runtime_bytes(api,observer,entry['retainer']['runtime'],root)
    common = {'schema_version':1,'profile_id':entry['profile_id'],'profile_sha256':hashlib.sha256(proof.canonical(entry)).hexdigest(),'status':'active','repository':entry['repository'],'branch':entry['branch']}
    first = dict(common,original=entry['original'],producer=dict(entry['producer'],source_sha=upstream))
    second = dict(common,upstream=first['producer'],observer=dict(entry['retainer'],source_sha=observer))
    return first,second


def retain_completed(source_api, writer_api, entry, upstream_run, observer_run, materials, *, guard, root=None, state_view=None, runner=None, now=None):
    """Authenticate both signatures before CAS; no forever-native-API replay need."""
    require(type(materials) is tuple and len(materials) == 4, 'signed completion materials required')
    run_binding(upstream_run,entry,upstream_run.get('head_sha'),entry['producer'],completed=True)
    expected = resolve_profile(source_api,entry,upstream_run,root=root)
    completed_profile = completion_profile(source_api,entry,upstream_run,observer_run,root=root)
    proof.verify_durable(*materials,expected,completed_profile,runner=runner,now=now)
    completion = proof.validate_completion(materials[2],completed_profile,now=now)
    require(completion['verification']['run_id'] == observer_run['id'] and completion['verification']['attempt'] == observer_run['run_attempt'] and completion['verification']['source_sha'] == observer_run['head_sha'], 'current observer differs')
    require(source_api.repo == writer_api.repo == entry['repository']['name'], 'retention repository differs')
    def accept_existing(raw):
        previous = retained_materials(raw)
        require(previous[:2] == materials[:2], 'retained upstream immutable')
        profiles = retained_profiles(source_api,entry,previous,root=root)
        proof.verify_durable(*previous,*profiles,runner=runner,now=now)
        require(guard() is True, 'protected profile changed during reconciliation')
        return True
    return retain(writer_api,entry,*materials,guard=guard,state_view=state_view,_accept_existing=accept_existing)


def output_materials(root):
    folder = root/'operational-completion-output'
    limits = {'evidence.json':262144,'provenance.sigstore.json':1000000,'completion.json':262144,'completion.sigstore.json':1000000}
    require(folder.is_dir() and folder.resolve() == folder and {path.name for path in folder.iterdir()} == set(limits), 'completion output paths differ')
    result = []
    for name,maximum in limits.items():
        path = folder/name
        require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= maximum, 'completion output file invalid')
        result.append(path.read_bytes())
    return tuple(result)


def main(argv=None):
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument('mode',choices=('produce','prepare-completion','retain'))
    parser.add_argument('--profile',required=True)
    args = parser.parse_args(argv)
    env = os.environ; require(env.get('FACTORY_OPERATIONAL_PROOF_ENABLED','false') == 'true', 'operational proof disabled')
    root = Path(__file__).resolve().parents[2]; api = evidence.GitHub(env.get('GITHUB_REPOSITORY'))
    workflow,event = (SIGNER,'workflow_dispatch') if args.mode == 'produce' else (RETAINER,'workflow_run')
    source = protected_execution(api,root,env,workflow,event)
    entry = select_registry(root,args.profile); initial = proof.canonical(entry)
    def guard():
        protected_execution(api,root,env,workflow,event)
        require(proof.canonical(select_registry(root,args.profile)) == initial, 'protected profile changed')
        return True
    if args.mode == 'produce':
        require(env.get('GITHUB_RUN_ID','').isdigit() and env.get('GITHUB_RUN_ATTEMPT','').isdigit(), 'execution run missing')
        run = api.request('repos/'+api.repo+'/actions/runs/'+env['GITHUB_RUN_ID']+'/attempts/'+env['GITHUB_RUN_ATTEMPT'])
        require(str(run.get('id')) == env['GITHUB_RUN_ID'] and str(run.get('run_attempt')) == env['GITHUB_RUN_ATTEMPT'] and run.get('head_sha') == source, 'execution run differs')
        require(run.get('status') == 'in_progress', 'signer must be actual running execution')
        record = produce(api,entry,run,root=root)
        guard(); output = root/'operational-output'; output.mkdir(exist_ok=False)
        (output/'evidence.json').write_bytes(proof.canonical(record)); return 0
    event_path = Path(env.get('GITHUB_EVENT_PATH',''))
    require(event_path.is_file() and not event_path.is_symlink() and event_path.stat().st_size <= 1000000, 'retainer event unavailable')
    event_document = proof.decode(event_path.read_bytes(),1000000)
    native = event_document.get('workflow_run',{})
    proof.integer(native.get('id')); proof.integer(native.get('run_attempt'))
    run = api.request(f'repos/{api.repo}/actions/runs/{native["id"]}/attempts/{native["run_attempt"]}')
    require(run.get('id') == native['id'] and run.get('run_attempt') == native['run_attempt'], 'completed event attempt differs')
    require(env.get('GITHUB_RUN_ID','').isdigit() and env.get('GITHUB_RUN_ATTEMPT','').isdigit(), 'observer run missing')
    observer = api.request('repos/'+api.repo+'/actions/runs/'+env['GITHUB_RUN_ID']+'/attempts/'+env['GITHUB_RUN_ATTEMPT'])
    require(str(observer.get('id')) == env['GITHUB_RUN_ID'] and str(observer.get('run_attempt')) == env['GITHUB_RUN_ATTEMPT'] and observer.get('head_sha') == source, 'observer execution differs')
    if args.mode == 'prepare-completion':
        raw,bundle,completion = prepare_completion(api,entry,run,observer,root=root)
        guard(); output = root/'operational-completion-output'; output.mkdir(exist_ok=False)
        for name,data in (('evidence.json',raw),('provenance.sigstore.json',bundle),('completion.json',completion)):(output/name).write_bytes(data)
        return 0
    require(env.get('FACTORY_REPORTING_APP_WRITER_ENABLED') == 'true', 'retainer requires selected reporting App')
    writer = transport.create_api(env)
    config = transport.attach_reporting_context({'repository':api.repo,'state_repository':api.repo,'state_branch':entry['retention']['branch']},checkout=root)
    guard(); result = retain_completed(api,writer,entry,run,observer,output_materials(root),guard=guard,root=root,state_view=config['state_view'])
    print(proof.canonical(result).decode()); return 0


if __name__ == '__main__':
    try:raise SystemExit(main())
    except (ValueError,RuntimeError,OSError,KeyError,TypeError):
        raise SystemExit('Historical operational proof unavailable; no live/current-readiness credit')
