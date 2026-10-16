#!/usr/bin/env python3
"""Protected discovery checkpoints; pending observations never prove delivery or completeness."""
import base64
import hashlib
import importlib.util
from pathlib import Path
import uuid
from urllib.parse import quote

spec = importlib.util.spec_from_file_location('archive', Path(__file__).with_name('factory-receipt-archive.py'))
archive = importlib.util.module_from_spec(spec); spec.loader.exec_module(archive)
require = archive.require


def binding(anchor):
    return {key: value for key, value in anchor.items() if key not in ('head', 'tree')}


def validate_checkpoint(value, anchor, workflow, page_size):
    old_keys = {'schema_version', 'stream', 'binding', 'anchor', 'scan', 'pagination', 'watch', 'coverage_complete'}
    if isinstance(value, dict) and type(value.get('schema_version')) is int and value.get('schema_version') == 1 and set(value) == old_keys:
        value = dict(value, schema_version=2, review={'segment': 0, 'row': 0})
    if isinstance(value, dict) and type(value.get('schema_version')) is int and value['schema_version'] == 2 and set(value) == old_keys | {'review'}:
        value = dict(value, schema_version=3, pagination=dict(value['pagination'], overlap_page=1, overlap_until=max(1, value['pagination']['next_page']-1)))
    require(isinstance(value, dict) and set(value) == old_keys | {'review'}, 'discovery checkpoint schema differs')
    require(type(value['schema_version']) is int and value['schema_version'] == 3 and value['stream'] == archive.archive_stream(anchor['repository']) and value['binding'] == binding(anchor) and value['coverage_complete'] is False, 'discovery checkpoint binding/completeness differs')
    require(isinstance(value['anchor'], dict) and set(value['anchor']) == {'head', 'tree'} and all(archive.state_paths.valid_hash(value['anchor'][k], 40) for k in ('head', 'tree')), 'discovery verified anchor differs')
    scan = value['scan']
    require(isinstance(scan, dict) and set(scan) == {'head', 'tree', 'cursor', 'complete'} and all(archive.state_paths.valid_hash(scan[k], 40) for k in ('head', 'tree')) and type(scan['complete']) is bool, 'discovery frozen scan differs')
    require((scan['cursor'] is None) == scan['complete'], 'discovery partial scan cannot claim complete')
    if scan['cursor'] is not None:
        require(isinstance(scan['cursor'], dict) and set(scan['cursor']) == {'root', 'pending'} and scan['cursor']['root'] == scan['tree'] and isinstance(scan['cursor']['pending'], list) and 0 < len(scan['cursor']['pending']) <= 4096, 'discovery frozen cursor differs')
    pagination = value['pagination']
    require(isinstance(pagination, dict) and set(pagination) == {'workflow_id', 'page_size', 'next_page', 'overlap_page', 'overlap_until'} and type(pagination['workflow_id']) is int and pagination['workflow_id'] == workflow and type(pagination['page_size']) is int and pagination['page_size'] == page_size and type(pagination['next_page']) is int and 0 < pagination['next_page'] <= 10**9, 'discovery pagination identity differs')
    require(all(type(pagination[k]) is int for k in ('overlap_page', 'overlap_until')) and 0 < pagination['overlap_page'] <= pagination['overlap_until'] <= max(1, pagination['next_page']-1), 'discovery frozen overlap cursor differs')
    watch = value['watch']
    require(isinstance(watch, dict) and set(watch) == {'segments', 'count'} and all(type(watch[k]) is int and 0 <= watch[k] < 10**12 for k in ('segments', 'count')) and watch['segments'] <= watch['count'] <= watch['segments']*128, 'discovery watch manifest differs')
    cursor = value['review']
    require(isinstance(cursor, dict) and set(cursor) == {'segment', 'row'} and all(type(cursor[k]) is int and cursor[k] >= 0 for k in cursor) and (cursor == {'segment': 0, 'row': 0} if watch['segments'] == 0 else cursor['segment'] < watch['segments'] and cursor['row'] < 128), 'discovery cold watch cursor differs')
    return value



