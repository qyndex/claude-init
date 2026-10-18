#!/usr/bin/env python3
"""Bounded compact proof data. Integrity validation alone does not establish origin."""
import base64
import binascii
import datetime
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

reporting_spec = importlib.util.spec_from_file_location('reporting_policy', Path(__file__).with_name('factory-reporting-policy.py'))
reporting_policy = importlib.util.module_from_spec(reporting_spec); reporting_spec.loader.exec_module(reporting_policy)

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
    require(len(materials) <= 10, 'archive material count exceeds bound')
    decoded = {}
    for key, value in materials.items():
        raw = decode(value)
        require(digest(raw) == key, 'archive material digest differs')
        decoded[key] = raw
    runtime_paths = set(links) - {'factory/policy.json', 'factory/receipt-trust.json', 'spec'}
    require(frozenset(runtime_paths) in receipts.RUNTIME_FAMILIES and set(links) == {'factory/policy.json', 'factory/receipt-trust.json', *runtime_paths, 'spec'}, 'archive material paths differ')
    source = document(decoded[links['factory/policy.json']]); trust = document(decoded[links['factory/receipt-trust.json']])
    require(source['base_branch'] == execution['branch'] and source['repository'] == repository == receipt['repository'] and receipts.coordinator.policy_hash(source) == receipt['policy_sha256'] == facts['policy_sha256'], 'archive policy differs')
    require(receipts.coordinator.policy_hash(trust) == facts['document_sha256'], 'archive trust differs')
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / 'trust.json'; path.write_bytes(canonical(trust))
        receipts.load_receipt_trust(path, repository, mode='report')
    require({p: digest(decoded[links[p]]) for p in runtime_paths} == facts['runtime'], 'archive runtime differs')
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


def _approved_policy_digest(policy, approval, approval_path, *, now=None):
    """Explicit v2 protected observations; retain the exact v1 raw contract."""
    require(type(approval.get('schema_version')) is int and approval['schema_version'] in (1, 2), 'archive bootstrap schema differs')
    if approval['schema_version'] == 1:
        return digest(canonical(policy))
    observations = reporting_policy.load(Path(approval_path).with_name(reporting_policy.SIDECAR),
        approval['repository'], approval['repository_id'], approval['branch'], approval['writer_app_id'], now=now)
    require(set(observations) == set(approval['policies']), 'archive reporting observation identities differ')
    repo = {'id': approval['repository_id'], 'full_name': approval['repository']}
    result = reporting_policy.validate(repo, policy, approval['branch'], approval['writer_app_id'],
        observations.get(str(policy.get('id'))), now=now)
    return result['metadata_sha256']


