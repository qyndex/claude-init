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