def validate_watch(value, repository, stream, number):
    require(isinstance(value, dict) and set(value) == {'schema_version', 'repository', 'stream', 'number', 'rows'} and type(value['schema_version']) is int and value['schema_version'] == 1 and value['repository'] == repository and value['stream'] == stream and type(value['number']) is int and value['number'] == number, 'discovery watch segment identity differs')
    require(isinstance(value['rows'], list) and 0 < len(value['rows']) <= 128, 'discovery watch segment invocation bound exceeded')
    seen = set()
    for row in value['rows']:
        require(isinstance(row, dict) and set(row) == {'run_id', 'attempt', 'source_sha', 'classification'} and all(type(row[k]) is int and row[k] > 0 for k in ('run_id', 'attempt')) and archive.state_paths.valid_hash(row['source_sha'], 40) and row['classification'] == 'pending', 'discovery pending identity/classification differs')
        key = (row['run_id'], row['attempt']); require(key not in seen, 'discovery duplicate pending identity'); seen.add(key)
    return value


def watch_identity(repository, stream, run_id, attempt):
    return archive.digest(archive.canonical([repository, stream, run_id, attempt]))


def run_identity(run, anchor, policy):
    require(isinstance(run, dict) and type(run.get('repository', {}).get('id')) is int and run['repository']['id'] == anchor['repository_id'] and run['repository'].get('full_name') == anchor['repository'] and type(run.get('workflow_id')) is int and run['workflow_id'] == policy['receipts']['workflow_id'] and run.get('path') == archive.receipts.RUNTIME_PATHS[0] and run.get('event') in ('workflow_run', 'workflow_dispatch') and run.get('head_branch') == policy['base_branch'] and all(type(run.get(k)) is int and run[k] > 0 for k in ('id', 'run_attempt')) and archive.state_paths.valid_hash(run.get('head_sha'), 40), 'discovery run identity differs')
    return run


def source_fact(api, policy, run, trust_path, trust_mode):
    source, observed, trust, selected = archive.receipts.authenticate_source(api, policy, run, trust_path=trust_path, trust_mode=trust_mode)
    material = {name: base64.b64encode(api.source(name, run['head_sha'])).decode() for name in ('factory/policy.json', *archive.receipts.RUNTIME_PATHS)}
    fact = {'mode': trust_mode, 'profile_id': selected['id'] if selected else None, 'document_sha256': archive.receipts.coordinator.policy_hash(trust), 'materials': material, 'receipt': None}
    validate_source_fact(fact, policy, run['head_sha'], trust_path, trust_mode)
    return source, fact


def validate_source_fact(fact, policy, sha, trust_path, trust_mode):
    require(isinstance(fact, dict) and set(fact) == {'mode', 'profile_id', 'document_sha256', 'materials', 'receipt'} and fact['mode'] == trust_mode, 'outcome source schema differs')
    trust = archive.receipts.load_receipt_trust(trust_path, policy['repository'], mode='report')
    require(fact['document_sha256'] == archive.receipts.coordinator.policy_hash(trust), 'outcome source trust epoch differs')
    require(isinstance(fact['materials'], dict) and set(fact['materials']) == {'factory/policy.json', *archive.receipts.RUNTIME_PATHS}, 'outcome source closure differs')
    material = {key: archive.decode(value) for key, value in fact['materials'].items()}
    source = archive.document(material['factory/policy.json']); observed = {key: archive.digest(material[key]) for key in archive.receipts.RUNTIME_PATHS}
    require(source.get('repository') == policy['repository'] and source.get('base_branch') == policy['base_branch'] and source.get('receipts', {}).get('workflow_id') == policy['receipts']['workflow_id'], 'outcome source identity differs')
    matching = [p for p in trust['profiles'] if p['policy_sha256'] == archive.receipts.coordinator.policy_hash(source) and p['runtime'] == observed]
    require(not any(p['status'] == 'revoked' for p in matching), 'outcome source revoked')
    if trust_mode == 'profile':
        require(sum(p['id'] == fact['profile_id'] and p['status'] == 'active' for p in matching) == 1, 'outcome source not approved')
    else:
        require(trust_mode == 'legacy' and fact['profile_id'] is None and trust['legacy_revisions'].get(sha) == observed, 'outcome source revision not approved')
    return source