def _bootstrap_context(api, approval_path, *, now=None):
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
    require(isinstance(approval, dict) and set(approval) == expected and type(approval['schema_version']) is int and approval['schema_version'] in (1, 2), 'archive bootstrap schema differs')
    require(approval['repository'] == api.repo, 'archive bootstrap repository differs')
    require(all(type(approval[k]) is int and approval[k] > 0 for k in ('repository_id', 'writer_app_id')) and type(approval['private']) is bool, 'archive bootstrap repository/writer invalid')
    branch = approval['branch']
    require(isinstance(branch, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*', branch) is not None and '..' not in branch and not branch.endswith('/'), 'archive bootstrap branch invalid')
    require(all(receipts.coordinator.contract.digest(approval[k], 40) for k in ('bootstrap_sha', 'bootstrap_tree')), 'archive bootstrap revision invalid')
    observed = instant(approval['observed_at']); origin = instant(approval['coverage_from'])
    require(origin <= observed <= now, 'archive coverage/approval clock invalid')
    consumed = 0; calls = 0; immutable = {}

    def read(path):
        nonlocal consumed, calls
        cacheable = any(path.startswith(f'repos/{api.repo}/git/'+kind+'/') and state_paths.valid_hash(path.rsplit('/', 1)[1], 40) for kind in ('commits', 'trees', 'blobs'))
        if cacheable and path in immutable:
            return document(immutable[path])
        require(calls < 2048, 'archive bootstrap API call bound reached; explicit coverage gap')
        calls += 1
        value = api.request(path)
        size = len(canonical(value)); consumed += size
        require(size <= MAX_OBJECT and consumed <= 33554432, 'archive bootstrap API response bound reached; explicit coverage gap')
        if cacheable:
            immutable[path] = canonical(value)
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
        require(_approved_policy_digest(policy, approval, approval_path, now=now) == approval['policies'][identity], 'archive protection policy changed')
        require(type(policy['id']) is int and policy['id'] == int(identity) and policy['source'] == api.repo and policy['source_type'] == 'Repository' and policy['target'] == 'branch' and policy['enforcement'] == 'active' and policy['conditions'] == conditions, 'archive protection scope differs')
        require((observed - instant(policy['updated_at'])).total_seconds() >= 60, 'archive protection must settle before approval')
        kinds = [rule['type'] for rule in policy['rules']]
        if 'update' in kinds:
            require(policy['rules'] == [{'type': 'update'}], 'archive exclusive writer policy must be update-only')
            if approval['schema_version'] == 1:
                require(policy['bypass_actors'] == [{'actor_id': approval['writer_app_id'], 'actor_type': 'Integration', 'bypass_mode': 'always'}], 'archive exclusive App writer differs')
            exclusive += 1
        else:
            require(set(kinds) <= {'non_fast_forward', 'deletion'}, 'archive rewrite/deletion protection must be no-bypass')
            if approval['schema_version'] == 1:
                require(policy['bypass_actors'] == [], 'archive rewrite/deletion protection must be no-bypass')
            covered.update(kinds)
    require(exclusive == 1 and covered == {'non_fast_forward', 'deletion'}, 'archive exclusive writer or immutable protection missing')
    ref = read(root + '/git/ref/heads/' + quote(branch, safe=''))
    require(ref['ref'] == 'refs/heads/' + branch and ref['object']['type'] == 'commit', 'archive state reference differs')
    return {'approval': approval, 'root': root, 'repo': repo, 'read': read, 'ref': ref}


def _origin_publication(api, context, head):
    """Authenticate protected scanner publication; a blob/hash alone is not proof.

    The exclusive reviewed App writer is the existing origin authority. Its
    checkpoint-only publication certifies checked content of a frozen prefix;
    comparison metadata only binds ancestry, never intermediate content.
    """
    from urllib.parse import quote
    approval, root, read = (context[key] for key in ('approval', 'root', 'read'))
    class Reader:
        repo = api.repo
        request = staticmethod(read)
    item_at, blob_at = fixed_reader(Reader(), root)
    require(state_paths.valid_hash(head, 40), 'archive bootstrap ancestry invalid')
    current = read(root+'/git/commits/'+head)
    require(current['sha'] == head and state_paths.valid_hash(current['tree']['sha'], 40), 'origin current commit differs')
    path = 'receipt-archive/origin/'+archive_stream(api.repo)+'.json'
    raw = blob_at(current['tree']['sha'], path)
    if raw is None:
        return None
    bootstrap = read(root+'/git/commits/'+approval['bootstrap_sha'])
    require(bootstrap['sha'] == approval['bootstrap_sha'] and bootstrap['tree']['sha'] == approval['bootstrap_tree'], 'origin bootstrap commit differs')
    require(item_at(approval['bootstrap_tree'], path) is None, 'origin checkpoint pre-bootstrap requires explicit reviewed import')
    binding = {key: approval[key] for key in ('repository', 'repository_id', 'private', 'branch', 'bootstrap_sha', 'bootstrap_tree', 'coverage_from', 'writer_app_id', 'policies')}
    binding['approval_sha256'] = digest(canonical(approval))
    progress = document(raw)
    require(type(progress) is dict and set(progress) == {'schema_version', 'binding', 'frozen_head', 'frozen_tree', 'prior_verified', 'next_sha', 'tree_cursor', 'checked_commits', 'complete', 'publication_parent'}
            and type(progress['schema_version']) is int and progress['schema_version'] == 1
            and canonical(progress['binding']) == canonical(binding) and type(progress['complete']) is bool
            and type(progress['checked_commits']) is int and 0 <= progress['checked_commits'] < 10**12
            and all(state_paths.valid_hash(progress[key], 40) for key in ('frozen_head', 'frozen_tree', 'publication_parent'))
            and (progress['prior_verified'] is None or state_paths.valid_hash(progress['prior_verified'], 40))
            and ((progress['complete'] and progress['next_sha'] is None and progress['tree_cursor'] is None and progress['checked_commits'] > 0)
                 or (not progress['complete'] and state_paths.valid_hash(progress['next_sha'], 40))), 'origin protected checkpoint schema/binding differs')
    history = read(root+'/commits?sha='+head+'&path='+quote(path, safe='')+'&per_page=1')
    require(type(history) is list and len(history) == 1 and state_paths.valid_hash(history[0].get('sha'), 40), 'origin checkpoint publication missing')
    publication = read(root+'/git/commits/'+history[0]['sha'])
    require(publication['sha'] == history[0]['sha'] and type(publication['parents']) is list and len(publication['parents']) == 1
            and publication['parents'][0]['sha'] == progress['publication_parent'], 'origin checkpoint publication parent differs')
    parent = read(root+'/git/commits/'+progress['publication_parent'])
    require(parent['sha'] == progress['publication_parent'] and blob_at(publication['tree']['sha'], path) == raw, 'origin checkpoint publication bytes differ')
    _origin_delta(read, root, parent['tree']['sha'], publication['tree']['sha'], path)
    frozen = read(root+'/git/commits/'+progress['frozen_head'])
    require(frozen['sha'] == progress['frozen_head'] and frozen['tree']['sha'] == progress['frozen_tree'], 'origin frozen tree differs')
    _origin_ancestor(read, root, approval['bootstrap_sha'], progress['frozen_head'])
    _origin_ancestor(read, root, progress['frozen_head'], parent['sha'])
    _origin_ancestor(read, root, publication['sha'], head)
    if progress['prior_verified'] is not None:
        _origin_ancestor(read, root, approval['bootstrap_sha'], progress['prior_verified'])
        _origin_ancestor(read, root, progress['prior_verified'], progress['frozen_head'])
    return progress, parent['sha']


def _completed_origin(api, context):
    # An incomplete scan may reuse only an earlier authenticated COMPLETE
    # publication, never the current partial flag or its asserted prior hash.
    head = context['ref']['object']['sha']; expected = None; seen = set()
    for _ in range(256):
        require(head not in seen, 'prior completed origin cycle invalid'); seen.add(head)
        item = _origin_publication(api, context, head)
        if item is None:
            require(expected is None, 'prior completed origin proof missing')
            return None
        progress, parent = item
        if progress['complete']:
            require(expected is None or progress['frozen_head'] == expected, 'prior completed origin proof differs')
            return progress['frozen_head']
        prior = progress['prior_verified']
        require(expected is None or prior == expected, 'prior completed origin chain differs')
        if prior is None:return None
        expected = prior; head = parent
    raise ValueError('prior completed origin traversal bound exceeded')


def verify_bootstrap(api, approval_path, *, now=None):
    from urllib.parse import quote
    context = _bootstrap_context(api, approval_path, now=now)
    approval, root, repo, read, ref = (context[key] for key in ('approval', 'root', 'repo', 'read', 'ref'))
    ids = set(approval['policies'])
    branch = approval['branch']
    verified_prefix = _completed_origin(api, context)
    head = ref['object']['sha']; sha = head; seen = set(); head_tree = None
    for _ in range(256):
        require(receipts.coordinator.contract.digest(sha, 40) and sha not in seen, 'archive bootstrap ancestry invalid')
        seen.add(sha)
        commit = read(root + '/git/commits/' + sha)
        require(commit['sha'] == sha and receipts.coordinator.contract.digest(commit['tree']['sha'], 40), 'archive bootstrap commit/tree differs')
        tree_sha = commit['tree']['sha']
        if head_tree is None:
            head_tree = tree_sha
        if sha == verified_prefix and sha != approval['bootstrap_sha']:
            break  # Actual protected completed publication already certifies this tree.
        bootstrap = sha == approval['bootstrap_sha']
        if bootstrap:
            require(tree_sha == approval['bootstrap_tree'], 'archive bootstrap tree differs')
        else:
            require(type(commit.get('parents')) is list and len(commit['parents']) == 1
                    and type(commit['parents'][0]) is dict and state_paths.valid_hash(commit['parents'][0].get('sha'), 40),
                    'archive bootstrap ancestry missing or merged')
            parent_sha = commit['parents'][0]['sha']
            parent = read(root+'/git/commits/'+parent_sha)
            require(parent.get('sha') == parent_sha and type(parent.get('tree')) is dict
                    and state_paths.valid_hash(parent['tree'].get('sha'), 40), 'archive bootstrap parent identity/tree differs')
        class Reader:
            repo = api.repo
            request = staticmethod(read)
        cursor = None
        for tree_window in range(10):
            # Conditional deltas gain authority only after EVERY single-parent edge
            # reaches the checked bootstrap or authenticated completed prefix below.
            tree = (state_paths.scan_tree(Reader(), root, tree_sha, cursor=cursor) if bootstrap
                    else state_paths.scan_delta(Reader(), root, tree_sha, parent['tree']['sha'], cursor=cursor))
            if tree['complete']:
                break
            cursor = tree['cursor']  # Checked in-memory continuation; never external input.
        require(tree['complete'], 'archive bootstrap tree incomplete; authenticated cursor continuation required')
        if bootstrap:
            break
        sha = parent_sha
    else:
        raise ValueError('archive bootstrap ancestry bound reached; explicit coverage gap')
    for identity in sorted(ids):
        require(_approved_policy_digest(read(root + '/rulesets/' + identity), approval, approval_path, now=now) == approval['policies'][identity], 'archive protection changed during verification')
    require(read(root + '/git/ref/heads/' + quote(branch, safe='')) == ref, 'archive state changed during bootstrap verification')
    return {'repository': api.repo, 'repository_id': repo['id'], 'private': repo['private'], 'branch': branch, 'head': head, 'tree': head_tree,
            'bootstrap_sha': approval['bootstrap_sha'], 'bootstrap_tree': approval['bootstrap_tree'], 'coverage_from': approval['coverage_from'],
            'writer_app_id': approval['writer_app_id'], 'policies': approval['policies'], 'approval_sha256': digest(canonical(approval))}


def interval_scope(anchor, stream, interval_end, interval_scoped):
    """Namespace selector only; the caller must independently authenticate anchor."""
    require(type(interval_scoped) is bool and stream==archive_stream(anchor['repository'])
            and state_paths.valid_hash(anchor['approval_sha256'],64), 'interval scope binding invalid')
    if not interval_scoped:return stream
    require(type(interval_end) is str and len(interval_end)<=40, 'interval scope cutoff invalid')
    cutoff=instant(interval_end)
    require(cutoff.microsecond==0, 'interval scope requires exact seconds')
    return digest(canonical(['reporting-receipt-interval-v1',anchor['repository'],stream,
                             anchor['approval_sha256'],cutoff.isoformat()]))


def projection_scope(api, anchor, policy, stream, interval_end, interval_scoped, *, tree_sha=None):
    """Derive a revision from authenticated snapshot contents, never a caller count."""
    base=interval_scope(anchor,stream,interval_end,interval_scoped)
    if not interval_scoped:return base
    tree=anchor['tree'] if tree_sha is None else tree_sha
    require(state_paths.valid_hash(tree,40), 'projection interval tree identity invalid')
    _,blob_at=fixed_reader(api,'repos/'+api.repo)
    raw=blob_at(tree,'receipt-archive/discovery/'+stream+'.json')
    count=0
    if raw is not None:
        journal=document(raw)
        require(type(journal) is dict and set(journal)=={'schema_version','repository','stream','coverage_from','next_segment','records_count'}
                and type(journal['schema_version']) is int and journal['schema_version']==1
                and journal['repository']==api.repo and journal['stream']==stream and journal['coverage_from']==anchor['coverage_from']
                and type(journal['next_segment']) is int and 0<=journal['next_segment']<10**12
                and type(journal['records_count']) is int and journal['records_count']==journal['next_segment'],
                'projection interval retained counter differs')
        count=journal['records_count']
    # Missing journal is only a namespace hint. The window still independently
    # proves empty archive namespaces before it can publish an empty snapshot.
    return digest(canonical([base,count,receipts.coordinator.policy_hash(policy)]))


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
        approval = document(Path(approval_path).read_bytes())
        require(digest(canonical(approval)) == anchor['approval_sha256'], 'archive bootstrap approval changed before append')
        for policy_id, expected_hash in anchor['policies'].items():
            require(_approved_policy_digest(api.request(root+'/rulesets/'+policy_id), approval, approval_path) == expected_hash, 'archive writer protection changed before append')
        try:
            result = api.request(root+'/git/refs/heads/'+quote(anchor['branch'], safe=''), 'PATCH', {'sha': commit['sha'], 'force': False})
            require(result['ref'] == 'refs/heads/'+anchor['branch'] and result['object']['sha'] == commit['sha'], 'archive reference acknowledgement differs')
        except Exception:
            uncertain = True
            continue  # Ref may have committed: re-read authoritative origin before any progress claim.
        return {'status': 'appended', 'head': commit['sha'], 'record_sha256': record_hash}
    raise ValueError('archive append uncertain after three CAS observations; reconcile before advancing')


def projection_window(state_api, policy, trust_path, store, approval_path, stream, *, interval_end, start=0, limit=128, frozen_head=None, _empty_origin=False):
    """Validate one bounded frozen retained window, granting no cursor/origin authority.

    Authenticate the protected view internally and recheck before returning facts.
    T301 publication and T302 reconstruction must independently authenticate this
    result's stored origin; a caller JSON/hash is never proof. Full bootstrap's
    existing 256-commit bound remains explicit until T288 integration.
    interval_end labels the requested campaign, not a timestamp filter: this
    validates the entire frozen snapshot range. T302/T288 must apply authenticated
    report-time semantics and reconcile cross-window duplicates/conflicts before
    claiming any requested interval complete.
    """
    require(type(start) is int and start >= 0 and type(limit) is int and 1 <= limit <= 128, 'archive projection window bounds differ')
    require(state_api.repo == policy['repository'] == store['repository'] and stream == archive_stream(state_api.repo), 'foreign archive reporting repository/stream')
    require(set(store) == {'repository', 'visibility'} and store['visibility'] in ('public', 'private'), 'archive reporting store differs')
    consumed = 0; calls = 0; cache = {}; root = 'repos/'+state_api.repo

    class ReadOnly:
        repo = state_api.repo

        def request(self, path, method='GET', payload=None):
            nonlocal consumed, calls
            require(method == 'GET' and payload is None and (path == root or path.startswith(root+'/')), 'archive reporting API must be read-only and same repository')
            immutable = '/git/trees/' in path or '/git/blobs/' in path
            if immutable and path in cache:
                return cache[path]
            calls += 1
            require(calls <= 2048, 'archive reporting API observation bound reached')
            value = state_api.request(path)
            size = len(canonical(value)); consumed += size
            require(size <= 2097152 and consumed <= 33554432, 'archive reporting observation bound reached; explicit coverage gap')
            if immutable:
                cache[path] = value
            return value

    api = ReadOnly(); anchor = verify_bootstrap(api, approval_path)
    view_head = anchor['head']; view_tree = anchor['tree']
    if frozen_head is not None and frozen_head != view_head:
        require(state_paths.valid_hash(frozen_head, 40), 'archive projection frozen view differs')
        _origin_ancestor(api.request, root, anchor['bootstrap_sha'], frozen_head)
        _origin_ancestor(api.request, root, frozen_head, anchor['head'])
        frozen = api.request(root+'/git/commits/'+frozen_head)
        require(frozen['sha'] == frozen_head and state_paths.valid_hash(frozen['tree']['sha'], 40), 'archive projection frozen tree differs')
        view_head = frozen_head; view_tree = frozen['tree']['sha']
    require(instant(anchor['coverage_from']) <= instant(interval_end) <= datetime.datetime.now(datetime.timezone.utc), 'archive projection interval differs')
    receipts.load_receipt_trust(trust_path, state_api.repo, mode='report')
    trust_sha256 = digest(Path(trust_path).read_bytes())
    approval_sha256 = digest(Path(approval_path).read_bytes())
    require(store['visibility'] == ('private' if anchor['private'] else 'public'), 'archive actual store visibility differs')
    item_at, blob_at = fixed_reader(api, root); tree = view_tree
    require(blob_at(anchor['bootstrap_tree'], f'receipt-archive/discovery/{stream}.json') is None, 'archive pre-bootstrap proof requires explicit reviewed import')
    journal_raw = blob_at(tree, f'receipt-archive/discovery/{stream}.json')
    if journal_raw is None:
        require(_empty_origin is True, 'archive discovery missing; cannot claim retained coverage')
        require(all(item_at(tree, 'receipt-archive/'+name) is None for name in ('index','objects','materials')), 'archive discovery missing; cannot claim retained coverage')
        journal = {'schema_version':1,'repository':state_api.repo,'stream':stream,'coverage_from':anchor['coverage_from'],'next_segment':0,'records_count':0}
    else:
        journal = document(journal_raw)
    require(set(journal) == {'schema_version', 'repository', 'stream', 'coverage_from', 'next_segment', 'records_count'} and type(journal['schema_version']) is int and journal['schema_version'] == 1 and journal['repository'] == state_api.repo and journal['stream'] == stream and journal['coverage_from'] == anchor['coverage_from'] and type(journal['next_segment']) is int and 0 <= journal['next_segment'] < 10**12 and type(journal['records_count']) is int and journal['records_count'] == journal['next_segment'], 'archive discovery identity/progress differs')
    require(start <= journal['next_segment'], 'archive projection window range differs')
    stop = min(start + limit, journal['next_segment'])
    proofs = []; references = []; seen = set()
    for number in range(start, stop):
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
            require(isinstance(links, dict) and len(links) <= 10 and all(state_paths.valid_hash(k, 64) for k in links.values()), 'archive material links differ')
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
            references.append(dict(reference, segment=number))
    require(len(proofs) == stop-start, 'archive retained window count differs')
    by_task = {}
    for proof in proofs:
        for task in proof['tasks']:
            require(task not in by_task or by_task[task] == proof, 'conflicting reporting delivery proof')
            by_task[task] = proof
    # All origin, material and conflict checks finish before any SQLite mutation.
    require(verify_bootstrap(api, approval_path) == anchor, 'archive reporting origin changed before projection')
    require(digest(Path(approval_path).read_bytes()) == approval_sha256, 'archive projection approval changed during validation')
    require(digest(Path(trust_path).read_bytes()) == trust_sha256, 'archive projection trust changed during validation')
    return {'schema_version': 1, 'repository': state_api.repo, 'stream': stream,
            'repository_id': anchor['repository_id'], 'private': anchor['private'],
            'frozen_head': view_head, 'tree': view_tree, 'observed_head': anchor['head'],
            'bootstrap_sha': anchor['bootstrap_sha'], 'bootstrap_tree': anchor['bootstrap_tree'],
            'coverage_from': anchor['coverage_from'], 'interval_end': interval_end,
            'start': start, 'next_segment': stop, 'records_count': journal['records_count'],
            'trust_sha256': trust_sha256, 'approval_sha256': approval_sha256,
            'policy_sha256': receipts.coordinator.policy_hash(policy),
            'proofs': proofs, 'references': references,
            'all_segments_checked': start == 0 and stop == journal['next_segment'],
            'coverage_complete': False}


def project_retained(state_api, policy, db_path, trust_path, store, approval_path, stream):
    """Legacy all-at-once reporting projection; resumable publication remains pending."""
    import sqlite3
    window = projection_window(state_api, policy, trust_path, store, approval_path, stream,
                               interval_end=datetime.datetime.now(datetime.timezone.utc).isoformat())
    require(window['all_segments_checked'], 'archive reporting segment invocation bound reached; resumable continuation required')
    by_task = {}
    for proof in window['proofs']:
        for task in proof['tasks']:
            require(task not in by_task or by_task[task] == proof, 'conflicting reporting delivery proof')
            by_task[task] = proof
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
    require(isinstance(links, dict) and len(links) <= 10 and all(state_paths.valid_hash(k, 64) for k in links.values()), 'retained lookup materials differ')
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


def _origin_ancestor(read, root, base, head):
    """Compare metadata assists ancestry; it never proves intermediate content."""
    require(all(state_paths.valid_hash(value, 40) for value in (base, head)), 'origin comparison identity invalid')
    value = read(root+'/compare/'+base+'...'+head+'?per_page=1&page=2')
    require(value['base_commit']['sha'] == base and value['merge_base_commit']['sha'] == base
            and value['status'] == ('identical' if base == head else 'ahead')
            and type(value['behind_by']) is int and value['behind_by'] == 0
            and all(type(value[key]) is int and value[key] >= 0 for key in ('ahead_by', 'total_commits')),
            'origin comparison does not prove ancestry')


def _origin_delta(read, root, before, after, path):
    """Authenticate a publication that changes exactly one strict inert path."""
    prefix = ''
    for component in path.split('/'):
        values = []
        for sha in (before, after):
            if sha is None:
                values.append({}); continue
            tree = read(root+'/git/trees/'+sha)
            require(tree.get('sha') == sha and tree.get('truncated') is False and type(tree.get('tree')) is list,
                    'origin checkpoint-only tree incomplete')
            items = {}
            for item in tree['tree']:
                require(type(item) is dict and type(item.get('path')) is str and '/' not in item['path']
                        and item['path'] not in items, 'origin checkpoint-only entries malformed')
                state_paths.validate_entry(dict(item, path=prefix+item['path']))
                items[item['path']] = {key: item[key] for key in ('path', 'type', 'mode', 'sha')}
            values.append(items)
        old, new = values
        require({key: value for key, value in old.items() if key != component}
                == {key: value for key, value in new.items() if key != component}
                and component in new, 'origin publication is not checkpoint-only')
        if prefix+component == path:
            require(new[component]['type'] == 'blob' and new[component]['mode'] == '100644', 'origin publication is not checkpoint-only')
            return
        require(new[component]['type'] == 'tree' and (component not in old or old[component]['type'] == 'tree'),
                'origin publication is not checkpoint-only')
        before = old.get(component, {}).get('sha'); after = new[component]['sha']; prefix += component+'/'


def advance_origin(state_api, approval_path, *, commit_budget=16, tree_pages=4, now=None):
    """Persist bounded checked windows using protected App-writer origin, not signatures.

    verify_bootstrap authenticates this protected publication before using its
    completed prefix. complete covers only its frozen snapshot; newer suffixes remain
    explicitly pending. No caller-provided resume JSON is accepted.
    """
    from urllib.parse import quote
    import uuid
    require(type(commit_budget) is int and 0 < commit_budget <= 32
            and type(tree_pages) is int and 0 < tree_pages <= 8, 'origin window bounds invalid')
    consumed = calls = 0

    class Bounded:
        repo = state_api.repo

        def request(self, path, method='GET', payload=None):
            nonlocal consumed, calls
            require(calls < 2048, 'origin invocation API call capacity gap')
            calls += 1
            result = state_api.request(path, method, payload)
            size = len(canonical(result)); consumed += size
            require(size <= MAX_OBJECT and consumed <= 33554432, 'origin invocation response capacity gap')
            return result

    api = Bounded(); stream = archive_stream(api.repo); path = 'receipt-archive/origin/'+stream+'.json'
    uncertain = False
    for attempt in range(3):
        context = _bootstrap_context(api, approval_path, now=now)
        approval, root, repo, read, ref = (context[key] for key in ('approval', 'root', 'repo', 'read', 'ref'))
        head = ref['object']['sha']; current = read(root+'/git/commits/'+head)
        require(current['sha'] == head and state_paths.valid_hash(current['tree']['sha'], 40), 'origin current commit differs')
        tree = current['tree']['sha']; bootstrap = read(root+'/git/commits/'+approval['bootstrap_sha'])
        require(bootstrap['sha'] == approval['bootstrap_sha'] and bootstrap['tree']['sha'] == approval['bootstrap_tree'], 'origin bootstrap commit differs')
        _origin_ancestor(read, root, approval['bootstrap_sha'], head)
        item_at, blob_at = fixed_reader(api, root)
        require(item_at(approval['bootstrap_tree'], path) is None, 'origin checkpoint pre-bootstrap requires explicit reviewed import')
        binding = {key: approval[key] for key in ('repository', 'repository_id', 'private', 'branch', 'bootstrap_sha', 'bootstrap_tree', 'coverage_from', 'writer_app_id', 'policies')}
        binding['approval_sha256'] = digest(canonical(approval))
        raw = blob_at(tree, path)
        if raw is None:
            progress = {'schema_version': 1, 'binding': binding, 'frozen_head': head, 'frozen_tree': tree,
                        'prior_verified': None, 'next_sha': head, 'tree_cursor': None,
                        'checked_commits': 0, 'complete': False, 'publication_parent': head}
        else:
            progress = document(raw)
            require(type(progress) is dict and set(progress) == {'schema_version', 'binding', 'frozen_head', 'frozen_tree', 'prior_verified', 'next_sha', 'tree_cursor', 'checked_commits', 'complete', 'publication_parent'}
                    and type(progress['schema_version']) is int and progress['schema_version'] == 1
                    and progress['binding'] == binding and type(progress['complete']) is bool
                    and type(progress['checked_commits']) is int and 0 <= progress['checked_commits'] < 10**12
                    and all(state_paths.valid_hash(progress[key], 40) for key in ('frozen_head', 'frozen_tree', 'publication_parent'))
                    and (progress['prior_verified'] is None or state_paths.valid_hash(progress['prior_verified'], 40))
                    and ((progress['complete'] and progress['next_sha'] is None and progress['tree_cursor'] is None)
                         or (not progress['complete'] and state_paths.valid_hash(progress['next_sha'], 40))), 'origin protected checkpoint schema/binding differs')
            # Actual API path history establishes publication origin. Hashes alone do not.
            history = read(root+'/commits?sha='+head+'&path='+quote(path, safe='')+'&per_page=1')
            require(type(history) is list and len(history) == 1 and state_paths.valid_hash(history[0].get('sha'), 40), 'origin checkpoint publication missing')
            publication = read(root+'/git/commits/'+history[0]['sha'])
            require(publication['sha'] == history[0]['sha'] and len(publication['parents']) == 1
                    and publication['parents'][0]['sha'] == progress['publication_parent'], 'origin checkpoint publication parent differs')
            _origin_ancestor(read, root, approval['bootstrap_sha'], publication['sha'])
            _origin_ancestor(read, root, publication['sha'], head)
            parent = read(root+'/git/commits/'+progress['publication_parent'])
            require(parent['sha'] == progress['publication_parent'], 'origin publication parent identity differs')
            require(blob_at(publication['tree']['sha'], path) == raw, 'origin checkpoint publication bytes differ')
            _origin_delta(read, root, parent['tree']['sha'], publication['tree']['sha'], path)
            frozen = read(root+'/git/commits/'+progress['frozen_head'])
            require(frozen['sha'] == progress['frozen_head'] and frozen['tree']['sha'] == progress['frozen_tree'], 'origin frozen tree differs')
            if not progress['complete']:
                _origin_ancestor(read, root, approval['bootstrap_sha'], progress['next_sha'])
                _origin_ancestor(read, root, progress['next_sha'], progress['frozen_head'])
            _origin_ancestor(read, root, approval['bootstrap_sha'], progress['frozen_head'])
            if progress['prior_verified'] is not None:
                _origin_ancestor(read, root, approval['bootstrap_sha'], progress['prior_verified'])
                _origin_ancestor(read, root, progress['prior_verified'], progress['frozen_head'])
            if progress['complete'] and publication['sha'] == head:
                # Reuse only the actual unchanged protected publication. The
                # existing verifier checks every suffix edge plus fresh mutable
                # policy/ref observations; a persisted complete flag is not proof.
                approval_raw = Path(approval_path).read_bytes()
                require(0 < len(approval_raw) <= 65536 and digest(canonical(document(approval_raw))) == binding['approval_sha256'],
                        'origin changed during completed-head verification')
                verified = verify_bootstrap(api, approval_path, now=now)
                require(verified['head'] == head and verified['tree'] == tree
                        and verified['approval_sha256'] == binding['approval_sha256']
                        and Path(approval_path).read_bytes() == approval_raw,
                        'origin changed during completed-head verification')
                return {'status': 'checkpointed', 'head': head, 'tree': tree,
                        'frozen_head': progress['frozen_head'], 'frozen_complete': True,
                        'checked_commits': progress['checked_commits'], 'coverage_complete': False,
                        'suffix_pending': head != progress['frozen_head'], 'uncertain_write_reconciled': uncertain}
            if progress['complete']:
                progress = dict(progress, frozen_head=head, frozen_tree=tree, prior_verified=progress['frozen_head'],
                                next_sha=head, tree_cursor=None, checked_commits=0, complete=False)
        for window in range(commit_budget):
            sha = progress['next_sha']; commit = read(root+'/git/commits/'+sha)
            require(commit['sha'] == sha and state_paths.valid_hash(commit['tree']['sha'], 40), 'origin scanned commit differs')
            if sha != approval['bootstrap_sha']:
                require(type(commit['parents']) is list and len(commit['parents']) == 1
                        and state_paths.valid_hash(commit['parents'][0]['sha'], 40), 'origin ancestry missing or merged')
            class Reader:
                repo = api.repo
                request = staticmethod(read)
            cursor = progress['tree_cursor']
            if sha == approval['bootstrap_sha'] or (cursor is not None and cursor.get('kind') != 'delta'):
                # Historic partial full-tree cursors retain their original check;
                # bootstrap has no independently valid parent and is always full.
                checked = state_paths.scan_tree(Reader(), root, commit['tree']['sha'], cursor=cursor, page_budget=tree_pages)
            else:
                parent = read(root+'/git/commits/'+commit['parents'][0]['sha'])
                require(parent['sha'] == commit['parents'][0]['sha'] and state_paths.valid_hash(parent['tree']['sha'], 40), 'origin delta parent identity differs')
                # Every edge is checked before the frozen snapshot can complete.
                # Unchanged subtrees inherit validity only once this walk reaches
                # the actual fully checked bootstrap or authenticated prefix.
                checked = state_paths.scan_delta(Reader(), root, commit['tree']['sha'], parent['tree']['sha'], cursor=cursor, page_budget=tree_pages)
            progress['tree_cursor'] = checked['cursor']
            if not checked['complete']:
                break
            progress['checked_commits'] += 1
            if sha == approval['bootstrap_sha'] or commit['parents'][0]['sha'] == progress['prior_verified']:
                progress.update(complete=True, next_sha=None)
                break
            require(commit['parents'][0]['sha'] != sha, 'origin ancestry cycle')
            progress['next_sha'] = commit['parents'][0]['sha']
        progress['publication_parent'] = head
        encoded = canonical(progress); require(len(encoded) <= MAX_OBJECT, 'origin checkpoint object capacity gap')
        blob = api.request(root+'/git/blobs', 'POST', {'encoding': 'base64', 'content': base64.b64encode(encoded).decode()})
        require(blob.get('sha') == hashlib.sha1(b'blob '+str(len(encoded)).encode()+b'\0'+encoded).hexdigest(), 'origin uploaded checkpoint differs')
        newtree = api.request(root+'/git/trees', 'POST', {'base_tree': tree, 'tree': [{'path': path, 'type': 'blob', 'mode': '100644', 'sha': blob['sha']}]})
        require(state_paths.valid_hash(newtree.get('sha'), 40), 'origin created tree invalid')
        _origin_delta(read, root, tree, newtree['sha'], path)
        publication = api.request(root+'/git/commits', 'POST', {'message': 'factory: checked origin window '+uuid.uuid4().hex, 'tree': newtree['sha'], 'parents': [head]})
        require(state_paths.valid_hash(publication.get('sha'), 40) and publication['tree']['sha'] == newtree['sha']
                and [parent['sha'] for parent in publication['parents']] == [head], 'origin created publication differs')
        for identity, expected in approval['policies'].items():
            require(_approved_policy_digest(read(root+'/rulesets/'+identity), approval, approval_path, now=now) == expected, 'origin protection changed before publication')
        if read(root+'/git/ref/heads/'+quote(approval['branch'], safe='')) != ref:
            continue
        try:
            api.request(root+'/git/refs/heads/'+quote(approval['branch'], safe=''), 'PATCH', {'sha': publication['sha'], 'force': False})
        except (ValueError, RuntimeError):
            uncertain = True
            try:
                observed = read(root+'/git/ref/heads/'+quote(approval['branch'], safe=''))
            except (ValueError, RuntimeError) as error:
                raise ValueError('origin publication acknowledgement uncertain; restart required') from error
            if observed['object']['sha'] != publication['sha']:
                continue
        observed = read(root+'/git/ref/heads/'+quote(approval['branch'], safe=''))
        require(observed['object']['sha'] == publication['sha'], 'origin publication acknowledgement uncertain')
        return {'status': 'checkpointed', 'head': publication['sha'], 'tree': newtree['sha'],
                'frozen_head': progress['frozen_head'], 'frozen_complete': progress['complete'],
                'checked_commits': progress['checked_commits'], 'coverage_complete': False,
                'suffix_pending': publication['sha'] != progress['frozen_head'], 'uncertain_write_reconciled': uncertain}
    raise ValueError('origin checkpoint three CAS attempts exhausted; progress incomplete')


def _projection_checkpoint(value, binding):
    """Shape/continuity checks only; actual protected publication grants origin."""
    require(type(value) is dict and set(value) == {'schema_version', 'binding', 'frozen_head', 'frozen_tree', 'records_count', 'next_segment', 'window', 'previous_blob', 'publication_parent'}, 'projection checkpoint schema differs')
    require(type(value['schema_version']) is int and value['schema_version'] == 1 and value['binding'] == binding, 'projection checkpoint binding differs')
    require(all(state_paths.valid_hash(value[k], 40) for k in ('frozen_head', 'frozen_tree', 'publication_parent')) and (value['previous_blob'] is None or state_paths.valid_hash(value['previous_blob'], 40)), 'projection checkpoint revision differs')
    require(type(value['records_count']) is int and type(value['next_segment']) is int and 0 <= value['next_segment'] <= value['records_count'] < 10**12, 'projection checkpoint progress differs')
    window = value['window']
    require(type(window) is dict and set(window) == {'start', 'stop', 'references', 'trust_sha256'} and type(window['start']) is int and type(window['stop']) is int and 0 <= window['start'] <= window['stop'] == value['next_segment'] and window['stop']-window['start'] <= 128 and state_paths.valid_hash(window['trust_sha256'], 64), 'projection checkpoint window differs')
    require((window['start'] == 0) == (value['previous_blob'] is None) and type(window['references']) is list and len(window['references']) == window['stop']-window['start'], 'projection checkpoint reference count differs')
    seen = set()
    for number, item in enumerate(window['references'], window['start']):
        require(type(item) is dict and set(item) == {'run_id', 'attempt', 'artifact_id', 'record_sha256', 'segment'} and all(type(item[k]) is int and item[k] > 0 for k in ('run_id', 'attempt', 'artifact_id')) and type(item['segment']) is int and item['segment'] == number and state_paths.valid_hash(item['record_sha256'], 64), 'projection checkpoint reference differs')
        identity = (item['run_id'], item['attempt'])
        require(identity not in seen, 'projection checkpoint duplicate execution')
        seen.add(identity)
    return value


def checkpoint_projection(state_api, policy, trust_path, store, approval_path, stream, *, interval_end, limit=32, interval_scoped=False):
    """Publish one checked window; no caller cursor or facts are accepted.

    A fixed bounded file links previous immutable Git blobs. Each publication
    changes only that inert file; historical windows are retained in Git history.
    T302 must authenticate/read that chain in bounded work before reconstruction.
    Completed protected origins resume history; unchecked suffixes remain bounded.
    """
    from urllib.parse import quote
    import uuid
    require(type(limit) is int and 0 < limit <= 128, 'projection checkpoint bounds differ')
    require(state_api.repo == policy['repository'] == store['repository'] and stream == archive_stream(state_api.repo), 'projection checkpoint repository differs')
    receipts.load_receipt_trust(trust_path, state_api.repo, mode='report')
    calls = consumed = cached_bytes = 0; immutable = {}; root = 'repos/'+state_api.repo

    class Bounded:
        repo = state_api.repo

        def request(self, path, method='GET', payload=None):
            nonlocal calls, consumed, cached_bytes
            require(path == root or path.startswith(root+'/'), 'projection checkpoint foreign API')
            cacheable = method == 'GET' and payload is None and any(path.startswith(root+'/git/'+kind+'/') and state_paths.valid_hash(path.rsplit('/',1)[1],40) for kind in ('commits','trees','blobs'))
            if cacheable and path in immutable:return document(immutable[path])
            require(calls < 2048, 'projection checkpoint API capacity gap')
            calls += 1
            value = state_api.request(path, method, payload)
            encoded = canonical(value); size = len(encoded); consumed += size
            require(size <= 2097152 and consumed <= 33554432, 'projection checkpoint observation capacity gap')
            if cacheable:
                require(cached_bytes+size <= 33554432, 'projection checkpoint normalized cache capacity gap')
                immutable[path] = encoded; cached_bytes += size
            return value

    api = Bounded(); uncertain = False
    for attempt in range(3):
        anchor = verify_bootstrap(api, approval_path)
        require(store == {'repository': api.repo, 'visibility': 'private' if anchor['private'] else 'public'}, 'projection checkpoint visibility differs')
        path = 'receipt-archive/projection/'+projection_scope(api,anchor,policy,stream,interval_end,interval_scoped)+'.json'
        approval = document(Path(approval_path).read_bytes())
        binding = {key: approval[key] for key in ('repository', 'repository_id', 'private', 'branch', 'bootstrap_sha', 'bootstrap_tree', 'coverage_from', 'writer_app_id', 'policies')}
        binding.update(stream=stream, approval_sha256=digest(canonical(approval)), policy_sha256=receipts.coordinator.policy_hash(policy), interval_end=interval_end)
        require(instant(anchor['coverage_from']) <= instant(interval_end) <= datetime.datetime.now(datetime.timezone.utc), 'projection checkpoint interval differs')
        item_at, blob_at = fixed_reader(api, root)
        require(item_at(anchor['bootstrap_tree'], path) is None, 'projection checkpoint pre-bootstrap requires explicit reviewed import')
        old = blob_at(anchor['tree'], path); previous_blob = None; start = 0; frozen = anchor['head']
        if old is not None:
            progress = _projection_checkpoint(document(old), binding)
            history = api.request(root+'/commits?sha='+anchor['head']+'&path='+quote(path, safe='')+'&per_page=1')
            require(type(history) is list and len(history) == 1 and state_paths.valid_hash(history[0].get('sha'), 40), 'projection checkpoint publication missing')
            publication = api.request(root+'/git/commits/'+history[0]['sha'])
            require(publication['sha'] == history[0]['sha'] and type(publication['parents']) is list and len(publication['parents']) == 1 and publication['parents'][0]['sha'] == progress['publication_parent'], 'projection checkpoint publication parent differs')
            _origin_ancestor(api.request, root, anchor['bootstrap_sha'], publication['sha'])
            _origin_ancestor(api.request, root, publication['sha'], anchor['head'])
            parent = api.request(root+'/git/commits/'+progress['publication_parent'])
            require(parent['sha'] == progress['publication_parent'] and blob_at(publication['tree']['sha'], path) == old, 'projection checkpoint publication bytes differ')
            _origin_delta(api.request, root, parent['tree']['sha'], publication['tree']['sha'], path)
            before_item = item_at(parent['tree']['sha'], path)
            require((before_item['sha'] if before_item else None) == progress['previous_blob'], 'projection checkpoint previous blob differs')
            if before_item is not None:
                prior = _projection_checkpoint(document(blob_at(parent['tree']['sha'], path)), binding)
                require(prior['next_segment'] == progress['window']['start'] and all(prior[key] == progress[key] for key in ('frozen_head', 'frozen_tree', 'records_count')), 'projection checkpoint previous continuity differs')
            _origin_ancestor(api.request, root, anchor['bootstrap_sha'], progress['frozen_head'])
            _origin_ancestor(api.request, root, progress['frozen_head'], progress['publication_parent'])
            frozen_commit = api.request(root+'/git/commits/'+progress['frozen_head'])
            require(frozen_commit['sha'] == progress['frozen_head'] and frozen_commit['tree']['sha'] == progress['frozen_tree'], 'projection checkpoint frozen tree differs')
            if progress['next_segment'] == progress['records_count']:
                require(verify_bootstrap(api, approval_path) == anchor, 'projection checkpoint origin changed')
                return {'status': 'already-checkpointed', 'head': anchor['head'], 'next_segment': progress['next_segment'], 'frozen_complete': True, 'coverage_complete': False, 'suffix_pending': anchor['head'] != progress['frozen_head']}
            start = progress['next_segment']; frozen = progress['frozen_head']; previous_blob = item_at(anchor['tree'], path)['sha']
        window = projection_window(api, policy, trust_path, store, approval_path, stream, interval_end=interval_end, start=start, limit=limit, frozen_head=frozen, _empty_origin=True)
        if window['observed_head'] != anchor['head']:
            continue
        progress = {'schema_version': 1, 'binding': binding, 'frozen_head': window['frozen_head'], 'frozen_tree': window['tree'], 'records_count': window['records_count'], 'next_segment': window['next_segment'], 'window': {'start': start, 'stop': window['next_segment'], 'references': window['references'], 'trust_sha256': window['trust_sha256']}, 'previous_blob': previous_blob, 'publication_parent': anchor['head']}
        _projection_checkpoint(progress, binding)
        encoded = canonical(progress); require(len(encoded) <= MAX_OBJECT, 'projection checkpoint object capacity gap')
        blob = api.request(root+'/git/blobs', 'POST', {'encoding': 'base64', 'content': base64.b64encode(encoded).decode()})
        require(blob.get('sha') == hashlib.sha1(b'blob '+str(len(encoded)).encode()+b'\0'+encoded).hexdigest(), 'projection checkpoint uploaded blob differs')
        tree = api.request(root+'/git/trees', 'POST', {'base_tree': anchor['tree'], 'tree': [{'path': path, 'type': 'blob', 'mode': '100644', 'sha': blob['sha']}]})
        require(state_paths.valid_hash(tree.get('sha'), 40), 'projection checkpoint created tree differs')
        _origin_delta(api.request, root, anchor['tree'], tree['sha'], path)
        commit = api.request(root+'/git/commits', 'POST', {'message': 'factory: checked projection window '+uuid.uuid4().hex, 'tree': tree['sha'], 'parents': [anchor['head']]})
        require(state_paths.valid_hash(commit.get('sha'), 40) and commit['tree']['sha'] == tree['sha'] and [p['sha'] for p in commit['parents']] == [anchor['head']], 'projection checkpoint created commit differs')
        for identity, expected in approval['policies'].items():
            require(_approved_policy_digest(api.request(root+'/rulesets/'+identity), approval, approval_path) == expected, 'projection checkpoint protection changed')
        require(digest(Path(trust_path).read_bytes()) == window['trust_sha256'] and digest(Path(approval_path).read_bytes()) == window['approval_sha256'], 'projection checkpoint protected input changed')
        refpath = root+'/git/ref/heads/'+quote(anchor['branch'], safe='')
        if api.request(refpath)['object']['sha'] != anchor['head']:
            continue
        try:
            api.request(root+'/git/refs/heads/'+quote(anchor['branch'], safe=''), 'PATCH', {'sha': commit['sha'], 'force': False})
        except (ValueError, RuntimeError):
            uncertain = True
            try:
                observed = api.request(refpath)
            except (ValueError, RuntimeError) as error:
                raise ValueError('projection checkpoint acknowledgement uncertain; restart required') from error
            if observed['object']['sha'] != commit['sha']:
                continue
        require(api.request(refpath)['object']['sha'] == commit['sha'], 'projection checkpoint acknowledgement uncertain')
        return {'status': 'checkpointed', 'head': commit['sha'], 'next_segment': progress['next_segment'], 'frozen_complete': progress['next_segment'] == progress['records_count'], 'coverage_complete': False, 'suffix_pending': True, 'uncertain_write_reconciled': uncertain}
    raise ValueError('projection checkpoint three CAS attempts exhausted; progress incomplete')


def projection_lineage(state_api, policy, trust_path, store, approval_path, stream, *, interval_end, page=1, limit=32, history_head=None, interval_scoped=False):
    """Read a bounded page of actual protected checkpoint publications.

    A caller page/SHA identifies requested work, never origin. Current protected
    bootstrap and exact ancestry establish every requested view independently.
    This reader grants neither retained-proof validity nor delivery coverage.
    The legacy full-bootstrap 256-commit integration limit remains explicit.
    """
    from urllib.parse import quote
    require(type(page) is int and 1 <= page <= 10**12 and type(limit) is int and 1 <= limit <= 32, 'projection lineage bounds differ')
    require(state_api.repo == policy['repository'] == store['repository'] and stream == archive_stream(state_api.repo), 'projection lineage repository differs')
    receipts.load_receipt_trust(trust_path, state_api.repo, mode='report')
    calls = consumed = 0; immutable = {}; root = 'repos/'+state_api.repo

    class Bounded:
        repo = state_api.repo

        def request(self, path, method='GET', payload=None):
            nonlocal calls, consumed
            require(method == 'GET' and payload is None and (path == root or path.startswith(root+'/')), 'projection lineage foreign API or write')
            cacheable = any(path.startswith(root+'/git/'+kind+'/') and state_paths.valid_hash(path.rsplit('/', 1)[1], 40) for kind in ('commits', 'trees', 'blobs'))
            if cacheable and path in immutable:
                return document(immutable[path])
            require(calls < 2048, 'projection lineage API capacity gap')
            calls += 1
            value = state_api.request(path, method, payload)
            size = len(canonical(value)); consumed += size
            require(size <= 2097152 and consumed <= 33554432, 'projection lineage observation capacity gap')
            if cacheable:
                immutable[path] = canonical(value)
                return document(immutable[path])
            return value

    api = Bounded(); anchor = verify_bootstrap(api, approval_path)
    require(store == {'repository': api.repo, 'visibility': 'private' if anchor['private'] else 'public'}, 'projection lineage visibility differs')
    approval_raw = Path(approval_path).read_bytes(); approval = document(approval_raw)
    trust_hash = digest(Path(trust_path).read_bytes())
    binding = {key: approval[key] for key in ('repository', 'repository_id', 'private', 'branch', 'bootstrap_sha', 'bootstrap_tree', 'coverage_from', 'writer_app_id', 'policies')}
    binding.update(stream=stream, approval_sha256=digest(canonical(approval)), policy_sha256=receipts.coordinator.policy_hash(policy), interval_end=interval_end)
    require(instant(anchor['coverage_from']) <= instant(interval_end) <= datetime.datetime.now(datetime.timezone.utc), 'projection lineage interval differs')
    selected = anchor['head'] if history_head is None else history_head
    require(state_paths.valid_hash(selected, 40), 'projection lineage history revision differs')
    _origin_ancestor(api.request, root, anchor['bootstrap_sha'], selected)
    _origin_ancestor(api.request, root, selected, anchor['head'])
    selected_commit = api.request(root+'/git/commits/'+selected)
    require(selected_commit['sha'] == selected, 'projection lineage history identity differs')
    path = 'receipt-archive/projection/'+projection_scope(api,anchor,policy,stream,interval_end,interval_scoped,tree_sha=selected_commit['tree']['sha'])+'.json'; item_at, blob_at = fixed_reader(api, root)
    require(item_at(anchor['bootstrap_tree'], path) is None, 'projection lineage pre-bootstrap requires explicit reviewed import')
    rows = api.request(root+'/commits?sha='+selected+'&path='+quote(path, safe='')+'&per_page='+str(limit)+'&page='+str(page))
    require(type(rows) is list and len(rows) <= limit, 'projection lineage publication list differs')
    windows = []; seen = set(); expected_blob = None
    for index, row in enumerate(rows):
        require(type(row) is dict and state_paths.valid_hash(row.get('sha'), 40) and row['sha'] not in seen, 'projection lineage duplicate or invalid publication')
        seen.add(row['sha'])
        publication = api.request(root+'/git/commits/'+row['sha'])
        require(publication['sha'] == row['sha'] and type(publication['parents']) is list and len(publication['parents']) == 1, 'projection lineage publication identity differs')
        _origin_ancestor(api.request, root, anchor['bootstrap_sha'], row['sha'])
        _origin_ancestor(api.request, root, row['sha'], selected)
        raw = blob_at(publication['tree']['sha'], path)
        require(raw is not None, 'projection lineage publication checkpoint missing')
        progress = _projection_checkpoint(document(raw), binding)
        require(publication['parents'][0]['sha'] == progress['publication_parent'], 'projection lineage publication parent differs')
        parent = api.request(root+'/git/commits/'+progress['publication_parent'])
        require(parent['sha'] == progress['publication_parent'], 'projection lineage parent identity differs')
        _origin_delta(api.request, root, parent['tree']['sha'], publication['tree']['sha'], path)
        blob = item_at(publication['tree']['sha'], path)['sha']
        if index == 0 and page == 1:
            require(item_at(selected_commit['tree']['sha'], path)['sha'] == blob, 'projection lineage latest publication differs')
        if expected_blob is not None:
            require(blob == expected_blob, 'projection lineage publication order differs')
        previous_item = item_at(parent['tree']['sha'], path)
        require((previous_item['sha'] if previous_item else None) == progress['previous_blob'], 'projection lineage previous blob differs')
        if previous_item is not None:
            prior = _projection_checkpoint(document(blob_at(parent['tree']['sha'], path)), binding)
            require(prior['next_segment'] == progress['window']['start'] and all(prior[k] == progress[k] for k in ('frozen_head', 'frozen_tree', 'records_count')), 'projection lineage previous continuity differs')
        _origin_ancestor(api.request, root, anchor['bootstrap_sha'], progress['frozen_head'])
        _origin_ancestor(api.request, root, progress['frozen_head'], progress['publication_parent'])
        frozen = api.request(root+'/git/commits/'+progress['frozen_head'])
        require(frozen['sha'] == progress['frozen_head'] and frozen['tree']['sha'] == progress['frozen_tree'], 'projection lineage frozen tree differs')
        windows.append({'publication_sha': row['sha'], 'blob_sha': blob, 'checkpoint': progress})
        expected_blob = progress['previous_blob']
    require(verify_bootstrap(api, approval_path) == anchor and Path(approval_path).read_bytes() == approval_raw and digest(Path(trust_path).read_bytes()) == trust_hash, 'projection lineage protected origin changed')
    reaches_start = bool(windows) and expected_blob is None
    return {'history_head': selected, 'observed_head': anchor['head'], 'windows': windows, 'page': page, 'next_page': page+1 if rows and not reaches_start else None, 'reaches_start': reaches_start, 'partial': page != 1 or not reaches_start, 'suffix_pending': not windows or any(w['checkpoint']['frozen_head'] != anchor['head'] for w in windows), 'coverage_complete': False}


def retained_merge_time(state_api, policy, store, approval_path, stream, run_id, attempt):
    """Derive time only from exact PR GET after protected retained authentication.

    Missing observations are explicit gaps; invalid identity/precision rejects.
    No inferred date, archive mutation, current-task credit or coverage is granted.
    """
    import re
    import subprocess
    require(state_api.repo == policy['repository'] == store['repository'] and stream == archive_stream(state_api.repo), 'retained time repository differs')
    calls = consumed = 0; immutable = {}; root = 'repos/'+state_api.repo

    class Bounded:
        repo = state_api.repo

        def request(self, path, method='GET', payload=None):
            nonlocal calls, consumed
            require(method == 'GET' and payload is None and (path == root or path.startswith(root+'/')), 'retained time foreign API or write')
            cacheable = any(path.startswith(root+'/git/'+kind+'/') and state_paths.valid_hash(path.rsplit('/', 1)[1], 40) for kind in ('commits', 'trees', 'blobs'))
            if cacheable and path in immutable:
                return document(immutable[path])
            require(calls < 2048, 'retained time API capacity gap')
            calls += 1
            value = state_api.request(path, method, payload)
            size = len(canonical(value)); consumed += size
            require(size <= 2097152 and consumed <= 33554432, 'retained time observation capacity gap')
            if cacheable:
                immutable[path] = canonical(value)
                return document(immutable[path])
            return value

    api = Bounded(); approval_raw = Path(approval_path).read_bytes()
    anchor = verify_bootstrap(api, approval_path)
    result = _retained_time_from_anchor(api, anchor, store, stream, run_id, attempt)
    require(verify_bootstrap(api, approval_path) == anchor and Path(approval_path).read_bytes() == approval_raw, 'retained time protected origin changed')
    return result


def stage_projection(state_api, policy, trust_path, store, approval_path, stream, *, interval_end, page=1, offset=0, limit=8, history_head=None, interval_scoped=False):
    """Derive one protected bounded slice; no supplied facts/cursors are authority.

    Conflict indices cover this frozen interval/trust campaign, not all history.
    Consumers must reauthenticate retained materials/current trust (T309).
    Unscanned suffixes retain the256-ancestor bound; coverage is always false here.
    """
    from urllib.parse import quote
    import uuid
    require(type(offset) is int and offset >= 0 and type(limit) is int and 1 <= limit <= 8, 'projection stage bounds differ')
    root = 'repos/'+state_api.repo; calls = consumed = 0; immutable = {}
    class Bounded:
        repo = state_api.repo
        def request(self, path, method='GET', payload=None):
            nonlocal calls, consumed
            require(path == root or path.startswith(root+'/'), 'projection stage foreign API')
            cacheable = method == 'GET' and payload is None and any(path.startswith(root+'/git/'+kind+'/') and state_paths.valid_hash(path.rsplit('/', 1)[1], 40) for kind in ('commits', 'trees', 'blobs'))
            if cacheable and path in immutable:
                return document(immutable[path])
            require(calls < 2048, 'projection stage API capacity gap'); calls += 1
            value = state_api.request(path, method, payload)
            size = len(canonical(value)); consumed += size
            require(size <= 2097152 and consumed <= 33554432, 'projection stage observation capacity gap')
            if cacheable:
                immutable[path] = canonical(value)
            return value
    api = Bounded(); uncertain = False; selected = history_head
    for retry in range(3):
        anchor = verify_bootstrap(api, approval_path)
        approval_raw = Path(approval_path).read_bytes(); trust_hash = digest(Path(trust_path).read_bytes())
        lineage = projection_lineage(api, policy, trust_path, store, approval_path, stream, interval_end=interval_end, page=page, limit=1, history_head=selected, interval_scoped=interval_scoped)
        selected = lineage['history_head']
        require(len(lineage['windows']) == 1, 'projection stage required window missing')
        window = lineage['windows'][0]; checkpoint = window['checkpoint']
        references = checkpoint['window']['references']
        binding = dict(checkpoint['binding'], frozen_head=checkpoint['frozen_head'], frozen_tree=checkpoint['frozen_tree'], trust_sha256=trust_hash)
        campaign = digest(canonical(binding)); prefix = 'receipt-archive/stages/'+campaign+'/'
        if not references:
            require(offset == 0 and checkpoint['records_count'] == checkpoint['next_segment'] == checkpoint['window']['start'] == checkpoint['window']['stop'] == 0, 'projection empty checkpoint differs')
            require(verify_bootstrap(api, approval_path) == anchor and Path(approval_path).read_bytes() == approval_raw and digest(Path(trust_path).read_bytes()) == trust_hash, 'projection empty protected input changed')
            return {'status':'empty-window','campaign':campaign,'facts_count':0,'coverage_complete':False}
        require(offset < len(references), 'projection stage slice missing')
        chosen = references[offset:offset+limit]
        def path_for(kind, identity):
            key = digest(canonical([kind, identity])); return prefix+key[:2]+'/'+key+'.json'
        facts = []; indexes = {}
        for reference in chosen:
            run_id, attempt = reference['run_id'], reference['attempt']
            retained = retained_execution(api, anchor, store, stream, run_id, attempt)
            require(retained is not None and retained['record_sha256'] == reference['record_sha256'] and retained['record']['artifact']['id'] == reference['artifact_id'], 'projection stage retained reference differs')
            # This slice already owns a verified anchor and rechecks mutable
            # origin/approval/trust below before any publication.
            timed = _retained_time_from_anchor(api, anchor, store, stream, run_id, attempt)
            if timed['status'] != 'observed':
                return {'status': 'gap', 'reason': timed['reason'], 'coverage_complete': False}
            fact = timed['fact']; tasks = retained['record']['proof']['tasks']
            fact = dict(fact, artifact_id=reference['artifact_id'], tasks=tasks, segment=reference['segment'])
            facts.append(fact)
            for kind, identities in (('execution', [[run_id, attempt]]), ('task', tasks)):
                for identity in identities:
                    index = {'schema_version': 1, 'campaign': campaign, 'kind': kind, 'identity': identity, 'run_id': run_id, 'attempt': attempt, 'record_sha256': reference['record_sha256']}
                    path = path_for(kind, identity)
                    require(path not in indexes or indexes[path] == index, 'projection stage conflicting '+kind)
                    indexes[path] = index
        stage = {'schema_version': 1, 'binding': binding, 'publication_sha': window['publication_sha'], 'checkpoint_blob': window['blob_sha'], 'offset': offset, 'stop': offset+len(chosen), 'facts': facts}
        stage_path = path_for('window', [window['publication_sha'], offset, limit])
        desired = {stage_path: stage, **indexes}; item_at, blob_at = fixed_reader(api, root)
        missing = {}
        for path, value in desired.items():
            require(item_at(anchor['bootstrap_tree'], path) is None, 'projection stage copied pre-bootstrap capsule')
            encoded = canonical(value); require(len(encoded) <= MAX_OBJECT, 'projection stage object capacity gap')
            old = blob_at(anchor['tree'], path)
            if old is not None:
                require(canonical(document(old)) == encoded, 'projection stage conflicting '+value.get('kind', 'window'))
            else:
                missing[path] = encoded
        require(verify_bootstrap(api, approval_path) == anchor and Path(approval_path).read_bytes() == approval_raw and digest(Path(trust_path).read_bytes()) == trust_hash, 'projection stage protected origin changed')
        if not missing:
            return {'status': 'already-staged', 'campaign': campaign, 'stage_path': stage_path, 'facts_count': len(facts), 'coverage_complete': False}
        require(stage_path in missing, 'projection stage incomplete index publication')
        tree_sha = anchor['tree']
        for path, encoded in missing.items():
            blob = api.request(root+'/git/blobs', 'POST', {'encoding': 'base64', 'content': base64.b64encode(encoded).decode()})
            require(blob.get('sha') == hashlib.sha1(b'blob '+str(len(encoded)).encode()+b'\0'+encoded).hexdigest(), 'projection stage uploaded blob differs')
            tree = api.request(root+'/git/trees', 'POST', {'base_tree': tree_sha, 'tree': [{'path': path, 'type': 'blob', 'mode': '100644', 'sha': blob['sha']}]})
            require(state_paths.valid_hash(tree.get('sha'), 40), 'projection stage created tree differs')
            _origin_delta(api.request, root, tree_sha, tree['sha'], path); tree_sha = tree['sha']
        commit = api.request(root+'/git/commits', 'POST', {'message': 'factory: checked derived stage '+uuid.uuid4().hex, 'tree': tree_sha, 'parents': [anchor['head']]})
        require(state_paths.valid_hash(commit.get('sha'), 40) and commit['tree']['sha'] == tree_sha and [p['sha'] for p in commit['parents']] == [anchor['head']], 'projection stage created commit differs')
        approval = document(approval_raw)
        for identity, expected in approval['policies'].items():
            require(_approved_policy_digest(api.request(root+'/rulesets/'+identity), approval, approval_path) == expected, 'projection stage protection changed')
        require(Path(approval_path).read_bytes() == approval_raw and digest(Path(trust_path).read_bytes()) == trust_hash, 'projection stage protected input changed')
        refpath = root+'/git/ref/heads/'+quote(anchor['branch'], safe='')
        if api.request(refpath)['object']['sha'] != anchor['head']:
            continue
        try:
            api.request(root+'/git/refs/heads/'+quote(anchor['branch'], safe=''), 'PATCH', {'sha': commit['sha'], 'force': False})
        except (ValueError, RuntimeError):
            uncertain = True
            try:
                observed = api.request(refpath)
            except (ValueError, RuntimeError) as error:
                raise ValueError('projection stage acknowledgement uncertain; restart required') from error
            if observed['object']['sha'] != commit['sha']:
                continue
        require(api.request(refpath)['object']['sha'] == commit['sha'], 'projection stage acknowledgement uncertain')
        return {'status': 'staged', 'campaign': campaign, 'stage_path': stage_path, 'facts_count': len(facts), 'coverage_complete': False, 'uncertain_write_reconciled': uncertain}
    raise ValueError('projection stage three CAS attempts exhausted; progress incomplete')


def _retained_time_from_anchor(api, anchor, store, stream, run_id, attempt):
    """Internal derivation under a separately authenticated/finally rechecked anchor.

    Returns data only; this helper never grants origin, coverage or SQL authority.
    """
    import re
    import subprocess
    root = "repos/"+api.repo
    retained = retained_execution(api, anchor, store, stream, run_id, attempt)
    result = {'status': 'gap', 'reason': 'retained-proof-missing', 'coverage_complete': False}
    if retained is not None:
        record = retained['record']; receipt = document(record['proof']['provenance'])['receipt']
        result = {'status': 'gap', 'reason': 'merge-time-unavailable', 'record_sha256': retained['record_sha256'], 'coverage_complete': False}
        try:
            pr = api.request(root+'/pulls/'+str(receipt['pull_request']))
        except (RuntimeError, OSError, subprocess.TimeoutExpired):
            pass
        except ValueError as error:
            if not str(error).startswith('GitHub API request failed:'):
                raise
        else:
            require(type(pr) is dict and type(pr.get('number')) is int and pr['number'] == receipt['pull_request'] and pr.get('merged') is True and pr.get('merge_commit_sha') == receipt['merge_sha'], 'retained time PR identity differs')
            base = pr.get('base'); base_repo = base.get('repo') if type(base) is dict else None
            require(type(base_repo) is dict and type(base_repo.get('id')) is int and base_repo['id'] == anchor['repository_id'] and base_repo.get('full_name') == api.repo, 'retained time base repository differs')
            value = pr.get('merged_at')
            if value is None:
                result['reason'] = 'merge-time-missing'
            else:
                require(type(value) is str and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})', value) is not None, 'retained merge timestamp precision/format invalid')
                require(value.endswith('Z') or (int(value[-5:-3]) < 24 and int(value[-2:]) < 60), 'retained merge timestamp offset invalid')
                try:
                    merged_at = instant(value).astimezone(datetime.timezone.utc)
                except (ValueError, OverflowError) as error:
                    raise ValueError('retained merge timestamp invalid') from error
                require(merged_at <= datetime.datetime.now(datetime.timezone.utc), 'retained merge timestamp future')
                fact = {'repository': api.repo, 'repository_id': anchor['repository_id'], 'run_id': run_id, 'attempt': attempt, 'record_sha256': retained['record_sha256'], 'pr': receipt['pull_request'], 'merge_sha': receipt['merge_sha'], 'merged_at': merged_at.isoformat(timespec='microseconds').replace('+00:00', 'Z')}
                result = {'status': 'observed', 'fact': fact, 'coverage_complete': False}
    return result


def reconstruct_interval(state_api, policy, db_path, trust_path, store, approval_path, stream, *, interval_end, history_head, campaign, interval_scoped=False):
    """Rebuild a bounded frozen interval from protected stages, never SQLite cursors.

    Every retained proof and current trust annotation is checked before SQL writes.
    projection_complete is not discovery/global coverage or current-task credit.
    Larger requested sets fail explicitly at unchanged per-invocation budgets.
    Unscanned suffixes require authenticated protected origin progress. No database-dump or SQL payload is accepted.
    """
    import sqlite3
    require(state_paths.valid_hash(campaign, 64) and state_paths.valid_hash(history_head, 40), 'reconstruction selector differs')
    root = 'repos/'+state_api.repo; calls = consumed = cached_bytes = 0; cache = {}; fresh_prs = {}
    class ReadOnly:
        repo = state_api.repo
        def request(self, path, method='GET', payload=None):
            nonlocal calls, consumed, cached_bytes
            require(method == 'GET' and payload is None and (path == root or path.startswith(root+'/')), 'reconstruction foreign API or write')
            if path in fresh_prs:return document(fresh_prs[path])
            immutable = any(path.startswith(root+'/git/'+kind+'/') and state_paths.valid_hash(path.rsplit('/', 1)[1], 40) for kind in ('commits', 'trees', 'blobs'))
            if immutable and path in cache:
                return document(cache[path])
            require(calls < 2048, 'reconstruction API capacity gap'); calls += 1
            value = state_api.request(path, method, payload); encoded = canonical(value); consumed += len(encoded)
            require(len(encoded) <= 2097152 and consumed <= 33554432, 'reconstruction observation capacity gap')
            if immutable:
                require(cached_bytes+len(encoded) <= 33554432, 'reconstruction normalized cache capacity gap')
                cached_bytes += len(encoded); cache[path] = encoded
            return value
        def prefetch_blobs(self, entries):
            nonlocal calls, consumed, cached_bytes
            transport = getattr(state_api, 'read_blobs', None)
            if not callable(transport):
                return  # Original bounded REST remains available for small callers.
            selected = {}
            for item in entries:
                state_paths.validate_entry(item)
                require(item['type'] == 'blob' and item['path'].startswith('receipt-archive/'), 'reconstruction batch leaf differs')
                key = root+'/git/blobs/'+item['sha']
                if key not in cache:
                    descriptor = {field:item[field] for field in ('path','sha','size')}
                    require(item['sha'] not in selected or selected[item['sha']]['size'] == item['size'], 'reconstruction batch size differs')
                    selected[item['sha']] = descriptor
            group = []; estimate = 0
            def fetch(items):
                nonlocal calls, consumed, cached_bytes
                require(calls < 2048, 'reconstruction API capacity gap'); calls += 1
                result = transport(anchor['repository_id'], items)
                require(type(result) is dict and set(result) == {'blobs','calls','raw_bytes'} and type(result['calls']) is int and result['calls'] == 1 and type(result['raw_bytes']) is int and 0 < result['raw_bytes'] <= 2097152 and type(result['blobs']) is dict and set(result['blobs']) == {item['sha'] for item in items}, 'reconstruction batch response differs')
                consumed += result['raw_bytes']
                require(consumed <= 33554432, 'reconstruction observation capacity gap')
                prepared = {}
                for item in items:
                    value = result['blobs'][item['sha']]
                    require(type(value) is dict and set(value) == {'sha','encoding','size','content'} and value['sha'] == item['sha'] and value['encoding'] == 'base64' and type(value['size']) is int and value['size'] == item['size'] and type(value['content']) is str and len(value['content']) <= 1398104, 'reconstruction batch object differs')
                    raw = base64.b64decode(value['content'], validate=True)
                    require(len(raw) == item['size'] and hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest() == item['sha'], 'reconstruction batch bytes differ')
                    prepared[root+'/git/blobs/'+item['sha']] = canonical(value)
                extra = sum(map(len,prepared.values()))
                require(cached_bytes+extra <= 33554432, 'reconstruction normalized cache capacity gap')
                cache.update(prepared); cached_bytes += extra
            for item in selected.values():
                size = item['size']*2+512
                if size > 1900000:
                    continue  # Plan an individually bounded REST read before any batch call.
                if group and (len(group) == 32 or estimate+size > 1900000):
                    fetch(group); group = []; estimate = 0
                group.append(item); estimate += size
            if group:
                fetch(group)

        def prefetch_pull_requests(self, numbers):
            nonlocal calls, consumed, cached_bytes
            transport=getattr(state_api,'read_pull_requests',None)
            if not callable(transport):return
            selected=sorted(set(numbers))
            require(all(type(number) is int and 0<number<=2147483647 for number in selected),'reconstruction PR selector invalid')
            for start in range(0,len(selected),32):
                group=selected[start:start+32]
                require(calls<2048,'reconstruction API capacity gap');calls+=1
                value=transport(anchor['repository_id'],group)
                require(type(value) is dict and set(value)=={'pull_requests','calls','raw_bytes'} and type(value['calls']) is int and value['calls']==1 and type(value['raw_bytes']) is int and 0<value['raw_bytes']<=2097152 and type(value['pull_requests']) is dict and all(type(key) is int for key in value['pull_requests']) and set(value['pull_requests'])==set(group),'reconstruction PR batch response differs')
                consumed+=value['raw_bytes'];require(consumed<=33554432,'reconstruction observation capacity gap')
                prepared={}
                for number in group:
                    pr=value['pull_requests'][number]
                    require(type(pr) is dict and set(pr)=={'number','merged','merged_at','merge_commit_sha','base'} and type(pr['number']) is int and pr['number']==number and pr['merged'] is True and state_paths.valid_hash(pr['merge_commit_sha'],40) and (pr['merged_at'] is None or type(pr['merged_at']) is str and len(pr['merged_at'])<=40),'reconstruction PR observation differs')
                    base=pr['base'];require(type(base) is dict and set(base)=={'repo'} and type(base['repo']) is dict and set(base['repo'])=={'id','full_name'} and type(base['repo']['id']) is int and base['repo']['id']==anchor['repository_id'] and base['repo']['full_name']==api.repo,'reconstruction PR base differs')
                    prepared[root+'/pulls/'+str(number)]=canonical(pr)
                extra=sum(map(len,prepared.values()));require(cached_bytes+extra<=33554432,'reconstruction normalized observation capacity gap')
                fresh_prs.update(prepared);cached_bytes+=extra

    api = ReadOnly(); anchor = verify_bootstrap(api, approval_path)
    approval_raw = Path(approval_path).read_bytes(); trust_hash = digest(Path(trust_path).read_bytes())
    windows = {}; page = 1; previous_blob = None
    while True:
        lineage = projection_lineage(api, policy, trust_path, store, approval_path, stream, interval_end=interval_end, history_head=history_head, page=page, limit=32, interval_scoped=interval_scoped)
        for window in lineage['windows']:
            require(window['publication_sha'] not in windows, 'reconstruction duplicate publication')
            if windows:
                require(window['blob_sha'] == previous_blob, 'reconstruction cross-page publication continuity differs')
            previous_blob = window['checkpoint']['previous_blob']
            windows[window['publication_sha']] = window
        if lineage['reaches_start']:
            break
        if not lineage['windows']:
            return {'projection_complete': False, 'coverage_complete': False, 'reason': 'required-lineage-gap'}
        page += 1
    require(bool(windows), 'reconstruction lineage missing')
    first = next(iter(windows.values()))['checkpoint']; count = first['records_count']
    if first['next_segment'] != count:
        return {'projection_complete': False, 'coverage_complete': False, 'reason': 'checkpoint-incomplete'}
    require(all(w['checkpoint'][key] == first[key] for w in windows.values() for key in ('frozen_head', 'frozen_tree', 'records_count')), 'reconstruction frozen campaign differs')
    prefix = 'receipt-archive/stages/'+campaign; item_at, blob_at = fixed_reader(api, root)
    require(item_at(anchor['bootstrap_tree'], prefix) is None, 'reconstruction copied pre-bootstrap stages')
    directory = item_at(anchor['tree'], prefix)
    if count == 0:
        expected_campaign = digest(canonical(dict(first['binding'], frozen_head=first['frozen_head'], frozen_tree=first['frozen_tree'], trust_sha256=trust_hash)))
        require(campaign == expected_campaign and directory is None and all(w['checkpoint']['window'] == dict(w['checkpoint']['window'],start=0,stop=0,references=[]) for w in windows.values()), 'reconstruction empty campaign differs')
        receipts.load_receipt_trust(trust_path, api.repo, mode='report')
        empty = projection_window(api, policy, trust_path, store, approval_path, stream, interval_end=interval_end, start=0, limit=1, frozen_head=first['frozen_head'], _empty_origin=True)
        require(empty['records_count'] == 0 and not empty['references'], 'reconstruction empty retained snapshot differs')
    elif directory is None:
        return {'projection_complete': False, 'coverage_complete': False, 'reason': 'required-stages-gap'}
    documents = {}
    def entries(tree, path):
        value = api.request(root+'/git/trees/'+tree)
        require(value.get('sha') == tree and value.get('truncated') is False and type(value.get('tree')) is list, 'reconstruction stage directory incomplete')
        rows = [dict(item, path=path+'/'+item['path']) for item in value['tree']]
        state_paths.validate_tree(rows)
        return rows
    require(directory is None or directory['type'] == 'tree', 'reconstruction stage directory differs')
    stage_entries = []; seen_stage_paths = set()
    for shard in (entries(directory['sha'], prefix) if directory is not None else []):
        require(shard['type'] == 'tree', 'reconstruction stage shard differs')
        for item in entries(shard['sha'], shard['path']):
            require(item['type'] == 'blob' and item['path'] not in seen_stage_paths, 'reconstruction duplicate or nested stage')
            seen_stage_paths.add(item['path']); stage_entries.append(item)
    api.prefetch_blobs(stage_entries)
    for item in stage_entries:
        documents[item['path']] = document(blob_at(anchor['tree'], item['path']))
    references = {row['segment']:row for window in windows.values() for row in window['checkpoint']['window']['references']}
    retained_entries = []; record_paths = set()
    for number, reference in references.items():
        identity = digest(canonical({'repository':api.repo,'stream':stream,'run_id':reference['run_id'],'attempt':reference['attempt']}))
        key = reference['record_sha256']; path = f'receipt-archive/objects/{key[:2]}/{key}.json'; record_paths.add(path)
        for name in (state_paths.segment_path(stream,number),f'receipt-archive/index/{stream}/identities/{identity[:2]}/{identity}.json',path):
            item = item_at(anchor['tree'],name); require(item is not None, 'reconstruction required retained leaf missing'); retained_entries.append(item)
    api.prefetch_blobs(retained_entries)
    materials = set()
    for path in record_paths:
        record = document(blob_at(anchor['tree'],path)); links = record.get('materials') if type(record) is dict else None
        require(type(links) is dict and len(links) <= 10 and all(state_paths.valid_hash(key,64) for key in links.values()), 'reconstruction retained material links differ')
        materials.update(links.values())
    material_entries = []
    for key in materials:
        item = item_at(anchor['tree'],f'receipt-archive/materials/{key[:2]}/{key}.json'); require(item is not None, 'reconstruction required material missing'); material_entries.append(item)
    api.prefetch_blobs(material_entries)
    numbers=[]
    for path in record_paths:
        record=document(blob_at(anchor['tree'],path));proof=record.get('proof') if type(record) is dict else None
        require(type(proof) is dict and type(proof.get('provenance')) is str,'reconstruction retained PR source differs')
        provenance=document(proof['provenance']);receipt=provenance.get('receipt') if type(provenance) is dict else None
        require(type(receipt) is dict and type(receipt.get('pull_request')) is int and 0<receipt['pull_request']<=2147483647,'reconstruction retained PR selector differs')
        numbers.append(receipt['pull_request'])
    api.prefetch_pull_requests(numbers)
    facts = {}; by_task = {}; expected_indices = {}; covered = set()
    for path, stage in documents.items():
        require(type(stage) is dict, 'reconstruction stage JSON differs')
        if 'kind' in stage:
            continue
        require(set(stage) == {'schema_version','binding','publication_sha','checkpoint_blob','offset','stop','facts'} and type(stage['schema_version']) is int and stage['schema_version'] == 1, 'reconstruction stage schema differs')
        require(stage['publication_sha'] in windows, 'reconstruction foreign publication')
        window = windows[stage['publication_sha']]; checkpoint = window['checkpoint']; binding = stage['binding']
        require(type(binding) is dict and state_paths.valid_hash(binding.get('trust_sha256'), 64), 'reconstruction trust binding differs')
        expected_binding = dict(checkpoint['binding'], frozen_head=checkpoint['frozen_head'], frozen_tree=checkpoint['frozen_tree'], trust_sha256=binding['trust_sha256'])
        require(canonical(binding) == canonical(expected_binding) and digest(canonical(binding)) == campaign and stage['checkpoint_blob'] == window['blob_sha'], 'reconstruction protected campaign differs')
        start, stop = stage['offset'], stage['stop']; references = checkpoint['window']['references']
        require(type(start) is int and type(stop) is int and 0 <= start < stop <= len(references) and stop-start <= 8 and type(stage['facts']) is list and len(stage['facts']) == stop-start, 'reconstruction stage slice differs')
        def path_for(kind, identity):
            key = digest(canonical([kind, identity])); return prefix+'/'+key[:2]+'/'+key+'.json'
        require(path in {path_for('window', [stage['publication_sha'], start, limit]) for limit in range(stop-start, 9) if min(start+limit,len(references)) == stop}, 'reconstruction window path differs')
        actual = []
        for reference in references[start:stop]:
            number = reference['segment']; execution = (reference['run_id'], reference['attempt'])
            timed = _retained_time_from_anchor(api, anchor, store, stream, *execution)
            if timed['status'] != 'observed':
                return {'projection_complete': False, 'coverage_complete': False, 'reason': timed['reason']}
            retained = retained_execution(api, anchor, store, stream, *execution)
            require(retained['record_sha256'] == reference['record_sha256'] and retained['record']['artifact']['id'] == reference['artifact_id'], 'reconstruction retained reference differs')
            proof = receipts.annotate_reported_trust(retained['record']['proof'], trust_path, api.repo)
            fact = dict(timed['fact'], artifact_id=reference['artifact_id'], tasks=proof['tasks'], segment=number)
            actual.append(fact)
            if number in covered or execution in facts:
                require(execution in facts and canonical(facts[execution]) == canonical(fact), 'reconstruction conflicting duplicate stage reference')
                continue
            facts[execution] = fact; covered.add(number)
            for task in proof['tasks']:
                require(task not in by_task, 'reconstruction conflicting task')
                by_task[task] = (proof, fact['merged_at'])
            for kind, identities in (('execution',[list(execution)]),('task',proof['tasks'])):
                for identity in identities:
                    index = {'schema_version':1,'campaign':campaign,'kind':kind,'identity':identity,'run_id':execution[0],'attempt':execution[1],'record_sha256':reference['record_sha256']}
                    key = path_for(kind,identity)
                    require(key not in expected_indices, 'reconstruction conflicting index')
                    expected_indices[key] = index
        require(canonical(stage['facts']) == canonical(actual), 'reconstruction staged facts differ')
    if len(covered) != count or (covered and (min(covered) != 0 or max(covered) != count-1)):
        return {'projection_complete': False, 'coverage_complete': False, 'reason': 'required-reference-gap'}
    indices = {path:value for path,value in documents.items() if 'kind' in value}
    require(set(indices) == set(expected_indices) and all(canonical(indices[key]) == canonical(value) for key,value in expected_indices.items()), 'reconstruction global indices differ')
    require(verify_bootstrap(api, approval_path) == anchor and Path(approval_path).read_bytes() == approval_raw and digest(Path(trust_path).read_bytes()) == trust_hash, 'reconstruction protected origin changed')
    definitions = {'delivery_receipts':'task TEXT PRIMARY KEY, revision TEXT NOT NULL, receipt TEXT NOT NULL','delivery_provenance':'task TEXT PRIMARY KEY, provenance TEXT NOT NULL','delivery_trust':'task TEXT PRIMARY KEY, status TEXT NOT NULL','delivery_times':'task TEXT PRIMARY KEY, merged_at TEXT NOT NULL','delivery_interval':'task TEXT PRIMARY KEY'}
    lower, upper = instant(anchor['coverage_from']), instant(interval_end)
    interval_tasks = {task for task,(_,time) in by_task.items() if lower <= instant(time) <= upper}
    with sqlite3.connect(db_path) as db:
        for kind,name,sql in db.execute('SELECT type,name,sql FROM sqlite_master'):
            if kind == 'index' and sql is None and any(name == 'sqlite_autoindex_'+table+'_1' for table in definitions):
                continue
            require(kind == 'table' and name in definitions and sql == 'CREATE TABLE '+name+'('+definitions[name]+')', 'reconstruction foreign SQLite schema')
        db.execute('BEGIN IMMEDIATE')
        for table,columns in definitions.items():
            db.execute('CREATE TABLE IF NOT EXISTS '+table+'('+columns+')')
        for table in definitions:
            rows = db.execute('SELECT count(*) FROM '+table).fetchone()[0]
            require(rows <= len(by_task), 'reconstruction SQLite row bound')
            require({row[0] for row in db.execute('SELECT task FROM '+table)} <= set(by_task), 'reconstruction SQLite rows lack required proof')
        require({row[0] for row in db.execute('SELECT task FROM delivery_receipts')} <= set(by_task), 'reconstruction existing fact lacks required proof')
        require({row[0] for row in db.execute('SELECT task FROM delivery_provenance')} == {row[0] for row in db.execute('SELECT task FROM delivery_receipts')}, 'reconstruction orphan provenance')
        for task,(proof,time) in by_task.items():
            previous = db.execute('SELECT revision,receipt FROM delivery_receipts WHERE task=?',(task,)).fetchone()
            provenance = db.execute('SELECT provenance FROM delivery_provenance WHERE task=?',(task,)).fetchone()
            previous_time = db.execute('SELECT merged_at FROM delivery_times WHERE task=?',(task,)).fetchone()
            require(previous is None or (previous == (proof['revision'],proof['delivery']) and provenance == (proof['provenance'],)), 'reconstruction conflicting SQLite fact')
            require(previous_time is None or previous_time == (time,), 'reconstruction conflicting SQLite time')
            db.execute('INSERT OR IGNORE INTO delivery_receipts VALUES(?,?,?)',(task,proof['revision'],proof['delivery']))
            db.execute('INSERT OR IGNORE INTO delivery_provenance VALUES(?,?)',(task,proof['provenance']))
            db.execute('INSERT OR IGNORE INTO delivery_times VALUES(?,?)',(task,time))
            db.execute('INSERT INTO delivery_trust VALUES(?,?) ON CONFLICT(task) DO UPDATE SET status=excluded.status',(task,proof['trust_status']))
        db.execute('DELETE FROM delivery_interval')
        db.executemany('INSERT INTO delivery_interval VALUES(?)',[(task,) for task in sorted(interval_tasks)])
    return {'projection_complete':True,'coverage_complete':False,'facts_count':len(by_task),'interval_facts_count':len(interval_tasks),'frozen_head':first['frozen_head'],'suffix_pending':True}
