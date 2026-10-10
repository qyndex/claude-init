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
                 '.claude/scripts/factory-preflight.py', '.claude/scripts/validate-candidate-evidence.py')
require = coordinator.require


def receipt_artifact(api, run):
    name = f'factory-receipt-{run["id"]}-{run["run_attempt"]}'
    pages = api.request(f'repos/{api.repo}/actions/runs/{run["id"]}/artifacts', paginate=True)
    candidates = [a for page in pages for a in page['artifacts'] if a['name'] == name and not a['expired']]
    require(len(candidates) == 1, 'receipt artifact missing or ambiguous')
    artifact = candidates[0]
    require(0 < artifact['size_in_bytes'] <= 1_000_000, 'receipt archive too large')
    blob = api.request(f'repos/{api.repo}/actions/artifacts/{artifact["id"]}/zip', raw=True)
    require(len(blob) <= 1_000_000 and artifact.get('digest') == 'sha256:' + hashlib.sha256(blob).hexdigest(), 'receipt archive digest differs')
    with zipfile.ZipFile(io.BytesIO(blob)) as archive:
        require(archive.namelist() == ['receipt.json'], 'unexpected receipt archive entries')
        require(0 < archive.infolist()[0].file_size <= 256_000, 'receipt document too large')
        return json.loads(archive.read('receipt.json'), object_pairs_hook=coordinator.contract.no_duplicate_keys), artifact


def authenticate(api, policy, run_id, *, historical=False):
    require(type(run_id) is int and run_id > 0 and api.repo == policy['repository'], 'invalid receipt source')
    repo = policy['repository']; root = f'repos/{repo}'
    require(type(policy['receipts']['workflow_id']) is int and policy['receipts']['workflow_id'] > 0, 'receipt workflow not configured')
    run = api.get(f'{root}/actions/runs/{run_id}')
    require(run['id'] == run_id and type(run['run_attempt']) is int and run['run_attempt'] > 0, 'wrong run identity')
    require(run['repository']['full_name'] == repo and run['workflow_id'] == policy['receipts']['workflow_id'], 'foreign receipt producer')
    require(run['event'] in {'workflow_run', 'workflow_dispatch'} and run['head_branch'] == policy['base_branch'], 'unprotected receipt event/branch')
    require(run['status'] == 'completed' and run['conclusion'] == 'success', 'coordinator did not succeed')
    pins = policy['receipts']['trusted_revisions'].get(run['head_sha'], {})
    require(set(RUNTIME_PATHS) <= set(pins), 'receipt source revision not approved')
    for path in RUNTIME_PATHS:
        require(hashlib.sha256(api.source(path, run['head_sha'])).hexdigest() == pins[path], 'receipt producer source changed')
    source = json.loads(api.source('factory/policy.json', run['head_sha']), object_pairs_hook=coordinator.contract.no_duplicate_keys)
    document, artifact = receipt_artifact(api, run)
    expected = {'schema_version', 'repository', 'pull_request', 'head_sha', 'base_sha', 'spec', 'spec_sha256',
                'policy_sha256', 'verifier_run', 'reviewer_run', 'eligible', 'merged', 'merge_sha', 'task_ids'}
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
    provenance = json.dumps({'run_id': run_id, 'attempt': run['run_attempt'], 'workflow_id': run['workflow_id'],
                             'source_sha': run['head_sha'], 'artifact_id': artifact['id'], 'artifact_digest': artifact['digest'],
                             'receipt': document}, sort_keys=True)
    return {'tasks': tasks, 'revision': document['spec_sha256'], 'delivery': encoded,
            'provenance': provenance, 'run_id': run_id, 'merge_sha': document['merge_sha']}


def ingest(api, policy, db_path, run_id):
    proof = authenticate(api, policy, run_id)
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


def project(api, policy, db_path):
    """Rebuild reporting-only proof tables; never create or transition runtime tasks."""
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
