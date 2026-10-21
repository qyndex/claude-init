#!/usr/bin/env python3
"""Authenticate protected GitHub delivery artifacts before changing runtime state."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import sys
import sqlite3
import zipfile


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    loaded = importlib.util.module_from_spec(spec); spec.loader.exec_module(loaded)
    return loaded


ledger = module('ledger', 'factory-ledger.py')
coordinator = module('coordinator', 'factory-coordinator.py')
RUNTIME_PATHS = ('.github/workflows/factory-merge.yml', '.claude/scripts/factory-coordinator.py',
                 '.claude/scripts/factory-preflight.py', '.claude/scripts/validate-candidate-evidence.py',
                 '.claude/scripts/factory-provenance.py', '.claude/scripts/factory-bounded-process.py',
                 '.claude/scripts/factory-policy-observation.py')
# Schema1 report-only history has exactly these reviewed dependency families.
# Parsing a historical family never authorizes current source authentication.
HISTORICAL_RUNTIME_PATHS = ('.github/workflows/factory-merge.yml', '.claude/scripts/factory-coordinator.py',
                            '.claude/scripts/factory-preflight.py', '.claude/scripts/validate-candidate-evidence.py',
                            '.claude/scripts/factory-provenance.py', '.claude/scripts/factory-bounded-process.py')
RUNTIME_FAMILIES = (frozenset(HISTORICAL_RUNTIME_PATHS), frozenset(RUNTIME_PATHS))
require = coordinator.require


def load_receipt_trust(path, repository, *, mode):
    """Parse separately reviewed trust data; callers must explicitly select a mode.

    This parser alone grants no receipt authority. Authentication integration must
    independently bind immutable GitHub source bytes and the selected profile.
    """
    require(isinstance(mode, str) and mode in {'profile', 'legacy', 'report'}, 'explicit receipt trust mode required')
    raw = Path(path).read_bytes()
    require(0 < len(raw) <= 262144, 'receipt trust document size exceeds bound')
    trust = json.loads(raw, object_pairs_hook=coordinator.contract.no_duplicate_keys)
    require(isinstance(trust, dict) and set(trust) == {'schema_version', 'repository', 'profiles', 'legacy_revisions'}, 'receipt trust schema differs')
    require(type(trust['schema_version']) is int and trust['schema_version'] == 1, 'receipt trust schema version differs')
    require(isinstance(repository, str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository) is not None and trust['repository'] == repository, 'receipt trust repository differs')

    def runtime(pins):
        require(isinstance(pins, dict) and frozenset(pins) in RUNTIME_FAMILIES, 'receipt trust runtime closure differs')
        require(all(coordinator.contract.digest(value, 64) for value in pins.values()), 'receipt trust runtime digest invalid')

    profiles = trust['profiles']
    require(isinstance(profiles, list) and len(profiles) <= 64, 'receipt trust profiles malformed')
    identities = set()
    for profile in profiles:
        require(isinstance(profile, dict) and set(profile) == {'id', 'status', 'policy_sha256', 'runtime'}, 'receipt trust profile schema differs')
        identity = profile['id']
        require(isinstance(identity, str) and re.fullmatch(r'[a-z][a-z0-9-]{0,63}', identity) is not None, 'receipt trust profile identity invalid')
        require(identity not in identities, 'duplicate receipt trust profile identity')
        identities.add(identity)
        require(profile['status'] in ('active', 'revoked'), 'receipt trust profile status invalid')
        require(coordinator.contract.digest(profile['policy_sha256'], 64), 'receipt trust policy digest invalid')
        runtime(profile['runtime'])
    revisions = trust['legacy_revisions']
    require(isinstance(revisions, dict) and len(revisions) <= 128, 'receipt trust legacy revisions malformed')
    for revision, pins in revisions.items():
        require(coordinator.contract.digest(revision, 40), 'receipt trust legacy revision invalid')
        runtime(pins)
    if mode == 'profile':
        require(any(profile['status'] == 'active' for profile in profiles), 'receipt trust active profile missing')
    elif mode == 'legacy':
        require(bool(revisions), 'receipt trust legacy revisions missing')
    return trust


def receipt_artifact(api, run, *, retain_blob=False):
    name = f'factory-receipt-{run["id"]}-{run["run_attempt"]}'
    pages = api.request(f'repos/{api.repo}/actions/runs/{run["id"]}/artifacts', paginate=True)
    candidates = [a for page in pages for a in page['artifacts'] if a['name'] == name and not a['expired']]
    require(len(candidates) == 1, 'receipt artifact missing or ambiguous')
    artifact = candidates[0]
    origin = artifact.get('workflow_run')
    repository_id = run['repository'].get('id')
    require(type(repository_id) is int and repository_id > 0 and isinstance(origin, dict), 'receipt artifact origin missing')
    require(type(origin.get('id')) is int and origin['id'] == run['id'] and
            type(origin.get('repository_id')) is int and origin['repository_id'] == repository_id and
            type(origin.get('head_repository_id')) is int and origin['head_repository_id'] == repository_id and
            origin.get('head_sha') == run['head_sha'], 'receipt artifact origin differs')
    require(0 < artifact['size_in_bytes'] <= 1_000_000, 'receipt archive too large')
    blob = api.request(f'repos/{api.repo}/actions/artifacts/{artifact["id"]}/zip', raw=True)
    require(len(blob) <= 1_000_000 and artifact.get('digest') == 'sha256:' + hashlib.sha256(blob).hexdigest(), 'receipt archive digest differs')
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        require(archive.namelist() == ['receipt.json'], 'unexpected receipt archive entries')
        require(0 < archive.infolist()[0].file_size <= 256_000, 'receipt document too large')
        document = json.loads(archive.read('receipt.json'), object_pairs_hook=coordinator.contract.no_duplicate_keys)
        return (document, artifact, blob) if retain_blob else (document, artifact)


def authenticate_source(api, policy, run, *, trust_path, trust_mode):
    """Authenticate exact emitter source, independently of outcome/artifact status."""
    repo = policy['repository']
    require(api.repo == repo and run['repository']['full_name'] == repo and type(run.get('id')) is int and run['id'] > 0 and type(run.get('run_attempt')) is int and run['run_attempt'] > 0 and type(run.get('workflow_id')) is int and run['workflow_id'] == policy['receipts']['workflow_id'], 'foreign receipt producer')
    require(run.get('event') in ('workflow_run', 'workflow_dispatch') and run.get('head_branch') == policy['base_branch'] and run.get('path') == RUNTIME_PATHS[0] and coordinator.contract.digest(run.get('head_sha'), 40), 'unprotected receipt source identity')
    require(trust_mode in ('legacy', 'profile'), 'explicit receipt trust mode required')
    require(trust_path is not None or trust_mode == 'legacy', 'external receipt profile required')
    trust = load_receipt_trust(trust_path, repo, mode='report') if trust_path is not None else None

    def source_bytes(path):
        value = api.source(path, run['head_sha'])
        require(isinstance(value, bytes) and 0 < len(value) <= 1048576, 'receipt source size exceeds bound')
        return value

    source = json.loads(source_bytes('factory/policy.json'), object_pairs_hook=coordinator.contract.no_duplicate_keys)
    observed = {path: hashlib.sha256(source_bytes(path)).hexdigest() for path in RUNTIME_PATHS}
    if trust is not None:
        require(not any(profile['status'] == 'revoked' and profile['policy_sha256'] == coordinator.policy_hash(source) and profile['runtime'] == observed for profile in trust['profiles']), 'receipt source profile revoked')
    selected = None
    if trust_mode == 'profile':
        matches = [profile for profile in trust['profiles'] if profile['status'] == 'active' and profile['policy_sha256'] == coordinator.policy_hash(source)]
        require(len(matches) == 1, 'receipt source policy not approved or ambiguous')
        selected = matches[0]
        pins = selected['runtime']
        require(set(pins) == set(RUNTIME_PATHS), 'receipt current runtime closure differs')
    else:
        revisions = trust['legacy_revisions'] if trust is not None else policy['receipts']['trusted_revisions']
        pins = revisions.get(run['head_sha'], {})
        require(set(pins) == set(RUNTIME_PATHS), 'receipt source revision not approved')
    for path in RUNTIME_PATHS:
        require(observed[path] == pins[path], 'receipt producer source changed')
    require(source.get('repository') == repo and source.get('base_branch') == policy['base_branch'] and source.get('receipts', {}).get('workflow_id') == policy['receipts']['workflow_id'], 'receipt source policy identity differs')
    return source, observed, trust, selected


def authenticate(api, policy, run_id, *, historical=False, trust_path=None, trust_mode='legacy'):
    require(type(run_id) is int and run_id > 0 and api.repo == policy['repository'], 'invalid receipt source')
    repo = policy['repository']; root = f'repos/{repo}'
    require(type(policy['receipts']['workflow_id']) is int and policy['receipts']['workflow_id'] > 0, 'receipt workflow not configured')
    run = api.get(f'{root}/actions/runs/{run_id}')
    require(type(run['id']) is int and run['id'] == run_id and type(run['run_attempt']) is int and run['run_attempt'] > 0, 'wrong run identity')
    require(run['repository']['full_name'] == repo and type(run['workflow_id']) is int and run['workflow_id'] == policy['receipts']['workflow_id'], 'foreign receipt producer')
    require(run['event'] in {'workflow_run', 'workflow_dispatch'} and run['head_branch'] == policy['base_branch'], 'unprotected receipt event/branch')
    require(run['status'] == 'completed' and run['conclusion'] == 'success', 'coordinator did not succeed')
    require(run.get('path') == RUNTIME_PATHS[0], 'receipt workflow path differs')
    require(coordinator.contract.digest(run.get('head_sha'), 40), 'receipt source SHA invalid')
    source, observed, trust, selected = authenticate_source(api, policy, run, trust_path=trust_path, trust_mode=trust_mode)
    document, artifact = receipt_artifact(api, run)
    expected = {'schema_version', 'repository', 'pull_request', 'head_sha', 'base_sha', 'spec', 'spec_sha256',
                'policy_sha256', 'verifier_run', 'reviewer_run', 'eligible', 'merged', 'merge_sha', 'task_ids'}
    registration = source.get('specs', {}).get(document.get('spec'), {}).get('review_adapter')
    if registration is not None:
        expected.add('review_adapter')
        canonical = lambda value: json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
        binding = {'kind':'registered-woff2-v1', 'registration_sha256':hashlib.sha256(canonical(registration)).hexdigest(),
                   'asset_manifest_sha256':hashlib.sha256(canonical({'head_sha':document.get('head_sha'),'assets':registration['assets']})).hexdigest()}
        require(document.get('review_adapter') == binding, 'receipt font adapter/asset binding differs')
    require(set(document) == expected and document['schema_version'] == 1, 'malformed delivery receipt')
    require(source.get('enabled') is True and source.get('merge_enabled') is True, 'receipt policy did not authorize merge')
    require(document['repository'] == repo == source['repository'] and document['eligible'] is True and document['merged'] is True, 'receipt is not a factory delivery')
    require(type(document['pull_request']) is int and document['pull_request'] > 0, 'invalid receipt PR')
    for name in ('head_sha', 'base_sha', 'merge_sha'):
        require(coordinator.contract.digest(document[name], 40), 'invalid candidate digest')
    require(all(type(document[k]) is int and document[k] > 0 for k in ('verifier_run', 'reviewer_run')) and document['verifier_run'] != document['reviewer_run'], 'missing independent proof identity')
    require(document['policy_sha256'] == coordinator.policy_hash(source), 'receipt policy differs')
    approved = source['specs'][document['spec']]
    current = approved if historical else policy['specs'][document['spec']]
    require(document['spec_sha256'] == approved['sha256'] == current['sha256'], 'superseded spec receipt')
    require(hashlib.sha256(api.source(approved['path'], run['head_sha'])).hexdigest() == document['spec_sha256'], 'receipt spec bytes differ')
    # Multiple task deliveries need explicit per-task acceptance mapping; never infer all spec tasks.
    tasks = document['task_ids']
    require(isinstance(tasks, list) and len(tasks) == 1 and tasks == approved.get('task_ids') == current.get('task_ids'), 'unapproved/ambiguous task delivery mapping')
    require(all(isinstance(t, str) and re.fullmatch(r'T-[1-9][0-9]*', t) for t in tasks), 'invalid delivery task')
    pr = api.get(f'{root}/pulls/{document["pull_request"]}')
    require(pr['number'] == document['pull_request'] and pr['merged'] is True and pr['merge_commit_sha'] == document['merge_sha'], 'actual PR merge differs')
    require(pr['head']['sha'] == document['head_sha'] and pr['head']['repo']['full_name'] == repo, 'actual candidate differs')
    require(pr['base']['repo']['full_name'] == repo and pr['base']['ref'] == policy['base_branch'] == source['base_branch'], 'actual merge target differs')
    delivery = {'repository': repo, 'pr': document['pull_request'], 'merge_sha': document['merge_sha']}
    encoded = json.dumps(delivery, sort_keys=True)
    provenance_facts = {'run_id': run_id, 'attempt': run['run_attempt'], 'workflow_id': run['workflow_id'],
                        'source_sha': run['head_sha'], 'artifact_id': artifact['id'], 'artifact_digest': artifact['digest'],
                        'receipt': document}
    if trust is not None:
        provenance_facts['execution'] = {'repository_id': run['repository']['id'], 'repository': repo, 'event': run['event'], 'branch': run['head_branch'], 'path': run['path'], 'status': run['status'], 'conclusion': run['conclusion']}
        provenance_facts['trust'] = {'mode': trust_mode, 'profile_id': selected['id'] if selected else None,
                                     'document_sha256': coordinator.policy_hash(trust),
                                     'policy_sha256': coordinator.policy_hash(source), 'runtime': observed}
    provenance = json.dumps(provenance_facts, sort_keys=True)
    return {'tasks': tasks, 'revision': document['spec_sha256'], 'delivery': encoded,
            'provenance': provenance, 'run_id': run_id, 'merge_sha': document['merge_sha']}


def annotate_reported_trust(proof, trust_path, repository):
    """Label an already-authenticated retained fact; never authenticate copied JSON.

    Archive integration must establish the protected origin of proof before this
    reporting-only annotation. It cannot grant runtime credit or rewrite facts.
    """
    trust = load_receipt_trust(trust_path, repository, mode='report')
    facts = json.loads(proof['provenance'])['trust']
    equivalent = [profile for profile in trust['profiles'] if profile['policy_sha256'] == facts['policy_sha256'] and profile['runtime'] == facts['runtime']]
    revoked = any(profile['status'] == 'revoked' for profile in equivalent)
    if facts['mode'] == 'profile':
        approved = any(profile['id'] == facts['profile_id'] and profile['status'] == 'active' for profile in equivalent)
    else:
        source = json.loads(proof['provenance'])['source_sha']
        approved = trust['legacy_revisions'].get(source) == facts['runtime']
    return dict(proof, trust_status='active' if approved and not revoked else 'withdrawn')


def ingest(api, policy, db_path, run_id, *, trust_path=None, trust_mode='legacy'):
    proof = authenticate(api, policy, run_id, trust_path=trust_path, trust_mode=trust_mode)
    tasks = proof['tasks']; encoded = proof['delivery']; provenance = proof['provenance']
    store = ledger.runtime.Store(db_path)
    with store.transaction() as db:
        db.execute('CREATE TABLE IF NOT EXISTS delivery_receipts(task TEXT PRIMARY KEY, revision TEXT NOT NULL, receipt TEXT NOT NULL)')
        db.execute('CREATE TABLE IF NOT EXISTS delivery_provenance(task TEXT PRIMARY KEY, provenance TEXT NOT NULL)')
        for task in tasks:
            row = store.row(db, task)
            require(row['revision'] == proof['revision'] and row['state'] != 'cancelled', 'runtime task authority differs')
            previous = db.execute('SELECT * FROM delivery_receipts WHERE task=?', (task,)).fetchone()
            old_proof = db.execute('SELECT * FROM delivery_provenance WHERE task=?', (task,)).fetchone()
            require(previous is None or (previous['revision'] == row['revision'] and previous['receipt'] == encoded and old_proof is not None and old_proof['provenance'] == provenance), 'conflicting delivery/provenance')
            db.execute('INSERT OR IGNORE INTO delivery_receipts VALUES(?,?,?)', (task, row['revision'], encoded))
            db.execute('INSERT OR IGNORE INTO delivery_provenance VALUES(?,?)', (task, provenance))
            if row['state'] != 'merged':
                db.execute("UPDATE tasks SET state='merged',owner=NULL,expires=NULL,fence=fence+1 WHERE id=?", (task,))
    return {'completed_tasks': tasks, 'run_id': run_id, 'merge_sha': proof['merge_sha']}


def project(api, policy, db_path, *, receipt_mode='legacy', state_api=None, archive_config=None, selection=None):
    """Rebuild reporting-only proof tables; never create or transition runtime tasks."""
    require(type(receipt_mode) is str and receipt_mode in ('legacy', 'durable'), 'explicit reporting receipt mode required')
    if receipt_mode == 'durable':
        require(state_api is not None and type(archive_config) is dict and
                set(archive_config)=={'approval_path','trust_path','store','trust_mode'} and
                type(selection) is dict and set(selection)=={'interval_end','history_head','campaign'},
                'protected durable reporting selection required')
        spec = importlib.util.spec_from_file_location('durable_reporting_receipts', Path(__file__).with_name('factory-reporting-receipts.py'))
        retained = importlib.util.module_from_spec(spec); spec.loader.exec_module(retained)
        try:
            return retained.project_reporting(api, state_api, policy, db_path, archive_config['trust_path'],
                        archive_config['store'], archive_config['approval_path'], retained.archive.archive_stream(api.repo),
                        interval_end=selection['interval_end'], history_head=selection['history_head'],
                        campaign=selection['campaign'], interval_scoped=True)
        except retained.ProjectionPending:
            return {'coverage_complete':False,'all_history_complete':False,'task_credit':False,
                    'gaps':['retained-reporting-projection-pending']}
    require(api.repo == policy['repository'], 'foreign reporting receipt policy')
    configured = policy['receipts']
    workflow = configured['workflow_id']
    if workflow is None:
        require(configured['trusted_revisions'] == {}, 'receipt workflow missing for approved revisions')
        proofs = []
    else:
        require(type(workflow) is int and workflow > 0, 'receipt workflow not configured')
        pages = api.request(f'repos/{api.repo}/actions/workflows/{workflow}/runs?status=success&per_page=100', paginate=True)
        require(isinstance(pages, list), 'receipt run pages malformed')
        runs = [run for page in pages for run in page['workflow_runs']]
        require(len(runs) <= 1000, 'receipt history exceeds projection bound')
        require(len({run['id'] for run in runs}) == len(runs), 'duplicate receipt run identity')
        proofs = []
        for run in runs:
            if run['head_sha'] not in configured['trusted_revisions']:
                continue  # Unapproved sources can never become authenticated evidence.
            # A successful coordinator may deliberately decline a merge. Its artifact
            # is inspected as data only; only true delivery claims enter authentication.
            document, _ = receipt_artifact(api, run)
            require(type(document.get('merged')) is bool, 'receipt delivery outcome missing')
            if document['merged']:
                proofs.append(authenticate(api, policy, run['id'], historical=True))
    # Validate the entire observation before atomically replacing the ephemeral tables.
    by_task = {}
    for proof in proofs:
        for task in proof['tasks']:
            require(task not in by_task or by_task[task] == proof, 'conflicting reporting delivery proof')
            by_task[task] = proof
    with sqlite3.connect(db_path) as db:
        db.execute('CREATE TABLE IF NOT EXISTS delivery_receipts(task TEXT PRIMARY KEY, revision TEXT NOT NULL, receipt TEXT NOT NULL)')
        db.execute('CREATE TABLE IF NOT EXISTS delivery_provenance(task TEXT PRIMARY KEY, provenance TEXT NOT NULL)')
        db.execute('DELETE FROM delivery_receipts')
        db.execute('DELETE FROM delivery_provenance')
        for task, proof in sorted(by_task.items()):
            db.execute('INSERT INTO delivery_receipts VALUES(?,?,?)', (task, proof['revision'], proof['delivery']))
            db.execute('INSERT INTO delivery_provenance VALUES(?,?)', (task, proof['provenance']))
    return len(by_task)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--db', required=True)
    parser.add_argument('--run-id', type=int, required=True)
    args = parser.parse_args()
    policy = coordinator.contract.load(args.policy)
    print(json.dumps(ingest(coordinator.GitHub(policy['repository']), policy, args.db, args.run_id)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