def validate_shadow(fact, source, row, anchor):
    import io
    import zipfile
    capsule = fact['receipt']
    require(isinstance(capsule, dict) and set(capsule) == {'zip', 'artifact'}, 'shadow receipt capsule differs')
    artifact = capsule['artifact']; blob = archive.decode(capsule['zip'])
    require(isinstance(artifact, dict) and set(artifact) == {'id', 'name', 'digest', 'workflow_run'} and type(artifact['id']) is int and artifact['id'] > 0 and artifact['name'] == f'factory-receipt-{row["run_id"]}-{row["attempt"]}' and artifact['digest'] == 'sha256:'+archive.digest(blob) and artifact['workflow_run'] == {'id': row['run_id'], 'repository_id': anchor['repository_id'], 'head_repository_id': anchor['repository_id'], 'head_sha': row['source_sha']}, 'shadow artifact identity differs')
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        require(z.namelist() == ['receipt.json'] and 0 < z.infolist()[0].file_size <= 256000, 'shadow receipt ZIP differs')
        receipt = archive.document(z.read('receipt.json'))
    fields = {'schema_version', 'repository', 'pull_request', 'head_sha', 'base_sha', 'spec', 'spec_sha256', 'policy_sha256', 'verifier_run', 'reviewer_run', 'eligible', 'merged'}
    require(isinstance(receipt, dict) and set(receipt) == fields and type(receipt['schema_version']) is int and receipt['schema_version'] == 1 and receipt['repository'] == anchor['repository'] and source.get('enabled') is True and source.get('merge_enabled') is True and receipt['eligible'] is True and receipt['merged'] is False and receipt['policy_sha256'] == archive.receipts.coordinator.policy_hash(source), 'shadow receipt policy/outcome differs')
    require(all(type(receipt[k]) is int and receipt[k] > 0 for k in ('pull_request', 'verifier_run', 'reviewer_run')) and receipt['verifier_run'] != receipt['reviewer_run'] and all(archive.state_paths.valid_hash(receipt[k], 40) for k in ('head_sha', 'base_sha')) and source['specs'][receipt['spec']]['sha256'] == receipt['spec_sha256'], 'shadow receipt candidate/spec differs')
    return receipt

def outcome_path(repository, stream, row, epoch):
    key = archive.digest(archive.canonical([repository, stream, row['run_id'], row['attempt'], epoch]))
    return f'receipt-archive/outcomes/{stream}/{key[:2]}/{key}.json'


def validate_outcome(value, repository, stream, row, epoch):
    require(isinstance(value, dict) and set(value) == {'schema_version', 'repository', 'stream', 'run_id', 'attempt', 'source_sha', 'trust_epoch', 'classification', 'reason', 'source', 'record_sha256', 'trust_status'} and type(value['schema_version']) is int and value['schema_version'] == 1 and value['repository'] == repository and value['stream'] == stream and all(type(value[k]) is int and value[k] == row[k] for k in ('run_id', 'attempt')) and value['source_sha'] == row['source_sha'] and value['trust_epoch'] == epoch, 'outcome identity/epoch differs')
    require(value['classification'] in ('watch', 'unapproved', 'non-delivery', 'retained-delivery') and value['reason'] in ('run-not-successful', 'unavailable', 'proof-unavailable', 'source-unapproved', 'source-merge-disabled', 'authenticated-shadow', 'retained-proof'), 'outcome classification differs')
    if value['classification'] == 'retained-delivery':
        require(archive.state_paths.valid_hash(value['record_sha256'], 64) and value['source'] is None and value['trust_status'] in ('active', 'withdrawn'), 'outcome retained proof differs')
    else:
        require(value['record_sha256'] is None and value['trust_status'] is None, 'outcome cannot claim retained delivery')
        require((value['source'] is not None) == (value['classification'] == 'non-delivery'), 'outcome source proof missing or unexpected')
    return value


