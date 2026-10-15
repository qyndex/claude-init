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
    require(isinstance(value, dict) and set(value) == {'schema_version', 'stream', 'binding', 'anchor', 'scan', 'pagination', 'watch', 'coverage_complete'}, 'discovery checkpoint schema differs')
    require(type(value['schema_version']) is int and value['schema_version'] == 1 and value['stream'] == archive.archive_stream(anchor['repository']) and value['binding'] == binding(anchor) and value['coverage_complete'] is False, 'discovery checkpoint binding/completeness differs')
    require(isinstance(value['anchor'], dict) and set(value['anchor']) == {'head', 'tree'} and all(archive.state_paths.valid_hash(value['anchor'][k], 40) for k in ('head', 'tree')), 'discovery verified anchor differs')
    scan = value['scan']
    require(isinstance(scan, dict) and set(scan) == {'head', 'tree', 'cursor', 'complete'} and all(archive.state_paths.valid_hash(scan[k], 40) for k in ('head', 'tree')) and type(scan['complete']) is bool, 'discovery frozen scan differs')
    require((scan['cursor'] is None) == scan['complete'], 'discovery partial scan cannot claim complete')
    if scan['cursor'] is not None:
        require(isinstance(scan['cursor'], dict) and set(scan['cursor']) == {'root', 'pending'} and scan['cursor']['root'] == scan['tree'] and isinstance(scan['cursor']['pending'], list) and 0 < len(scan['cursor']['pending']) <= 4096, 'discovery frozen cursor differs')
    pagination = value['pagination']
    require(isinstance(pagination, dict) and set(pagination) == {'workflow_id', 'page_size', 'next_page'} and type(pagination['workflow_id']) is int and pagination['workflow_id'] == workflow and type(pagination['page_size']) is int and pagination['page_size'] == page_size and type(pagination['next_page']) is int and 0 < pagination['next_page'] <= 10**9, 'discovery pagination identity differs')
    watch = value['watch']
    require(isinstance(watch, dict) and set(watch) == {'segments', 'count'} and all(type(watch[k]) is int and 0 <= watch[k] < 10**12 for k in ('segments', 'count')) and watch['segments'] <= watch['count'] <= watch['segments']*128, 'discovery watch manifest differs')
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

def advance(source_api, state_api, policy, approval_path, stream, *, page_size=10, tree_pages=1):
    """Read actual protected progress, advance one bounded page/scan and CAS atomically.

    Only checked scanner output is persisted. No caller checkpoint/cursor input is
    accepted. Full bootstrap verification remains mandatory until later anchor
    integration; a checkpoint's mere hash is never an origin grant.
    """
    require(source_api.repo == state_api.repo == policy['repository'] and stream == archive.archive_stream(state_api.repo), 'foreign discovery repository/stream')
    require(type(page_size) is int and 0 < page_size <= 100 and type(tree_pages) is int and 0 < tree_pages <= 10, 'discovery invocation budget invalid')
    workflow = policy['receipts']['workflow_id']; require(type(workflow) is int and workflow > 0, 'discovery workflow missing')
    root = 'repos/'+state_api.repo; path = f'receipt-archive/progress/{stream}.json'
    consumed = 0; calls = 0; cache = {}; attempted = None; attempted_changes = {}; uncertain = False

    def charge(value):
        nonlocal consumed
        size = len(archive.canonical(value)); consumed += size
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
            progress = {'schema_version': 1, 'stream': stream, 'binding': binding(anchor), 'anchor': {'head': anchor['head'], 'tree': anchor['tree']},
                        'scan': {'head': anchor['head'], 'tree': anchor['tree'], 'cursor': None, 'complete': True},
                        'pagination': {'workflow_id': workflow, 'page_size': page_size, 'next_page': 1}, 'watch': {'segments': 0, 'count': 0}, 'coverage_complete': False}
            cursor = None
        else:
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
        page = progress['pagination']['next_page']
        target = f'{root}/actions/workflows/{workflow}/runs?per_page={page_size}&page={page}'
        response = charge(source_api.request(target))
        require(isinstance(response, dict) and isinstance(response.get('workflow_runs'), list) and len(response['workflow_runs']) <= page_size, 'discovery run page malformed')
        new_rows = []; changes = {}; page_seen = set()
        for run in response['workflow_runs']:
            require(isinstance(run, dict) and run.get('repository', {}).get('id') == anchor['repository_id'] and run['repository'].get('full_name') == state_api.repo and type(run.get('workflow_id')) is int and run['workflow_id'] == workflow and run.get('path') == archive.receipts.RUNTIME_PATHS[0] and run.get('event') in ('workflow_run', 'workflow_dispatch') and run.get('head_branch') == policy['base_branch'] and all(type(run.get(k)) is int and run[k] > 0 for k in ('id', 'run_attempt')) and archive.state_paths.valid_hash(run.get('head_sha'), 40), 'discovery run identity differs')
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
                changes[lookup_path] = archive.canonical({'schema_version': 1, 'repository': state_api.repo, 'stream': stream, 'run_id': row['run_id'], 'attempt': row['attempt'], 'source_sha': row['source_sha'], 'segment': progress['watch']['segments']})
        if new_rows:
            number = progress['watch']['segments']
            segment = validate_watch({'schema_version': 1, 'repository': state_api.repo, 'stream': stream, 'number': number, 'rows': new_rows}, state_api.repo, stream, number)
            segment_path = archive.state_paths.pending_segment_path(stream, number)
            require(blob_at(anchor['tree'], segment_path) is None, 'discovery conflicting occupied watch segment')
            changes[segment_path] = archive.canonical(segment)
            progress['watch']['segments'] += 1
            progress['watch']['count'] += len(new_rows)
        progress['pagination']['next_page'] = page+1
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
    raise ValueError('discovery checkpoint uncertain after three CAS observations; reconcile before progress')
