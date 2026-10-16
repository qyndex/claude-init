#!/usr/bin/env python3
"""Bounded compact proof data. Integrity validation alone does not establish origin."""
import base64
import binascii
import hashlib
import io
import json
from pathlib import Path
import tempfile
import zipfile
import importlib.util

spec = importlib.util.spec_from_file_location('receipts', Path(__file__).with_name('factory-receipts.py'))
receipts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receipts)
require = receipts.require
paths_spec = importlib.util.spec_from_file_location('state_paths', Path(__file__).with_name('factory-state-paths.py'))
state_paths = importlib.util.module_from_spec(paths_spec); paths_spec.loader.exec_module(state_paths)

MAX_OBJECT = 1048576


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def decode(value):
    require(isinstance(value, str) and len(value) <= 1398104, 'archive object size exceeds bound')
    try:
        raw = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ValueError('archive object encoding invalid') from error
    require(0 < len(raw) <= MAX_OBJECT, 'archive object size exceeds bound')
    return raw


def document(raw):
    return json.loads(raw, object_pairs_hook=receipts.coordinator.contract.no_duplicate_keys)


def validate_record(record, materials, repository, visibility):
    """Validate data integrity only; protected bootstrap/writer origin is required separately."""
    require(isinstance(record, dict) and set(record) == {'schema_version', 'repository', 'visibility', 'source_private', 'run', 'artifact', 'proof', 'receipt_zip', 'materials'}, 'archive record schema differs')
    require(type(record['schema_version']) is int and record['schema_version'] == 1, 'archive record schema differs')
    require(len(canonical(record)) <= MAX_OBJECT, 'archive record size exceeds bound')
    require(record['repository'] == repository and visibility in ('public', 'private') and record['visibility'] == visibility, 'archive repository/store differs')
    require(type(record['source_private']) is bool and (not record['source_private'] or visibility == 'private'), 'private source requires private archive store')
    proof = record['proof']
    require(isinstance(proof, dict) and set(proof) == {'tasks', 'revision', 'delivery', 'provenance', 'run_id', 'merge_sha'}, 'archive proof schema differs')
    provenance = document(proof['provenance']); receipt = provenance['receipt']; facts = provenance['trust']
    require(set(provenance) == {'run_id', 'attempt', 'workflow_id', 'source_sha', 'artifact_id', 'artifact_digest', 'receipt', 'trust', 'execution'} and set(facts) == {'mode', 'profile_id', 'document_sha256', 'policy_sha256', 'runtime'}, 'archive provenance schema differs')
    run = record['run']; artifact = record['artifact']
    require(set(run) == {'id', 'attempt', 'workflow_id', 'path', 'source_sha', 'repository_id'}, 'archive run schema differs')
    require(all(type(run[k]) is int and run[k] > 0 for k in ('id', 'attempt', 'workflow_id', 'repository_id')), 'archive run identity differs')
    require(run['path'] == receipts.RUNTIME_PATHS[0] and receipts.coordinator.contract.digest(run['source_sha'], 40), 'archive source differs')
    require((run['id'], run['attempt'], run['workflow_id'], run['source_sha']) == (provenance['run_id'], provenance['attempt'], provenance['workflow_id'], provenance['source_sha']), 'archive run/proof differs')
    require(set(artifact) == {'id', 'name', 'digest', 'workflow_run'}, 'archive artifact schema differs')
    require(type(artifact['id']) is int and artifact['id'] > 0 and artifact['id'] == provenance['artifact_id'] and artifact['digest'] == provenance['artifact_digest'], 'archive artifact differs')
    execution = provenance['execution']
    require(set(execution) == {'repository_id', 'repository', 'event', 'branch', 'path', 'status', 'conclusion'} and execution['repository_id'] == run['repository_id'] and execution['repository'] == repository and execution['event'] in ('workflow_run', 'workflow_dispatch') and execution['path'] == run['path'] and execution['status'] == 'completed' and execution['conclusion'] == 'success', 'archive execution differs')
    origin = artifact['workflow_run']
    require(isinstance(origin, dict) and set(origin) == {'id', 'repository_id', 'head_repository_id', 'head_sha'} and all(type(origin[k]) is int and origin[k] > 0 for k in ('id', 'repository_id', 'head_repository_id')), 'archive artifact origin differs')
    require(isinstance(origin, dict) and origin.get('id') == run['id'] and origin.get('repository_id') == run['repository_id'] and origin.get('head_repository_id') == run['repository_id'] and origin.get('head_sha') == run['source_sha'], 'archive artifact origin differs')
    require(artifact['name'] == f"factory-receipt-{run['id']}-{run['attempt']}", 'archive attempt differs')
    blob = decode(record['receipt_zip'])
    require(artifact['digest'] == 'sha256:' + digest(blob), 'archive digest differs')
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        require(archive.namelist() == ['receipt.json'] and 0 < archive.infolist()[0].file_size <= 256000, 'archive members exceed bound')
        require(document(archive.read('receipt.json')) == receipt, 'archive receipt differs')
    links = record['materials']
    require(isinstance(links, dict) and isinstance(materials, dict) and set(materials) == set(links.values()), 'archive material set differs')
    require(len(materials) <= 9, 'archive material count exceeds bound')
    decoded = {}
    for key, value in materials.items():
        raw = decode(value)
        require(digest(raw) == key, 'archive material digest differs')
        decoded[key] = raw
    require(set(links) == {'factory/policy.json', 'factory/receipt-trust.json', *receipts.RUNTIME_PATHS, 'spec'}, 'archive material paths differ')
    source = document(decoded[links['factory/policy.json']]); trust = document(decoded[links['factory/receipt-trust.json']])
    require(source['base_branch'] == execution['branch'] and source['repository'] == repository == receipt['repository'] and receipts.coordinator.policy_hash(source) == receipt['policy_sha256'] == facts['policy_sha256'], 'archive policy differs')
    require(receipts.coordinator.policy_hash(trust) == facts['document_sha256'], 'archive trust differs')
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'trust.json'; path.write_bytes(canonical(trust))
        receipts.load_receipt_trust(path, repository, mode='report')
    require({p: digest(decoded[links[p]]) for p in receipts.RUNTIME_PATHS} == facts['runtime'], 'archive runtime differs')
    expected_receipt = {'schema_version', 'repository', 'pull_request', 'head_sha', 'base_sha', 'spec', 'spec_sha256', 'policy_sha256', 'verifier_run', 'reviewer_run', 'eligible', 'merged', 'merge_sha', 'task_ids'}
    require(set(receipt) == expected_receipt and type(receipt['schema_version']) is int and receipt['schema_version'] == 1 and receipt['eligible'] is True and receipt['merged'] is True and source.get('enabled') is True and source.get('merge_enabled') is True, 'archive delivery semantics differ')
    require(all(receipts.coordinator.contract.digest(receipt[k], 40) for k in ('head_sha', 'base_sha', 'merge_sha')) and all(type(receipt[k]) is int and receipt[k] > 0 for k in ('pull_request', 'verifier_run', 'reviewer_run')) and receipt['verifier_run'] != receipt['reviewer_run'], 'archive delivery identity differs')
    matching = [profile for profile in trust['profiles'] if profile['policy_sha256'] == facts['policy_sha256'] and profile['runtime'] == facts['runtime']]
    require(not any(profile['status'] == 'revoked' for profile in matching), 'archive selected trust revoked')
    if facts['mode'] == 'profile':
        require(sum(profile['id'] == facts['profile_id'] and profile['status'] == 'active' for profile in matching) == 1, 'archive selected trust differs')
    else:
        require(facts['mode'] == 'legacy' and facts['profile_id'] is None and trust['legacy_revisions'].get(run['source_sha']) == facts['runtime'], 'archive selected trust differs')
    approved = source['specs'][receipt['spec']]
    require(digest(decoded[links['spec']]) == receipt['spec_sha256'] == approved['sha256'] == proof['revision'], 'archive spec differs')
    require(proof['tasks'] == receipt['task_ids'] == approved['task_ids'] and proof['run_id'] == run['id'] and proof['merge_sha'] == receipt['merge_sha'], 'archive delivery mapping differs')
    require(document(proof['delivery']) == {'repository': repository, 'pr': receipt['pull_request'], 'merge_sha': receipt['merge_sha']}, 'archive delivery differs')
    return record