class ArchiveAdvanced(Exception):
    pass


def assess(source_api, api, anchor, policy, trust_path, trust_mode, store, stream, row, epoch, blob_at, approval_path):
    # This lookup precedes all source artifact accesses, including on expired runs.
    retained = archive.retained_execution(api, anchor, store, stream, row['run_id'], row['attempt'])
    value = dict(schema_version=1, repository=api.repo, stream=stream, run_id=row['run_id'], attempt=row['attempt'], source_sha=row['source_sha'], trust_epoch=epoch, classification='watch', reason='run-not-successful', source=None, record_sha256=None, trust_status=None)
    if retained is not None:
        require(retained['record']['run']['source_sha'] == row['source_sha'], 'retained watched source differs')
        proof = archive.receipts.annotate_reported_trust(retained['record']['proof'], trust_path, api.repo)
        value.update(classification='retained-delivery', reason='retained-proof', record_sha256=retained['record_sha256'], trust_status=proof['trust_status'])
    cached_raw = blob_at(anchor['tree'], outcome_path(api.repo, stream, row, epoch))
    if cached_raw is not None and retained is None:
        require(blob_at(anchor['bootstrap_tree'], outcome_path(api.repo, stream, row, epoch)) is None, 'outcome pre-bootstrap capsule requires explicit reviewed import')
        cached = validate_outcome(archive.document(cached_raw), api.repo, stream, row, epoch)
        if cached['classification'] == 'non-delivery':
            source = validate_source_fact(cached['source'], policy, row['source_sha'], trust_path, trust_mode)
            if cached['reason'] == 'source-merge-disabled':
                require(source.get('merge_enabled') is False and cached['source']['receipt'] is None, 'cached source cannot prove non-delivery')
            else:
                require(cached['reason'] == 'authenticated-shadow', 'cached shadow reason differs')
                validate_shadow(cached['source'], source, row, anchor)
            value = cached
    latest = None
    try:
        latest = run_identity(source_api.get(f'repos/{api.repo}/actions/runs/{row["run_id"]}'), anchor, policy)
    except (RuntimeError, OSError):
        if value['classification'] == 'watch':value['reason'] = 'unavailable'
        return value, None
    except ValueError as error:
        if not str(error).startswith('GitHub API request failed:'):raise
        if value['classification'] == 'watch':value['reason'] = 'unavailable'
        return value, None
    require(latest['id'] == row['run_id'] and latest['head_sha'] == row['source_sha'] and latest['run_attempt'] >= row['attempt'], 'watched run immutable identity changed')
    if retained is not None or value['classification'] == 'non-delivery':
        return value, latest
    try:
        run = latest if latest['run_attempt'] == row['attempt'] else run_identity(source_api.get(f'repos/{api.repo}/actions/runs/{row["run_id"]}/attempts/{row["attempt"]}'), anchor, policy)
        require((run['id'], run['run_attempt'], run['head_sha']) == (row['run_id'], row['attempt'], row['source_sha']), 'watched attempt identity changed')
        source, fact = source_fact(source_api, policy, run, trust_path, trust_mode)
    except (RuntimeError, OSError):
        value['reason'] = 'unavailable'; return value, latest
    except ValueError as error:
        if any(token in str(error) for token in ('not approved', 'not approved or ambiguous', 'source changed', 'revoked')):
            value.update(classification='unapproved', reason='source-unapproved'); return value, latest
        raise
    if source.get('merge_enabled') is False:
        value.update(classification='non-delivery', reason='source-merge-disabled', source=fact)
        return value, latest
    if run['status'] != 'completed' or run['conclusion'] != 'success':
        return value, latest  # Failed/skipped/running merge-capable attempts remain cold-watchable.
    class AttemptView:
        repo = source_api.repo
        def get(self, path):
            return run if path == f'repos/{self.repo}/actions/runs/{row["run_id"]}' else source_api.get(path)
        source = staticmethod(source_api.source)
        request = staticmethod(source_api.request)
    try:
        document, artifact, blob = archive.receipts.receipt_artifact(AttemptView(), run, retain_blob=True)
        if document.get('merged') is False:
            fact['receipt'] = {'zip': base64.b64encode(blob).decode(), 'artifact': dict({k: artifact[k] for k in ('id', 'name', 'digest')}, workflow_run={k: artifact['workflow_run'][k] for k in ('id', 'repository_id', 'head_repository_id', 'head_sha')})}
            validate_shadow(fact, source, row, anchor)
            value.update(classification='non-delivery', reason='authenticated-shadow', source=fact)
            return value, latest
        archive.append_delivery(AttemptView(), api, policy, row['run_id'], trust_path, store, approval_path, stream, trust_mode=trust_mode)
    except (RuntimeError, OSError):
        value['reason'] = 'unavailable'; return value, latest
    except ValueError:
        value['reason'] = 'proof-unavailable'; return value, latest
    raise ArchiveAdvanced()  # Re-read the actual archive head, then use its retained index first.


