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
    consumed = 0

    def read(path):
        nonlocal consumed
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
        tree = state_paths.scan_tree(Reader(), root, tree_sha)
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