def check_record_conflict(existing, incoming):
    """Compare already-validated records before a future authenticated append."""
    identity = lambda record: (record['repository'], record['run']['id'], record['run']['attempt'], record['artifact']['id'])
    require(identity(existing) == identity(incoming) and canonical(existing) == canonical(incoming), 'conflicting retained receipt identity/content')
    return existing


def build_record(api, policy, run_id, trust_path, store, *, trust_mode='profile'):
    """Construct only after live API authentication; never accept claimed-authenticated input."""
    require(set(store) == {'repository', 'visibility'} and store['repository'] == api.repo and store['visibility'] in ('public', 'private'), 'archive store differs')
    repo = api.get(f'repos/{api.repo}')
    require(repo['full_name'] == api.repo and type(repo['id']) is int and type(repo['private']) is bool, 'archive repository metadata differs')
    require(not repo['private'] or store['visibility'] == 'private', 'private source requires private archive store')
    proof = receipts.authenticate(api, policy, run_id, historical=True, trust_path=trust_path, trust_mode=trust_mode)
    provenance = document(proof['provenance']); run = api.get(f'repos/{api.repo}/actions/runs/{run_id}')
    require(run['id'] == run_id and run['repository']['id'] == repo['id'] and run['repository']['full_name'] == api.repo and run['head_sha'] == provenance['source_sha'] and run['run_attempt'] == provenance['attempt'] and run['workflow_id'] == provenance['workflow_id'] and run['path'] == receipts.RUNTIME_PATHS[0] and run['event'] in ('workflow_run', 'workflow_dispatch') and run['head_branch'] == policy['base_branch'] and run['status'] == 'completed' and run['conclusion'] == 'success', 'archive observed run differs')
    require(provenance['execution'] == {'repository_id': run['repository']['id'], 'repository': run['repository']['full_name'], 'event': run['event'], 'branch': run['head_branch'], 'path': run['path'], 'status': run['status'], 'conclusion': run['conclusion']}, 'archive observed run changed')
    receipt, artifact, blob = receipts.receipt_artifact(api, run, retain_blob=True)
    require(receipt == provenance['receipt'] and artifact['id'] == provenance['artifact_id'] and artifact['digest'] == provenance['artifact_digest'], 'archive observed artifact differs')
    raw = {p: api.source(p, run['head_sha']) for p in ('factory/policy.json', *receipts.RUNTIME_PATHS)}
    source = document(raw['factory/policy.json']); raw['spec'] = api.source(source['specs'][receipt['spec']]['path'], run['head_sha'])
    raw['factory/receipt-trust.json'] = canonical(receipts.load_receipt_trust(trust_path, api.repo, mode='report'))
    require(all(isinstance(v, bytes) and 0 < len(v) <= MAX_OBJECT for v in raw.values()), 'archive source size exceeds bound')
    materials = {digest(v): base64.b64encode(v).decode() for v in raw.values()}
    record = {'schema_version': 1, 'repository': api.repo, 'visibility': store['visibility'], 'source_private': repo['private'],
              'run': {'id': run_id, 'attempt': run['run_attempt'], 'workflow_id': run['workflow_id'], 'path': run['path'], 'source_sha': run['head_sha'], 'repository_id': repo['id']},
              'artifact': dict({k: artifact[k] for k in ('id', 'name', 'digest')}, workflow_run={k: artifact['workflow_run'][k] for k in ('id', 'repository_id', 'head_repository_id', 'head_sha')}), 'proof': proof,
              'receipt_zip': base64.b64encode(blob).decode(), 'materials': {p: digest(v) for p, v in raw.items()}}
    return validate_record(record, materials, api.repo, store['visibility']), materials