def _checkpoint(source_api, state_api, policy, approval_path, stream, *, page_size=10, tree_pages=1, review_rows=4, mode='discover', trust_path=None, trust_mode='profile', store=None):
    """Read actual protected progress, advance one bounded page/scan and CAS atomically.

    Only checked scanner output is persisted. No caller checkpoint/cursor input is
    accepted. Full bootstrap verification remains mandatory until later anchor
    integration; a checkpoint's mere hash is never an origin grant.
    """
    require(source_api.repo == state_api.repo == policy['repository'] and stream == archive.archive_stream(state_api.repo), 'foreign discovery repository/stream')
    require(type(page_size) is int and 0 < page_size <= 100 and type(tree_pages) is int and 0 < tree_pages <= 10, 'discovery invocation budget invalid')
    require(mode in ('discover', 'review') and type(review_rows) is int and 0 < review_rows <= 16, 'discovery review budget invalid')
    if mode == 'review':
        require(trust_path is not None and trust_mode in ('profile', 'legacy') and store == {'repository': state_api.repo, 'visibility': 'private' if archive.document(Path(approval_path).read_bytes())['private'] else 'public'}, 'explicit reviewed reconciliation trust/store required')
        trust = archive.receipts.load_receipt_trust(trust_path, policy['repository'], mode='report')
        epoch = archive.digest(archive.canonical({'mode': trust_mode, 'document': trust}))
    workflow = policy['receipts']['workflow_id']; require(type(workflow) is int and workflow > 0, 'discovery workflow missing')
    root = 'repos/'+state_api.repo; path = f'receipt-archive/progress/{stream}.json'
    consumed = 0; calls = 0; cache = {}; attempted = None; attempted_changes = {}; uncertain = False

    def charge(value):
        nonlocal consumed
        size = len(value) if isinstance(value, bytes) else len(archive.canonical(value)); consumed += size
        require(size <= 2097152 and consumed <= 33554432, 'discovery observation budget exceeded; explicit coverage gap')
        return value

    class State:
        repo = state_api.repo

        def request(self, target, method='GET', payload=None):
            nonlocal calls
            require(target == root or target.startswith(root+'/'), 'foreign discovery state endpoint')
            require(method == 'GET' or (method == 'POST' and target in {root+'/git/blobs', root+'/git/trees', root+'/git/commits'}) or (method == 'PATCH' and target.startswith(root+'/git/refs/heads/')), 'discovery write endpoint not permitted')
            immutable = method == 'GET' and any(part in target for part in ('/git/trees/', '/git/blobs/', '/git/commits/'))
            if immutable and target in cache:
                return cache[target]
            require(calls < 4096, 'discovery invocation API call budget reached; explicit coverage gap')
            calls += 1
            try:
                result = charge(state_api.request(target, method=method, payload=payload))
            except Exception as error:
                if uncertain:
                    raise ValueError('discovery write uncertain; authoritative checkpoint unavailable') from error
                raise
            if immutable:
                cache[target] = result
            return result

    def source_read(fn, *args, **kwargs):
        nonlocal calls
        require(calls < 4096, 'reconciliation API call budget reached; explicit coverage gap')
        calls += 1
        return charge(fn(*args, **kwargs))

    original_source = source_api
    class Source:
        repo = source_api.repo
        def get(self, target):
            require(target == root or target.startswith(root+'/'), 'foreign reconciliation source endpoint')
            return source_read(original_source.get, target)
        def source(self, name, sha):
            return source_read(original_source.source, name, sha)
        def request(self, target, **kwargs):
            require(kwargs.get('method', 'GET') == 'GET' and target.startswith(root+'/'), 'reconciliation source must be read-only')
            return source_read(original_source.request, target, **kwargs)
    source_api = Source()
    api = State()
    for retry in range(3):
        anchor = archive.verify_bootstrap(api, approval_path)
        _, blob_at = archive.fixed_reader(api, root)
        require(blob_at(anchor['bootstrap_tree'], path) is None, 'discovery pre-bootstrap checkpoint requires explicit reviewed import')
        raw = blob_at(anchor['tree'], path)
        if attempted is not None and raw == attempted:
            require(all(blob_at(anchor['tree'], name) == data for name, data in attempted_changes.items()), 'discovery reconciled checkpoint material differs')
            return {'status': 'checkpointed', 'head': anchor['head'], 'complete': False, 'reconciled': True}
        if raw is None:
            require(mode == 'discover', 'protected discovery checkpoint missing before reconciliation')
            progress = {'schema_version': 3, 'stream': stream, 'binding': binding(anchor), 'anchor': {'head': anchor['head'], 'tree': anchor['tree']},
                        'scan': {'head': anchor['head'], 'tree': anchor['tree'], 'cursor': None, 'complete': True},
                        'pagination': {'workflow_id': workflow, 'page_size': page_size, 'next_page': 1, 'overlap_page': 1, 'overlap_until': 1}, 'watch': {'segments': 0, 'count': 0}, 'review': {'segment': 0, 'row': 0}, 'coverage_complete': False}
            cursor = None
        else:
            if mode == 'review':
                page_size = archive.document(raw)['pagination']['page_size']
            progress = validate_checkpoint(archive.document(raw), anchor, workflow, page_size)
            frozen = api.request(root+'/git/commits/'+progress['scan']['head'])
            require(frozen.get('sha') == progress['scan']['head'] and frozen['tree']['sha'] == progress['scan']['tree'], 'discovery frozen commit/tree differs')
            # The saved checkpoint was read from the authenticated protected chain;
            # verify its previously observed anchor is actually on that same chain.
            require(progress['anchor']['head'] != progress['scan']['head'] or progress['anchor']['tree'] == progress['scan']['tree'], 'discovery saved anchor/frozen tree differs')
            required = {progress['anchor']['head']: progress['anchor']['tree'], progress['scan']['head']: progress['scan']['tree']}
            sha = anchor['head']
            for _ in range(256):
                commit = api.request(root+'/git/commits/'+sha)
                if sha in required:
                    require(commit['tree']['sha'] == required.pop(sha), 'discovery retained anchor tree differs')
                if not required:
                    break
                require(len(commit['parents']) == 1, 'discovery retained anchor not on protected chain')
                sha = commit['parents'][0]['sha']
            else:
                raise ValueError('discovery anchor invocation bound reached; verified continuation required')
            cursor = progress['scan']['cursor']
        if raw is None or not progress['scan']['complete']:
            scan = archive.state_paths.scan_tree(api, root, progress['scan']['tree'], cursor=cursor, page_budget=tree_pages)
            progress['scan'].update(cursor=scan['cursor'], complete=scan['complete'])
        page = progress['pagination']['next_page']; changes = {}
        if mode == 'discover':
            target = f'{root}/actions/workflows/{workflow}/runs?per_page={page_size}&page={page}'
            response = charge(source_api.request(target))
            pages = [response]
            if page > 1:
                overlap = progress['pagination']['overlap_page']
                pages.append(source_api.request(f'{root}/actions/workflows/{workflow}/runs?per_page={page_size}&page={overlap}'))
                if overlap == progress['pagination']['overlap_until']:
                    progress['pagination'].update(overlap_page=1, overlap_until=max(1, page-1))
                else:
                    progress['pagination']['overlap_page'] = overlap+1
            merged = {}
            for observed_page in pages:
                require(isinstance(observed_page, dict) and isinstance(observed_page.get('workflow_runs'), list) and len(observed_page['workflow_runs']) <= page_size, 'discovery run page malformed')
                seen = set()
                for run in observed_page['workflow_runs']:
                    run_identity(run, anchor, policy); key = (run['id'], run['run_attempt'])
                    require(key not in seen, 'discovery duplicate page identity'); seen.add(key)
                    require(key not in merged or merged[key]['head_sha'] == run['head_sha'], 'discovery overlap immutable identity changed')
                    merged[key] = run
            response = {'workflow_runs': list(merged.values())}
        else:
            if progress['watch']['segments'] == 0:
                return {'status': 'idle', 'head': anchor['head'], 'complete': False}
            cursor = progress['review']; number = cursor['segment']
            segment_raw = blob_at(anchor['tree'], archive.state_paths.pending_segment_path(stream, number))
            require(segment_raw is not None, 'cold watch segment missing')
            segment = validate_watch(archive.document(segment_raw), api.repo, stream, number)
            require(cursor['row'] < len(segment['rows']), 'cold watch row missing')
            selected = segment['rows'][cursor['row']:cursor['row']+review_rows]; latest = {}
            try:
                for row in selected:
                    outcome, observed = assess(source_api, api, anchor, policy, trust_path, trust_mode, store, stream, row, epoch, blob_at, approval_path)
                    validate_outcome(outcome, api.repo, stream, row, epoch)
                    changes[outcome_path(api.repo, stream, row, epoch)] = archive.canonical(outcome)
                    if observed is not None:latest[(observed['id'], observed['run_attempt'])] = observed
            except ArchiveAdvanced:
                continue  # Actual retained append survived independently; resume index-first.
            position = cursor['row']+len(selected)
            progress['review'] = {'segment': number, 'row': position} if position < len(segment['rows']) else {'segment': (number+1) % progress['watch']['segments'], 'row': 0}
            response = {'workflow_runs': list(latest.values())}
        new_rows = []; page_seen = set()
        for run in response['workflow_runs']:
            run_identity(run, anchor, policy)
            key = (run['id'], run['run_attempt']); require(key not in page_seen, 'discovery duplicate page identity'); page_seen.add(key)
            row = {'run_id': run['id'], 'attempt': run['run_attempt'], 'source_sha': run['head_sha'], 'classification': 'pending'}
            identity = watch_identity(state_api.repo, stream, *key)
            lookup_path = f'receipt-archive/pending/{stream}/identities/{identity[:2]}/{identity}.json'
            old_raw = blob_at(anchor['tree'], lookup_path)
            if old_raw is not None:
                old = archive.document(old_raw)
                require(isinstance(old, dict) and set(old) == {'schema_version', 'repository', 'stream', 'run_id', 'attempt', 'source_sha', 'segment'} and type(old['schema_version']) is int and old['schema_version'] == 1 and old['repository'] == state_api.repo and old['stream'] == stream and all(type(old[k]) is int and old[k] > 0 for k in ('run_id', 'attempt')) and old['run_id'] == row['run_id'] and old['attempt'] == row['attempt'] and old['source_sha'] == row['source_sha'] and type(old['segment']) is int and 0 <= old['segment'] < progress['watch']['segments'], 'discovery immutable pending identity changed')
                retained_raw = blob_at(anchor['tree'], archive.state_paths.pending_segment_path(stream, old['segment']))
                require(retained_raw is not None, 'discovery retained watch segment missing')
                retained = validate_watch(archive.document(retained_raw), state_api.repo, stream, old['segment'])
                require(sum(item == row for item in retained['rows']) == 1, 'discovery retained watch lookup differs')
            else:
                new_rows.append(row)
                changes[lookup_path] = archive.canonical({'schema_version': 1, 'repository': state_api.repo, 'stream': stream, 'run_id': row['run_id'], 'attempt': row['attempt'], 'source_sha': row['source_sha'], 'segment': progress['watch']['segments'] + (len(new_rows)-1)//128})
        for start in range(0, len(new_rows), 128):
            number = progress['watch']['segments']
            rows = new_rows[start:start+128]
            segment = validate_watch({'schema_version': 1, 'repository': state_api.repo, 'stream': stream, 'number': number, 'rows': rows}, state_api.repo, stream, number)
            segment_path = archive.state_paths.pending_segment_path(stream, number)
            require(blob_at(anchor['tree'], segment_path) is None, 'discovery conflicting occupied watch segment')
            changes[segment_path] = archive.canonical(segment)
            progress['watch']['segments'] += 1
            progress['watch']['count'] += len(rows)
        if mode == 'discover':progress['pagination']['next_page'] = page+1
        progress['anchor'] = {'head': anchor['head'], 'tree': anchor['tree']}
        validate_checkpoint(progress, anchor, workflow, page_size)
        # Even a short/empty API page is NOT complete history (filtered queries cap
        # at 1,000). Partition/reconciliation and outcome proofs are later stages.
        encoded = archive.canonical(progress); changes[path] = encoded
        prepared = []
        for name, data in changes.items():
            require(0 < len(data) <= archive.MAX_OBJECT, 'discovery encoded checkpoint exceeds bound')
            sha = hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
            archive.state_paths.validate_entry({'path': name, 'type': 'blob', 'mode': '100644', 'sha': sha, 'size': len(data)})
            prepared.append((name, data, sha))
        require(archive.verify_bootstrap(api, approval_path) == anchor, 'discovery state changed before checkpoint')
        entries = []
        for name, data, sha in prepared:
            uploaded = api.request(root+'/git/blobs', 'POST', {'encoding': 'base64', 'content': base64.b64encode(data).decode()})
            require(uploaded.get('sha') == sha, 'discovery uploaded checkpoint differs')
            entries.append({'path': name, 'type': 'blob', 'mode': '100644', 'sha': sha})
        tree = api.request(root+'/git/trees', 'POST', {'base_tree': anchor['tree'], 'tree': entries})
        require(archive.state_paths.valid_hash(tree.get('sha'), 40), 'discovery created tree invalid')
        commit = api.request(root+'/git/commits', 'POST', {'message': 'factory: discovery progress '+uuid.uuid4().hex, 'tree': tree['sha'], 'parents': [anchor['head']]})
        require(archive.state_paths.valid_hash(commit.get('sha'), 40) and commit['tree']['sha'] == tree['sha'] and [p['sha'] for p in commit['parents']] == [anchor['head']], 'discovery created commit differs')
        for identity, expected in anchor['policies'].items():
            require(archive.digest(archive.canonical(api.request(root+'/rulesets/'+identity))) == expected, 'discovery protection changed before checkpoint')
        attempted = encoded; attempted_changes = dict(changes)
        try:
            result = api.request(root+'/git/refs/heads/'+quote(anchor['branch'], safe=''), 'PATCH', {'sha': commit['sha'], 'force': False})
            require(result['ref'] == 'refs/heads/'+anchor['branch'] and result['object']['sha'] == commit['sha'], 'discovery reference acknowledgement differs')
        except Exception:
            uncertain = True
            continue
        return {'status': 'checkpointed', 'head': commit['sha'], 'complete': False, 'reconciled': False}
    raise ValueError('discovery checkpoint uncertain after three CAS observations; reconcile before progress' if uncertain else 'discovery work bound reached; resume protected progress')


def advance(source_api, state_api, policy, approval_path, stream, *, page_size=10, tree_pages=1):
    return _checkpoint(source_api, state_api, policy, approval_path, stream, page_size=page_size, tree_pages=tree_pages)


def reconcile(source_api, state_api, policy, trust_path, store, approval_path, stream, *, trust_mode='profile', review_rows=4):
    return _checkpoint(source_api, state_api, policy, approval_path, stream, mode='review', trust_path=trust_path, trust_mode=trust_mode, store=store, review_rows=review_rows)