def instant(value):
    from datetime import datetime
    require(isinstance(value, str), 'archive coverage timestamp invalid')
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError as error:
        raise ValueError('archive coverage timestamp invalid') from error
    require(parsed.tzinfo is not None, 'archive coverage timestamp requires timezone')
    return parsed


def verify_bootstrap(api, approval_path, *, now=None):
    """Read-only proof under an explicitly reviewed protected approval input.

    GitHub API reads are the external trust boundary. A caller must load approval
    from reviewed authority, never from a candidate or the data branch itself.
    Existing state protection without exclusive App updates is insufficient.
    """
    from datetime import datetime, timezone
    from urllib.parse import quote
    import re
    now = now or datetime.now(timezone.utc)
    raw = Path(approval_path).read_bytes()
    require(0 < len(raw) <= 65536, 'archive bootstrap approval size invalid')
    approval = document(raw)
    expected = {'schema_version', 'repository', 'repository_id', 'private', 'branch', 'bootstrap_sha', 'bootstrap_tree', 'coverage_from', 'observed_at', 'writer_app_id', 'policies'}
    require(isinstance(approval, dict) and set(approval) == expected and type(approval['schema_version']) is int and approval['schema_version'] == 1, 'archive bootstrap schema differs')
    require(approval['repository'] == api.repo, 'archive bootstrap repository differs')
    require(all(type(approval[k]) is int and approval[k] > 0 for k in ('repository_id', 'writer_app_id')) and type(approval['private']) is bool, 'archive bootstrap repository/writer invalid')
    branch = approval['branch']
    require(isinstance(branch, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', branch) is not None and '..' not in branch and not branch.endswith('/'), 'archive bootstrap branch invalid')
    require(all(receipts.coordinator.contract.digest(approval[k], 40) for k in ('bootstrap_sha', 'bootstrap_tree')), 'archive bootstrap revision invalid')
    observed = instant(approval['observed_at']); origin = instant(approval['coverage_from'])
    require(origin <= observed <= now, 'archive coverage/approval clock invalid')
    consumed = 0; calls = 0

    def read(path):
        nonlocal consumed, calls
        require(calls < 2048, 'archive bootstrap API call bound reached; explicit coverage gap')
        calls += 1
        value = api.request(path)
        size = len(canonical(value)); consumed += size
        require(size <= MAX_OBJECT and consumed <= 33554432, 'archive bootstrap API response bound reached; explicit coverage gap')
        return value

    root = f'repos/{api.repo}'
    repo = read(root)
    require(repo['full_name'] == api.repo and type(repo['id']) is int and repo['id'] == approval['repository_id'] and type(repo['private']) is bool and repo['private'] == approval['private'] and repo['archived'] is False, 'archive bootstrap repository differs')
    require(branch != repo['default_branch'], 'archive cannot use default branch')
    rules = read(root + '/rules/branches/' + quote(branch, safe=''))
    require(isinstance(rules, list) and len(rules) <= 64, 'archive protection rules invalid')
    ids = {str(rule.get('ruleset_id')) for rule in rules}
    require(isinstance(approval['policies'], dict) and 0 < len(ids) <= 16 and ids == set(approval['policies']), 'archive reviewed protection identities differ')
    covered = set(); exclusive = 0
    conditions = {'ref_name': {'include': ['refs/heads/' + branch], 'exclude': []}}
    for identity in sorted(ids):
        require(identity.isdecimal() and int(identity) > 0, 'archive protection identity invalid')
        policy = read(root + '/rulesets/' + identity)
        require(digest(canonical(policy)) == approval['policies'][identity], 'archive protection policy changed')
        require(type(policy['id']) is int and policy['id'] == int(identity) and policy['source'] == api.repo and policy['source_type'] == 'Repository' and policy['target'] == 'branch' and policy['enforcement'] == 'active' and policy['conditions'] == conditions, 'archive protection scope differs')
        require((observed - instant(policy['updated_at'])).total_seconds() >= 60, 'archive protection must settle before approval')
        kinds = [rule['type'] for rule in policy['rules']]
        if 'update' in kinds:
            require(policy['rules'] == [{'type': 'update'}], 'archive exclusive writer policy must be update-only')
            require(policy['bypass_actors'] == [{'actor_id': approval['writer_app_id'], 'actor_type': 'Integration', 'bypass_mode': 'always'}], 'archive exclusive App writer differs')
            exclusive += 1
        else:
            require(policy['bypass_actors'] == [] and set(kinds) <= {'non_fast_forward', 'deletion'}, 'archive rewrite/deletion protection must be no-bypass')
            covered.update(kinds)
    require(exclusive == 1 and covered == {'non_fast_forward', 'deletion'}, 'archive exclusive writer or immutable protection missing')
    ref = read(root + '/git/ref/heads/' + quote(branch, safe=''))
    require(ref['ref'] == 'refs/heads/' + branch and ref['object']['type'] == 'commit', 'archive state reference differs')
    head = ref['object']['sha']; sha = head; seen = set(); head_tree = None
    for _ in range(256):
        require(receipts.coordinator.contract.digest(sha, 40) and sha not in seen, 'archive bootstrap ancestry invalid')
        seen.add(sha)
        commit = read(root + '/git/commits/' + sha)
        require(commit['sha'] == sha and receipts.coordinator.contract.digest(commit['tree']['sha'], 40), 'archive bootstrap commit/tree differs')
        tree_sha = commit['tree']['sha']
        if head_tree is None:
            head_tree = tree_sha
        class Reader:
            repo = api.repo
            request = staticmethod(read)
        cursor = None
        for tree_window in range(10):
            tree = state_paths.scan_tree(Reader(), root, tree_sha, cursor=cursor)
            if tree['complete']:
                break
            cursor = tree['cursor']  # Checked in-memory continuation; never external input.
        require(tree['complete'], 'archive bootstrap tree incomplete; authenticated cursor continuation required')
        if sha == approval['bootstrap_sha']:
            require(tree_sha == approval['bootstrap_tree'], 'archive bootstrap tree differs')
            break
        require(isinstance(commit['parents'], list) and len(commit['parents']) == 1, 'archive bootstrap ancestry missing or merged')
        sha = commit['parents'][0]['sha']
    else:
        raise ValueError('archive bootstrap ancestry bound reached; explicit coverage gap')
    for identity in sorted(ids):
        require(digest(canonical(read(root + '/rulesets/' + identity))) == approval['policies'][identity], 'archive protection changed during verification')
    require(read(root + '/git/ref/heads/' + quote(branch, safe='')) == ref, 'archive state changed during bootstrap verification')
    return {'repository': api.repo, 'repository_id': repo['id'], 'private': repo['private'], 'branch': branch, 'head': head, 'tree': head_tree,
            'bootstrap_sha': approval['bootstrap_sha'], 'bootstrap_tree': approval['bootstrap_tree'], 'coverage_from': approval['coverage_from'],
            'writer_app_id': approval['writer_app_id'], 'policies': approval['policies'], 'approval_sha256': digest(canonical(approval))}


def coverage_status(bootstrap, timestamp, *, available):
    """Classify proof availability without resetting origin or authorizing delivery."""
    require(type(available) is bool, 'archive availability must be explicit')
    before = instant(timestamp) < instant(bootstrap['coverage_from'])
    status = 'outside-coverage' if before else 'complete' if available else 'gap'
    return {'status': status, 'coverage_from': bootstrap['coverage_from'], 'reason': 'before reviewed origin' if before else 'retained proof available' if available else 'required history unavailable'}


def archive_stream(repository):
    return digest(canonical(['factory-receipt-archive-v1', repository]))


def fixed_reader(api, root):
    """Bounded immutable fixed-path reads; origin must be authenticated separately."""
    def item_at(tree_sha, path):
        current = tree_sha; prefix = ''
        for part in path.split('/'):
            tree = api.request(root+'/git/trees/'+current)
            require(tree.get('sha') == current and tree.get('truncated') is False and isinstance(tree.get('tree'), list), 'archive fixed-path tree incomplete')
            found = [entry for entry in tree['tree'] if entry.get('path') == part]
            require(len(found) <= 1, 'archive fixed path ambiguous')
            if not found:
                return None
            item = dict(found[0], path=prefix+part); state_paths.validate_entry(item)
            prefix += part+'/'
            if prefix[:-1] == path:
                return item
            require(item['type'] == 'tree', 'archive fixed path crosses blob')
            current = item['sha']
        raise ValueError('archive fixed path invalid')

    def blob_at(tree_sha, path):
        item = item_at(tree_sha, path)
        if item is None:
            return None
        require(item['type'] == 'blob' and 0 < item['size'] <= MAX_OBJECT, 'archive stored blob size/mode invalid')
        value = api.request(root+'/git/blobs/'+item['sha'])
        require(value.get('encoding') == 'base64' and value.get('sha') == item['sha'], 'archive stored blob identity differs')
        raw = base64.b64decode(''.join(value['content'].split()), validate=True)
        require(len(raw) == value['size'] == item['size'] and hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest() == item['sha'], 'archive stored blob bytes differ')
        return raw

    return item_at, blob_at


def append_delivery(source_api, state_api, policy, run_id, trust_path, store, approval_path, stream, *, trust_mode='profile'):
    """Authenticate and atomically append; no runtime credit or legacy policy relaxation."""
    from urllib.parse import quote
    import uuid
    require(source_api.repo == state_api.repo == policy['repository'] == store['repository'] and stream == archive_stream(policy['repository']), 'foreign archive append repository/stream')
    root = f'repos/{state_api.repo}'
    consumed = 0; immutable_cache = {}; uncertain = False

    def charge(value, *, source_file=False):
        nonlocal consumed
        size = (2*len(value)+16384 if source_file else len(value)) if isinstance(value, bytes) else len(canonical(value))
        consumed += size
        require(size <= 2097152 and consumed <= 33554432, 'archive append API observation budget exceeded')
        return value

    class ObservedSource:
        repo = source_api.repo

        def get(self, path):
            return charge(source_api.get(path))

        def source(self, path, sha):
            return charge(source_api.source(path, sha), source_file=True)

        def request(self, path, **kwargs):
            require(kwargs.get('method', 'GET') == 'GET', 'archive source API must be read-only')
            return charge(source_api.request(path, **kwargs))

    require(trust_path is not None and trust_mode in ('profile', 'legacy'), 'explicit protected archive trust document/mode required')
    record, materials = build_record(ObservedSource(), policy, run_id, trust_path, store, trust_mode=trust_mode)
    record_bytes = canonical(record); record_hash = digest(record_bytes)
    execution = {'repository': state_api.repo, 'stream': stream, 'run_id': record['run']['id'], 'attempt': record['run']['attempt']}
    identity = digest(canonical(execution))  # Artifact replacement cannot evade same-attempt identity.
    identity_path = f'receipt-archive/index/{stream}/identities/{identity[:2]}/{identity}.json'
    journal_path = f'receipt-archive/discovery/{stream}.json'

    class Bounded:
        repo = state_api.repo

        def request(self, path, method='GET', payload=None):
            nonlocal consumed
            require(path == root or path.startswith(root+'/'), 'foreign archive state API path')
            require(method == 'GET' or (method == 'POST' and path in {root+'/git/blobs', root+'/git/trees', root+'/git/commits'}) or (method == 'PATCH' and path.startswith(root+'/git/refs/heads/')), 'archive write endpoint not permitted')
            cacheable = method == 'GET' and ('/git/trees/' in path or '/git/blobs/' in path)
            if cacheable and path in immutable_cache:
                return immutable_cache[path]
            require(consumed <= 31457280, 'archive append invocation byte budget exhausted')
            try:
                value = state_api.request(path, method=method, payload=payload)
            except Exception as error:
                if uncertain:
                    raise ValueError('archive append uncertain; authoritative state could not be reconciled') from error
                raise
            charge(value)
            if cacheable:
                immutable_cache[path] = value
            return value

    api = Bounded()

    item_at, blob_at = fixed_reader(api, root)

    for attempt in range(3):
        anchor = verify_bootstrap(api, approval_path)
        require(record['run']['repository_id'] == anchor['repository_id'] and record['source_private'] == anchor['private'], 'archive source/store repository identity differs')
        require(store['visibility'] == ('private' if anchor['private'] else 'public'), 'archive actual store visibility differs')
        head = anchor['head']; tree = anchor['tree']
        journal_raw = blob_at(tree, journal_path)
        if journal_raw is None:
            require(item_at(tree, 'receipt-archive/index/'+stream) is None, 'archive discovery missing for existing stream; never reset')
            journal = {'schema_version': 1, 'repository': state_api.repo, 'stream': stream, 'coverage_from': anchor['coverage_from'], 'next_segment': 0, 'records_count': 0}
        else:
            journal = document(journal_raw)
            require(set(journal) == {'schema_version', 'repository', 'stream', 'coverage_from', 'next_segment', 'records_count'} and type(journal['schema_version']) is int and journal['schema_version'] == 1 and journal['repository'] == state_api.repo and journal['stream'] == stream and journal['coverage_from'] == anchor['coverage_from'] and type(journal['next_segment']) is int and 0 <= journal['next_segment'] < 10**12 and type(journal['records_count']) is int and journal['records_count'] == journal['next_segment'], 'archive discovery identity/progress differs')
        previous = blob_at(tree, identity_path)
        if previous is not None:
            old = document(previous)
            require(set(old) == {'schema_version', 'repository', 'stream', 'run_id', 'attempt', 'artifact_id', 'record_sha256', 'segment'} and type(old['schema_version']) is int and old['schema_version'] == 1 and all(type(old[key]) is int and old[key] > 0 for key in ('run_id', 'attempt', 'artifact_id')) and all(old[key] == execution[key] for key in execution), 'archive conflicting execution index')
            require(old['artifact_id'] == record['artifact']['id'] and old['record_sha256'] == record_hash and type(old['segment']) is int and 0 <= old['segment'] < journal['next_segment'], 'archive conflicting retained execution/artifact')
            retained = blob_at(tree, f'receipt-archive/objects/{record_hash[:2]}/{record_hash}.json')
            require(retained == record_bytes, 'archive conflicting retained object')
            retained_materials = {}
            for key in materials:
                raw = blob_at(tree, f'receipt-archive/materials/{key[:2]}/{key}.json')
                wrapper = document(raw) if raw is not None else {}
                require(type(wrapper.get('schema_version')) is int and wrapper == {'schema_version': 1, 'sha256': key, 'encoding': 'base64', 'content': materials[key]}, 'archive conflicting retained material')
                retained_materials[key] = wrapper['content']
            validate_record(document(retained), retained_materials, state_api.repo, store['visibility'])
            segment_raw = blob_at(tree, state_paths.segment_path(stream, old['segment']))
            segment = state_paths.validate_segment(document(segment_raw), state_api.repo, stream, old['segment'])
            require(segment['records'] == [{'run_id': execution['run_id'], 'attempt': execution['attempt'], 'artifact_id': old['artifact_id'], 'record_sha256': record_hash}], 'archive conflicting retained segment')
            return {'status': 'already-appended', 'head': head, 'record_sha256': record_hash}
        number = journal['next_segment']
        segment = {'schema_version': 1, 'repository': state_api.repo, 'stream': stream, 'number': number, 'records': [{'run_id': execution['run_id'], 'attempt': execution['attempt'], 'artifact_id': record['artifact']['id'], 'record_sha256': record_hash}]}
        state_paths.validate_segment(segment, state_api.repo, stream, number)
        segment_path = state_paths.segment_path(stream, number)
        require(blob_at(tree, segment_path) is None, 'archive conflicting occupied index sequence')
        index = dict(execution, schema_version=1, artifact_id=record['artifact']['id'], record_sha256=record_hash, segment=number)
        changes = {f'receipt-archive/objects/{record_hash[:2]}/{record_hash}.json': record_bytes, identity_path: canonical(index), segment_path: canonical(segment)}
        for key, value in materials.items():
            changes[f'receipt-archive/materials/{key[:2]}/{key}.json'] = canonical({'schema_version': 1, 'sha256': key, 'encoding': 'base64', 'content': value})
        journal.update(next_segment=number+1, records_count=number+1)
        changes[journal_path] = canonical(journal)
        entries = []; prepared = []
        for path, raw in changes.items():
            require(0 < len(raw) <= MAX_OBJECT, 'archive encoded object size exceeds bound')
            existing = blob_at(tree, path)
            require(existing is None or existing == raw or path == journal_path, 'archive conflicting immutable object')
            if existing == raw:
                continue
            sha = hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
            state_paths.validate_entry({'path': path, 'type': 'blob', 'mode': '100644', 'sha': sha, 'size': len(raw)})
            prepared.append((path, raw, sha))
        for path, raw, sha in prepared:
            uploaded = api.request(root+'/git/blobs', 'POST', {'encoding': 'base64', 'content': base64.b64encode(raw).decode()})
            require(uploaded.get('sha') == sha, 'archive uploaded blob differs')
            entries.append({'path': path, 'type': 'blob', 'mode': '100644', 'sha': sha})
        newtree = api.request(root+'/git/trees', 'POST', {'base_tree': tree, 'tree': entries})
        require(state_paths.valid_hash(newtree.get('sha'), 40), 'archive created tree invalid')
        commit = api.request(root+'/git/commits', 'POST', {'message': 'factory: compact receipt append '+uuid.uuid4().hex, 'tree': newtree['sha'], 'parents': [head]})
        require(state_paths.valid_hash(commit.get('sha'), 40) and commit['tree']['sha'] == newtree['sha'] and [parent['sha'] for parent in commit['parents']] == [head], 'archive created commit ancestry differs')
        for policy_id, expected_hash in anchor['policies'].items():
            require(digest(canonical(api.request(root+'/rulesets/'+policy_id))) == expected_hash, 'archive writer protection changed before append')
        try:
            result = api.request(root+'/git/refs/heads/'+quote(anchor['branch'], safe=''), 'PATCH', {'sha': commit['sha'], 'force': False})
            require(result['ref'] == 'refs/heads/'+anchor['branch'] and result['object']['sha'] == commit['sha'], 'archive reference acknowledgement differs')
        except Exception:
            uncertain = True
            continue  # Ref may have committed: re-read authoritative origin before any progress claim.
        return {'status': 'appended', 'head': commit['sha'], 'record_sha256': record_hash}
    raise ValueError('archive append uncertain after three CAS observations; reconcile before advancing')


def project_retained(state_api, policy, db_path, trust_path, store, approval_path, stream):
    """Reconstruct report facts only from the reviewed protected archive chain.

    Never calls source Actions artifacts or task lifecycle APIs. Per-invocation
    bounds fail explicitly; resumable discovery/anchors are a separate stage.
    Caller-supplied records, hashes or cursor JSON cannot establish origin.
    """
    import sqlite3
    require(state_api.repo == policy['repository'] == store['repository'] and stream == archive_stream(state_api.repo), 'foreign archive reporting repository/stream')
    require(set(store) == {'repository', 'visibility'} and store['visibility'] in ('public', 'private'), 'archive reporting store differs')
    consumed = 0; cache = {}; root = 'repos/'+state_api.repo

    class ReadOnly:
        repo = state_api.repo

        def request(self, path, method='GET', payload=None):
            nonlocal consumed
            require(method == 'GET' and payload is None and (path == root or path.startswith(root+'/')), 'archive reporting API must be read-only and same repository')
            immutable = '/git/trees/' in path or '/git/blobs/' in path
            if immutable and path in cache:
                return cache[path]
            value = state_api.request(path)
            size = len(canonical(value)); consumed += size
            require(size <= 2097152 and consumed <= 33554432, 'archive reporting observation bound reached; explicit coverage gap')
            if immutable:
                cache[path] = value
            return value

    api = ReadOnly(); anchor = verify_bootstrap(api, approval_path)
    require(store['visibility'] == ('private' if anchor['private'] else 'public'), 'archive actual store visibility differs')
    _, blob_at = fixed_reader(api, root); tree = anchor['tree']
    require(blob_at(anchor['bootstrap_tree'], f'receipt-archive/discovery/{stream}.json') is None, 'archive pre-bootstrap proof requires explicit reviewed import')
    journal_raw = blob_at(tree, f'receipt-archive/discovery/{stream}.json')
    require(journal_raw is not None, 'archive discovery missing; cannot claim retained coverage')
    journal = document(journal_raw)
    require(set(journal) == {'schema_version', 'repository', 'stream', 'coverage_from', 'next_segment', 'records_count'} and type(journal['schema_version']) is int and journal['schema_version'] == 1 and journal['repository'] == state_api.repo and journal['stream'] == stream and journal['coverage_from'] == anchor['coverage_from'] and type(journal['next_segment']) is int and 0 <= journal['next_segment'] < 10**12 and type(journal['records_count']) is int and journal['records_count'] == journal['next_segment'], 'archive discovery identity/progress differs')
    require(journal['next_segment'] <= 128, 'archive reporting segment invocation bound reached; resumable continuation required')
    proofs = []; seen = set()
    for number in range(journal['next_segment']):
        raw = blob_at(tree, state_paths.segment_path(stream, number))
        require(raw is not None, 'archive retained segment missing')
        segment = state_paths.validate_segment(document(raw), state_api.repo, stream, number)
        require(len(segment['records']) == 1, 'archive discovery record count differs')
        for reference in segment['records']:
            identity = digest(canonical({'repository': state_api.repo, 'stream': stream, 'run_id': reference['run_id'], 'attempt': reference['attempt']}))
            require(identity not in seen, 'archive conflicting duplicate execution')
            seen.add(identity)
            index_raw = blob_at(tree, f'receipt-archive/index/{stream}/identities/{identity[:2]}/{identity}.json')
            expected_index = dict(reference, schema_version=1, repository=state_api.repo, stream=stream, segment=number)
            require(index_raw is not None and document(index_raw) == expected_index, 'archive retained execution index differs')
            key = reference['record_sha256']
            raw = blob_at(tree, f'receipt-archive/objects/{key[:2]}/{key}.json')
            require(raw is not None and digest(raw) == key, 'archive retained record missing or digest differs')
            require(blob_at(anchor['bootstrap_tree'], f'receipt-archive/objects/{key[:2]}/{key}.json') is None, 'archive object pre-bootstrap requires explicit reviewed import')
            record = document(raw); links = record.get('materials')
            require(isinstance(links, dict) and len(links) <= 9 and all(state_paths.valid_hash(k, 64) for k in links.values()), 'archive material links differ')
            materials = {}
            for key in set(links.values()):
                raw = blob_at(tree, f'receipt-archive/materials/{key[:2]}/{key}.json')
                require(blob_at(anchor['bootstrap_tree'], f'receipt-archive/materials/{key[:2]}/{key}.json') is None, 'archive material pre-bootstrap requires explicit reviewed import')
                require(raw is not None, 'archive retained material missing')
                wrapper = document(raw)
                require(set(wrapper) == {'schema_version', 'sha256', 'encoding', 'content'} and type(wrapper['schema_version']) is int and wrapper['schema_version'] == 1 and wrapper['sha256'] == key and wrapper['encoding'] == 'base64', 'archive material wrapper differs')
                materials[key] = wrapper['content']
            validate_record(record, materials, state_api.repo, store['visibility'])
            require(record['run']['repository_id'] == anchor['repository_id'] and record['source_private'] == anchor['private'], 'archive retained repository identity/privacy differs')
            require((record['run']['id'], record['run']['attempt'], record['artifact']['id']) == (reference['run_id'], reference['attempt'], reference['artifact_id']), 'archive retained index/record identity differs')
            source = document(decode(materials[links['factory/policy.json']]))
            require(record['run']['workflow_id'] == source['receipts']['workflow_id'], 'archive retained workflow differs')
            proofs.append(receipts.annotate_reported_trust(record['proof'], trust_path, state_api.repo))
    require(len(proofs) == journal['records_count'], 'archive retained count differs')
    by_task = {}
    for proof in proofs:
        for task in proof['tasks']:
            require(task not in by_task or by_task[task] == proof, 'conflicting reporting delivery proof')
            by_task[task] = proof
    # All origin, material and conflict checks finish before any SQLite mutation.
    require(verify_bootstrap(api, approval_path) == anchor, 'archive reporting origin changed before projection')
    with sqlite3.connect(db_path) as db:
        db.execute('CREATE TABLE IF NOT EXISTS delivery_receipts(task TEXT PRIMARY KEY, revision TEXT NOT NULL, receipt TEXT NOT NULL)')
        db.execute('CREATE TABLE IF NOT EXISTS delivery_provenance(task TEXT PRIMARY KEY, provenance TEXT NOT NULL)')
        db.execute('CREATE TABLE IF NOT EXISTS delivery_trust(task TEXT PRIMARY KEY, status TEXT NOT NULL)')
        require({row[0] for row in db.execute('SELECT task FROM delivery_receipts')} <= set(by_task), 'archive retained coverage missing existing reporting fact')
        for task, proof in sorted(by_task.items()):
            previous = db.execute('SELECT revision,receipt FROM delivery_receipts WHERE task=?', (task,)).fetchone()
            provenance = db.execute('SELECT provenance FROM delivery_provenance WHERE task=?', (task,)).fetchone()
            require(previous is None or (previous == (proof['revision'], proof['delivery']) and provenance == (proof['provenance'],)), 'conflicting reporting delivery proof')
            require(provenance is None or previous is not None, 'conflicting orphan reporting provenance')
            db.execute('INSERT OR IGNORE INTO delivery_receipts VALUES(?,?,?)', (task, proof['revision'], proof['delivery']))
            db.execute('INSERT OR IGNORE INTO delivery_provenance VALUES(?,?)', (task, proof['provenance']))
            db.execute('INSERT INTO delivery_trust VALUES(?,?) ON CONFLICT(task) DO UPDATE SET status=excluded.status', (task, proof['trust_status']))
    return len(by_task)


def retained_execution(api, anchor, store, stream, run_id, attempt):
    """Read known proof first from an already authenticated protected archive view."""
    require(api.repo == anchor['repository'] == store['repository'] and store['visibility'] == ('private' if anchor['private'] else 'public'), 'retained lookup store/privacy differs')
    require(stream == archive_stream(api.repo) and all(type(x) is int and x > 0 for x in (run_id, attempt)), 'retained lookup identity invalid')
    root = 'repos/'+api.repo; _, blob_at = fixed_reader(api, root)
    identity = digest(canonical({'repository': api.repo, 'stream': stream, 'run_id': run_id, 'attempt': attempt}))
    raw = blob_at(anchor['tree'], f'receipt-archive/index/{stream}/identities/{identity[:2]}/{identity}.json')
    if raw is None:
        return None  # Absence is never evidence of a non-delivery outcome.
    require(blob_at(anchor['bootstrap_tree'], f'receipt-archive/index/{stream}/identities/{identity[:2]}/{identity}.json') is None, 'retained proof pre-bootstrap requires explicit reviewed import')
    index = document(raw)
    require(set(index) == {'schema_version', 'repository', 'stream', 'run_id', 'attempt', 'artifact_id', 'record_sha256', 'segment'} and type(index['schema_version']) is int and index['schema_version'] == 1 and index['repository'] == api.repo and index['stream'] == stream and type(index['run_id']) is int and index['run_id'] == run_id and type(index['attempt']) is int and index['attempt'] == attempt and type(index['artifact_id']) is int and index['artifact_id'] > 0 and type(index['segment']) is int and 0 <= index['segment'] < 10**12 and state_paths.valid_hash(index['record_sha256'], 64), 'retained lookup index differs')
    require(blob_at(anchor['bootstrap_tree'], state_paths.segment_path(stream, index['segment'])) is None, 'retained segment pre-bootstrap requires explicit reviewed import')
    journal_path = f'receipt-archive/discovery/{stream}.json'
    require(blob_at(anchor['bootstrap_tree'], journal_path) is None, 'retained discovery pre-bootstrap requires explicit reviewed import')
    journal_raw = blob_at(anchor['tree'], journal_path)
    require(journal_raw is not None, 'retained discovery missing')
    journal = document(journal_raw)
    require(set(journal) == {'schema_version', 'repository', 'stream', 'coverage_from', 'next_segment', 'records_count'} and type(journal['schema_version']) is int and journal['schema_version'] == 1 and journal['repository'] == api.repo and journal['stream'] == stream and journal['coverage_from'] == anchor['coverage_from'] and type(journal['next_segment']) is int and index['segment'] < journal['next_segment'] < 10**12 and type(journal['records_count']) is int and journal['records_count'] == journal['next_segment'], 'retained discovery differs')
    segment_raw = blob_at(anchor['tree'], state_paths.segment_path(stream, index['segment']))
    require(segment_raw is not None, 'retained lookup segment missing')
    segment = state_paths.validate_segment(document(segment_raw), api.repo, stream, index['segment'])
    reference = {key: index[key] for key in ('run_id', 'attempt', 'artifact_id', 'record_sha256')}
    require(sum(row == reference for row in segment['records']) == 1, 'retained lookup segment differs')
    key = index['record_sha256']; raw = blob_at(anchor['tree'], f'receipt-archive/objects/{key[:2]}/{key}.json')
    require(blob_at(anchor['bootstrap_tree'], f'receipt-archive/objects/{key[:2]}/{key}.json') is None, 'retained object pre-bootstrap requires explicit reviewed import')
    require(raw is not None and digest(raw) == key, 'retained lookup object missing or altered')
    record = document(raw); links = record.get('materials')
    require(isinstance(links, dict) and len(links) <= 9 and all(state_paths.valid_hash(k, 64) for k in links.values()), 'retained lookup materials differ')
    materials = {}
    for material in set(links.values()):
        raw = blob_at(anchor['tree'], f'receipt-archive/materials/{material[:2]}/{material}.json')
        require(blob_at(anchor['bootstrap_tree'], f'receipt-archive/materials/{material[:2]}/{material}.json') is None, 'retained material pre-bootstrap requires explicit reviewed import')
        require(raw is not None, 'retained lookup material missing')
        wrapper = document(raw)
        require(set(wrapper) == {'schema_version', 'sha256', 'encoding', 'content'} and type(wrapper['schema_version']) is int and wrapper['schema_version'] == 1 and wrapper['sha256'] == material and wrapper['encoding'] == 'base64', 'retained lookup material differs')
        materials[material] = wrapper['content']
    validate_record(record, materials, api.repo, store['visibility'])
    require(record['run']['repository_id'] == anchor['repository_id'] and record['source_private'] == anchor['private'] and (record['run']['id'], record['run']['attempt'], record['artifact']['id']) == (run_id, attempt, index['artifact_id']), 'retained lookup record identity/privacy differs')
    source = document(decode(materials[links['factory/policy.json']]))
    require(record['run']['workflow_id'] == source['receipts']['workflow_id'], 'retained lookup workflow differs')
    return {'record_sha256': key, 'record': record}
