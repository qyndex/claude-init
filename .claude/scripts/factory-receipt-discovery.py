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


def _checkpoint_ancestor(read, root, base, head):
    """Request compare metadata without the first-page file/patch payload."""
    archive._origin_ancestor(read, root, base, head)


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


class DiscoveryBudgetError(ValueError):
    """Own discovery capacity failure must never become a soft proof outcome."""


def _source_fetch_unavailable(error):
    """Known transport/source absence only; identity, parse and budget errors escape."""
    message = str(error)
    return message.startswith('GitHub API request failed:') or message in {
        'reporting API failed; reconcile authoritative state before retry',
        'reporting source unavailable', 'trusted source unavailable',
        'receipt source size exceeds bound'}


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
        if not _source_fetch_unavailable(error):raise
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
        if _source_fetch_unavailable(error):
            value['reason'] = 'unavailable'; return value, latest
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
    except DiscoveryBudgetError:
        raise
    except ValueError:
        value['reason'] = 'proof-unavailable'; return value, latest
    raise ArchiveAdvanced()  # Re-read the actual archive head, then use its retained index first.


def backfill_page(source_api, anchor, policy, stream, interval_end, page_size, blob_at, *, interval_scoped=False):
    """Pure bounded partition step; caller must authenticate protected blob origin.

    Only _checkpoint publishes changes. Listing facts alone never prove delivery
    or grant trust to a supplied JSON blob/hash.
    """
    from datetime import datetime, timezone
    def second(value):
        point = archive.instant(value)
        require(point.microsecond == 0 and point.timestamp() >= 0, 'backfill boundary requires exact seconds')
        return int(point.timestamp())
    def stamp(value):
        return datetime.fromtimestamp(value, timezone.utc).isoformat().replace('+00:00', 'Z')
    low = second(anchor['coverage_from']); high = second(interval_end)
    require(low <= high <= int(datetime.now(timezone.utc).timestamp()) and type(page_size) is int
            and 0 < page_size <= 100, 'backfill interval/page bound invalid')
    workflow = policy['receipts']['workflow_id']; root = 'repos/'+anchor['repository']
    require(source_api.repo == anchor['repository'] == policy['repository']
            and stream == archive.archive_stream(anchor['repository']), 'backfill repository/stream differs')
    scope=archive.interval_scope(anchor,stream,interval_end,interval_scoped)
    path = 'receipt-archive/backfill/'+scope+'.json'
    require(blob_at(anchor['bootstrap_tree'], path) is None, 'backfill pre-bootstrap manifest requires explicit reviewed import')
    raw = blob_at(anchor['tree'], path)
    expected = {'schema_version': 1, 'repository': anchor['repository'], 'stream': stream,
                'binding': binding(anchor), 'workflow_id': workflow, 'source_branch': policy['base_branch'], 'page_size': page_size,
                'interval_start': stamp(low), 'interval_end': stamp(high)}
    if raw is None:
        manifest = dict(expected, stack=[[low, high]], epoch=0, rounds_observed=0,
                        round_gaps=0, last_round_gaps=0, coverage_complete=False)
    else:
        manifest = archive.document(raw)
        require(type(manifest) is dict and manifest.keys() == expected.keys() | {'stack', 'epoch', 'rounds_observed', 'round_gaps', 'last_round_gaps', 'coverage_complete'}
                and all(manifest[key] == value and type(manifest[key]) is type(value) for key, value in expected.items())
                and manifest['coverage_complete'] is False, 'backfill protected campaign binding differs')
        require(all(type(manifest[key]) is int and 0 <= manifest[key] < 10**12 for key in ('epoch', 'rounds_observed', 'round_gaps', 'last_round_gaps'))
                and type(manifest['stack']) is list and 0 < len(manifest['stack']) <= 64
                and all(type(part) is list and len(part) == 2 and all(type(n) is int for n in part)
                        and low <= part[0] <= part[1] <= high for part in manifest['stack']), 'backfill frontier malformed')
    lo, hi = manifest['stack'][-1]
    identity = archive.digest(archive.canonical([expected, lo, hi]))
    part_path = f'receipt-archive/backfill/{scope}/{identity[:2]}/{identity}.json'
    require(blob_at(anchor['bootstrap_tree'], part_path) is None, 'backfill pre-bootstrap partition requires explicit reviewed import')
    raw = blob_at(anchor['tree'], part_path)
    part_binding = {'schema_version': 1, 'campaign_sha256': archive.digest(archive.canonical(expected)), 'lo': lo, 'hi': hi}
    if raw is None:
        node = dict(part_binding, epoch=manifest['epoch'], phase='paging', page=1,
                    expected_count=None, seen=[], facts=[], reason=None, observation=None)
    else:
        node = archive.document(raw)
        require(type(node) is dict and node.keys() == part_binding.keys() | {'epoch', 'phase', 'page', 'expected_count', 'seen', 'facts', 'reason', 'observation'}
                and all(node[key] == value and type(node[key]) is type(value) for key, value in part_binding.items())
                and type(node['epoch']) is int and 0 <= node['epoch'] <= manifest['epoch']
                and node['phase'] in ('paging', 'confirm', 'split', 'observed', 'gap')
                and type(node['page']) is int and 0 < node['page'] <= 1001
                and (node['expected_count'] is None or type(node['expected_count']) is int and 0 <= node['expected_count'] < 10**12)
                and type(node['seen']) is list and len(node['seen']) <= 999
                and type(node['facts']) is list and len(node['facts']) <= 1000
                and node['reason'] in (None, 'dense-second', 'unavailable', 'count-drift', 'row-count', 'duplicate-identity', 'confirmation-changed'), 'backfill partition malformed')
        identities = set()
        for row in node['seen']:
            require(type(row) is dict and row.keys() == {'run_id', 'attempt', 'source_sha', 'created_at'}
                    and all(type(row[key]) is int and row[key] > 0 for key in ('run_id', 'attempt'))
                    and row['run_id'] not in identities and archive.state_paths.valid_hash(row['source_sha'], 40)
                    and lo <= second(row['created_at']) <= hi, 'backfill retained identity malformed')
            identities.add(row['run_id'])
        for number, fact in enumerate(node['facts'], 1):
            require(type(fact) is dict and fact.keys() == {'page', 'total_count', 'rows_sha256', 'rows_count'}
                    and type(fact['page']) is int and fact['page'] == number
                    and type(fact['total_count']) is int and 0 <= fact['total_count'] < 10**12
                    and type(fact['rows_count']) is int and 0 <= fact['rows_count'] <= page_size
                    and archive.state_paths.valid_hash(fact['rows_sha256'], 64), 'backfill page facts malformed')
        require(node['page'] == len(node['facts'])+1, 'backfill retained page cursor differs')
        offset = 0
        for fact in node['facts']:
            retained = node['seen'][offset:offset+fact['rows_count']]; offset += fact['rows_count']
            require(fact['total_count'] == node['expected_count']
                    and archive.digest(archive.canonical(retained)) == fact['rows_sha256'], 'backfill retained page identities differ')
        require(offset == len(node['seen']), 'backfill retained unique count differs')
        if node['phase'] in ('confirm', 'observed'):
            require(type(node['expected_count']) is int and node['expected_count'] < 1000
                    and len(node['seen']) == node['expected_count'], 'backfill retained completion count differs')
        if node['phase'] == 'split':
            require(lo < hi and type(node['expected_count']) is int and node['expected_count'] >= 1000
                    and len(node['facts']) == 1, 'backfill retained split differs')
        observation = node['observation']
        require(observation is None or type(observation) is dict and observation.keys() == {'page', 'total_count', 'rows_sha256', 'rows_count'}
                and type(observation['page']) is int and 0 < observation['page'] <= 1001
                and type(observation['total_count']) is int and 0 <= observation['total_count'] < 10**12
                and type(observation['rows_count']) is int and 0 <= observation['rows_count'] <= page_size
                and archive.state_paths.valid_hash(observation['rows_sha256'], 64), 'backfill last observation malformed')
        if node['epoch'] != manifest['epoch'] or node['phase'] in ('split', 'observed', 'gap'):
            # Revisit preserves known watches and immutable Git history, not a new origin.
            node = dict(part_binding, epoch=manifest['epoch'], phase='paging', page=1,
                        expected_count=None, seen=[], facts=[], reason=None, observation=None)
    query_page = 1 if node['phase'] == 'confirm' else node['page']
    target = f'{root}/actions/workflows/{workflow}/runs?branch={quote(policy['base_branch'], safe="")}&created={quote(stamp(lo)+".."+stamp(hi), safe="")}&per_page={page_size}&page={query_page}'
    response = None
    try:
        response = source_api.request(target)
    except (RuntimeError, OSError):
        node.update(phase='gap', reason='unavailable')
    except ValueError as error:
        if not str(error).startswith('GitHub API request failed:'):
            raise
        node.update(phase='gap', reason='unavailable')
    rows = []; facts = []
    if response is not None:
        require(type(response) is dict and type(response.get('total_count')) is int and 0 <= response['total_count'] < 10**12
                and type(response.get('workflow_runs')) is list and len(response['workflow_runs']) <= page_size, 'backfill source page malformed')
        count = response['total_count']
        for run in response['workflow_runs']:
            run_identity(run, anchor, policy)
            require(lo <= second(run['created_at']) <= hi, 'backfill run outside created partition')
            facts.append({'run_id': run['id'], 'attempt': run['run_attempt'], 'source_sha': run['head_sha'], 'created_at': run['created_at']})
        fact = {'page': query_page, 'total_count': count, 'rows_sha256': archive.digest(archive.canonical(facts)), 'rows_count': len(facts)}
        node['observation'] = fact
        duplicate = len({row['run_id'] for row in facts}) != len(facts)
        if duplicate:
            node.update(phase='gap', reason='duplicate-identity')
        elif node['phase'] == 'confirm':
            if node['expected_count'] != count or not node['facts'] or fact != node['facts'][0]:
                node.update(phase='gap', reason='confirmation-changed')
            else:
                node['phase'] = 'observed'
        elif node['expected_count'] is not None and node['expected_count'] != count:
            node.update(phase='gap', reason='count-drift')
        elif count >= 1000:
            # Only a first-page observation can begin a saturated partition.
            node.update(expected_count=count, facts=[fact], page=2, seen=facts)
            node.update(phase='gap' if lo == hi else 'split', reason='dense-second' if lo == hi else None)
        elif len(facts) != min(page_size, max(0, count-(query_page-1)*page_size)):
            node.update(phase='gap', reason='row-count')
        elif duplicate or {row['run_id'] for row in facts} & {row['run_id'] for row in node['seen']}:
            node.update(phase='gap', reason='duplicate-identity')
        else:
            node['expected_count'] = count; node['facts'].append(fact); node['seen'].extend(facts); node['page'] += 1
            if len(node['seen']) == count:
                node['phase'] = 'confirm'
        if duplicate:
            node.update(phase='gap', reason='duplicate-identity')
        if node['phase'] != 'gap':
            rows = response['workflow_runs']
    if node['phase'] in ('split', 'observed', 'gap'):
        manifest['stack'].pop()
        if node['phase'] == 'split':
            mid = (lo+hi)//2
            children = [[lo, mid], [mid if hi-lo > 1 else hi, hi]]
            manifest['stack'].extend(reversed(children))
        elif node['phase'] == 'gap':
            manifest['round_gaps'] += 1
        if not manifest['stack']:
            manifest.update(epoch=manifest['epoch']+1, rounds_observed=manifest['rounds_observed']+1,
                            last_round_gaps=manifest['round_gaps'], round_gaps=0, stack=[[low, high]])
    require(len(manifest['stack']) <= 64, 'backfill partition frontier capacity gap')
    changes = {path: archive.canonical(manifest), part_path: archive.canonical(node)}
    require(all(len(raw) <= archive.MAX_OBJECT for raw in changes.values()), 'backfill object capacity gap')
    return rows, changes, {'epoch': manifest['epoch'], 'rounds_observed': manifest['rounds_observed'],
                           'last_round_gaps': manifest['last_round_gaps'], 'partition_phase': node['phase'], 'coverage_complete': False}


def _checkpoint(source_api, state_api, policy, approval_path, stream, *, page_size=10, tree_pages=1, review_rows=4, mode='discover', trust_path=None, trust_mode='profile', store=None, backfill_end=None, interval_scoped=False):
    """Read actual protected progress, advance one bounded page/scan and CAS atomically.

    Only checked scanner output is persisted. No caller checkpoint/cursor input is
    accepted. Shared bootstrap verification authenticates completed scanner
    publications plus every fresh suffix; a checkpoint hash alone grants nothing.
    """
    require(source_api.repo == state_api.repo == policy['repository'] and stream == archive.archive_stream(state_api.repo), 'foreign discovery repository/stream')
    require(type(page_size) is int and 0 < page_size <= 100 and type(tree_pages) is int and 0 < tree_pages <= 10, 'discovery invocation budget invalid')
    require(mode in ('discover', 'review', 'backfill') and type(review_rows) is int and 0 < review_rows <= 16, 'discovery review budget invalid')
    source_page_size = page_size
    if mode == 'backfill':
        page_size = 10  # Existing discovery page identity is independent of query partition size.
        require(backfill_end is not None, 'protected backfill end required')
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
        if not (size <= 2097152 and consumed <= 33554432):
            raise DiscoveryBudgetError('discovery observation budget exceeded; explicit coverage gap')
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
            if calls >= 4096:
                raise DiscoveryBudgetError('discovery invocation API call budget reached; explicit coverage gap')
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
        if calls >= 4096:
            raise DiscoveryBudgetError('reconciliation API call budget reached; explicit coverage gap')
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
            require(mode in ('discover', 'backfill'), 'protected discovery checkpoint missing before reconciliation')
            progress = {'schema_version': 3, 'stream': stream, 'binding': binding(anchor), 'anchor': {'head': anchor['head'], 'tree': anchor['tree']},
                        'scan': {'head': anchor['head'], 'tree': anchor['tree'], 'cursor': None, 'complete': True},
                        'pagination': {'workflow_id': workflow, 'page_size': page_size, 'next_page': 1, 'overlap_page': 1, 'overlap_until': 1}, 'watch': {'segments': 0, 'count': 0}, 'review': {'segment': 0, 'row': 0}, 'coverage_complete': False}
            cursor = None
        else:
            if mode in ('review', 'backfill'):
                page_size = archive.document(raw)['pagination']['page_size']
            progress = validate_checkpoint(archive.document(raw), anchor, workflow, page_size)
            frozen = api.request(root+'/git/commits/'+progress['scan']['head'])
            require(frozen.get('sha') == progress['scan']['head'] and frozen['tree']['sha'] == progress['scan']['tree'], 'discovery frozen commit/tree differs')
            # The saved checkpoint was read from the authenticated protected chain;
            # verify its previously observed anchor is actually on that same chain.
            require(progress['anchor']['head'] != progress['scan']['head'] or progress['anchor']['tree'] == progress['scan']['tree'], 'discovery saved anchor/frozen tree differs')
            required = {progress['anchor']['head']: progress['anchor']['tree'], progress['scan']['head']: progress['scan']['tree']}
            # The shared origin verifier already checked every single-parent
            # inert edge to this current head. Compare only links the retained
            # source frames into that checked history; it grants no origin alone.
            for sha, expected_tree in required.items():
                commit = api.request(root+'/git/commits/'+sha)
                require(commit.get('sha') == sha and commit['tree']['sha'] == expected_tree, 'discovery retained anchor tree differs')
                _checkpoint_ancestor(api.request, root, anchor['bootstrap_sha'], sha)
                _checkpoint_ancestor(api.request, root, sha, anchor['head'])
            cursor = progress['scan']['cursor']
        if raw is None or not progress['scan']['complete']:
            scan = archive.state_paths.scan_tree(api, root, progress['scan']['tree'], cursor=cursor, page_budget=tree_pages)
            progress['scan'].update(cursor=scan['cursor'], complete=scan['complete'])
        page = progress['pagination']['next_page']; changes = {}
        if mode == 'backfill':
            rows, observations, _ = backfill_page(source_api, anchor, policy, stream, backfill_end, source_page_size, blob_at, interval_scoped=interval_scoped)
            changes.update(observations)
            response = {'workflow_runs': rows}
        elif mode == 'discover':
            target = f'{root}/actions/workflows/{workflow}/runs?per_page={page_size}&page={page}'
            response = charge(source_api.request(target))
            pages = [response]
            if page > 1:
                overlap = progress['pagination']['overlap_page']
                # Alternate head and older overlap within the two-page budget.
                if page % 2:
                    pages.append(source_api.request(f'{root}/actions/workflows/{workflow}/runs?per_page={page_size}&page=1'))
                elif overlap != page:
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
            primary_short = len(pages[0]['workflow_runs']) < page_size
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
                    if observed is not None:
                        latest[(observed['id'], observed['run_attempt'])] = observed
                        # Follow one predecessor per reviewed row. The protected
                        # watch itself resumes a long rerun chain across calls.
                        prior = row['attempt']-1
                        if prior > 0:
                            identity = watch_identity(api.repo, stream, row['run_id'], prior)
                            lookup = f'receipt-archive/pending/{stream}/identities/{identity[:2]}/{identity}.json'
                            occupied = blob_at(anchor['tree'], lookup)
                            if occupied is not None:
                                saved = archive.document(occupied)
                                require(type(saved) is dict and set(saved) == {'schema_version', 'repository', 'stream', 'run_id', 'attempt', 'source_sha', 'segment'} and type(saved['schema_version']) is int and saved['schema_version'] == 1 and saved['repository'] == api.repo and saved['stream'] == stream and type(saved['run_id']) is int and saved['run_id'] == row['run_id'] and type(saved['attempt']) is int and saved['attempt'] == prior and saved['source_sha'] == row['source_sha'] and type(saved['segment']) is int and 0 <= saved['segment'] < progress['watch']['segments'], 'prior attempt pending identity differs')
                                retained_raw = blob_at(anchor['tree'], archive.state_paths.pending_segment_path(stream, saved['segment']))
                                require(retained_raw is not None, 'prior attempt retained watch missing')
                                retained = validate_watch(archive.document(retained_raw), api.repo, stream, saved['segment'])
                                require(sum(item == {'run_id': row['run_id'], 'attempt': prior, 'source_sha': row['source_sha'], 'classification': 'pending'} for item in retained['rows']) == 1, 'prior attempt retained watch differs')
                            else:
                                try:
                                    previous = run_identity(source_api.get(f'repos/{api.repo}/actions/runs/{row["run_id"]}/attempts/{prior}'), anchor, policy)
                                except (RuntimeError, OSError):
                                    previous = None
                                except ValueError as error:
                                    if not _source_fetch_unavailable(error):raise
                                    previous = None
                                if previous is not None:
                                    require((previous['id'], previous['run_attempt'], previous['head_sha']) == (row['run_id'], prior, row['source_sha']), 'prior attempt immutable identity changed')
                                    latest[(previous['id'], previous['run_attempt'])] = previous
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
        if mode == 'discover':
            if primary_short:
                progress['pagination'].update(next_page=1, overlap_page=1, overlap_until=1)
            else:
                progress['pagination']['next_page'] = page+1
        progress['anchor'] = {'head': anchor['head'], 'tree': anchor['tree']}
        validate_checkpoint(progress, anchor, workflow, page_size)
        # Even a short/empty API page is NOT complete history (filtered queries cap
        # at 1,000). Backfill count observations still require retained outcome proofs.
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
        approval = archive.document(Path(approval_path).read_bytes())
        require(archive.digest(archive.canonical(approval)) == anchor['approval_sha256'], 'discovery bootstrap approval changed before checkpoint')
        for identity, expected in anchor['policies'].items():
            require(archive._approved_policy_digest(api.request(root+'/rulesets/'+identity), approval, approval_path) == expected, 'discovery protection changed before checkpoint')
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


def backfill(source_api, state_api, policy, approval_path, stream, *, interval_end, page_size=100, tree_pages=1, interval_scoped=False):
    return _checkpoint(source_api, state_api, policy, approval_path, stream, mode='backfill', backfill_end=interval_end, page_size=page_size, tree_pages=tree_pages, interval_scoped=interval_scoped)


def coverage(source_api, state_api, policy, trust_path, store, approval_path, stream, *, interval_end, projection_end, history_head, campaign, page_size=100, interval_scoped=False):
    """Bounded as-observed requested coverage, never future/all-history authority.

    Durable partition/watch progress is the resume authority. This read-only
    composition may refuse capacity; it never advances a cursor or imports SQL.
    """
    import datetime
    import sqlite3
    import tempfile
    require(source_api.repo == state_api.repo == policy['repository'] == store['repository'] and stream == archive.archive_stream(state_api.repo), 'foreign coverage repository/stream')
    require(type(page_size) is int and 0 < page_size <= 100 and interval_end == projection_end, 'coverage interval/page binding differs')
    root = 'repos/'+state_api.repo; calls = consumed = cached_bytes = 0; cache = {}; source_observations = []; listed_runs = {}
    result = {'source_partition_complete': False, 'frozen_projection_complete': False, 'coverage_complete': False, 'all_history_complete': False, 'task_credit': False, 'gaps': [], 'verified_until': None}
    def gap(reason):
        result['gaps'].append(reason); return result
    def charge(value):
        nonlocal calls, consumed
        calls += 1; size = len(archive.canonical(value)); consumed += size
        require(calls <= 2048 and size <= 2097152 and consumed <= 33554432, 'coverage invocation capacity gap')
        return value
    class State:
        repo = state_api.repo
        def request(self, target, method='GET', payload=None):
            nonlocal cached_bytes
            require(method == 'GET' and payload is None and (target == root or target.startswith(root+'/')), 'coverage state API must be read-only and same repository')
            immutable = any(target.startswith(root+'/git/'+kind+'/') and archive.state_paths.valid_hash(target.rsplit('/',1)[1],40) for kind in ('commits','trees','blobs'))
            if immutable and target in cache:return archive.document(cache[target])
            value = charge(state_api.request(target))
            if immutable:
                encoded=archive.canonical(value);require(cached_bytes+len(encoded)<=33554432,'coverage normalized cache capacity gap')
                cached_bytes+=len(encoded);cache[target]=encoded
            return value
    def read_blobs(repository_id, entries):
        nonlocal calls, consumed, cached_bytes
        require(calls<2048,'coverage invocation capacity gap');calls+=1
        value=state_api.read_blobs(repository_id,entries)
        require(type(value) is dict and set(value)=={'blobs','calls','raw_bytes'} and type(value['calls']) is int and value['calls']==1 and type(value['raw_bytes']) is int and 0<value['raw_bytes']<=2097152 and type(value['blobs']) is dict and set(value['blobs'])=={item['sha'] for item in entries},'coverage batch response differs')
        consumed+=value['raw_bytes'];require(consumed<=33554432,'coverage invocation capacity gap')
        prepared={}
        for item in entries:
            blob=value['blobs'][item['sha']]
            require(type(blob) is dict and set(blob)=={'sha','encoding','size','content'} and blob['sha']==item['sha'] and blob['encoding']=='base64' and type(blob['size']) is int and blob['size']==item['size'] and type(blob['content']) is str and len(blob['content'])<=1398104,'coverage batch object differs')
            raw=base64.b64decode(blob['content'],validate=True)
            require(len(raw)==item['size'] and hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==item['sha'],'coverage batch bytes differ')
            key=root+'/git/blobs/'+item['sha']
            if key not in cache:prepared[key]=archive.canonical(blob)
        extra=sum(map(len,prepared.values()));require(cached_bytes+extra<=33554432,'coverage normalized cache capacity gap')
        cache.update(prepared);cached_bytes+=extra
        return value
    def read_pull_requests(repository_id,numbers):
        nonlocal calls,consumed
        require(calls<2048,'coverage invocation capacity gap');calls+=1
        value=state_api.read_pull_requests(repository_id,numbers)
        require(type(value) is dict and set(value)=={'pull_requests','calls','raw_bytes'} and type(value['calls']) is int and value['calls']==1 and type(value['raw_bytes']) is int and 0<value['raw_bytes']<=2097152 and type(value['pull_requests']) is dict and all(type(key) is int for key in value['pull_requests']) and set(value['pull_requests'])==set(numbers),'coverage PR batch response differs')
        consumed+=value['raw_bytes'];require(consumed<=33554432,'coverage invocation capacity gap')
        return value
    def observe(target, *, detail=False, repeat=False):
        require(target.startswith(root+'/actions/'), 'coverage source endpoint differs')
        value = charge(source_api.get(target) if detail else source_api.request(target))
        if not repeat:source_observations.append((target,detail,archive.canonical(value)))
        return value
    api = State()
    if callable(getattr(state_api,'read_blobs',None)):api.read_blobs=read_blobs
    if callable(getattr(state_api,'read_pull_requests',None)):api.read_pull_requests=read_pull_requests
    approval_raw = Path(approval_path).read_bytes(); trust_raw = Path(trust_path).read_bytes()
    try:
        anchor = archive.verify_bootstrap(api, approval_path)
        require(store == {'repository':api.repo,'visibility':'private' if anchor['private'] else 'public'}, 'coverage store visibility differs')
        result.update(repository=api.repo, observed_head=anchor['head'], coverage_from=anchor['coverage_from'])
        trust = archive.receipts.load_receipt_trust(trust_path, api.repo, mode='report')
        epoch = archive.digest(archive.canonical({'mode':'profile','document':trust}))
        _, blob_at = archive.fixed_reader(api, root)
        def protected(path):
            require(blob_at(anchor['bootstrap_tree'],path) is None, 'coverage pre-bootstrap capsule requires reviewed import')
            raw = blob_at(anchor['tree'],path)
            return archive.document(raw) if raw is not None else None
        def second(value):
            point = archive.instant(value)
            require(point.microsecond == 0 and point.timestamp() >= 0, 'coverage boundary requires exact seconds')
            return int(point.timestamp())
        def stamp(number):return datetime.datetime.fromtimestamp(number,datetime.timezone.utc).isoformat().replace('+00:00','Z')
        low, high = second(anchor['coverage_from']), second(interval_end)
        require(low <= high <= int(datetime.datetime.now(datetime.timezone.utc).timestamp()), 'coverage interval clock invalid')
        expected = {'schema_version':1,'repository':api.repo,'stream':stream,'binding':binding(anchor),'workflow_id':policy['receipts']['workflow_id'],'source_branch':policy['base_branch'],'page_size':page_size,'interval_start':stamp(low),'interval_end':stamp(high)}
        scope=archive.interval_scope(anchor,stream,interval_end,interval_scoped)
        manifest = protected('receipt-archive/backfill/'+scope+'.json')
        if manifest is None:return gap('required-source-history-missing')
        require(type(manifest) is dict and set(manifest) == set(expected)|{'stack','epoch','rounds_observed','round_gaps','last_round_gaps','coverage_complete'} and all(archive.canonical(manifest[key]) == archive.canonical(value) for key,value in expected.items()) and manifest['coverage_complete'] is False, 'coverage source campaign differs')
        require(all(type(manifest[key]) is int and 0 <= manifest[key] < 10**12 for key in ('epoch','rounds_observed','round_gaps','last_round_gaps')), 'coverage source round malformed')
        if manifest['epoch'] == 0 or manifest['rounds_observed'] != manifest['epoch'] or manifest['round_gaps'] or manifest['last_round_gaps'] or manifest['stack'] != [[low,high]]:return gap('source-round-incomplete')
        result['source_epoch'] = manifest['epoch']-1
        frontier = [(low,high)]; nodes = 0; listed = {}; saturated = []
        while frontier:
            nodes += 1
            if nodes > 128:return gap('source-partition-capacity')
            lo,hi = frontier.pop(); identity = archive.digest(archive.canonical([expected,lo,hi]))
            node = protected(f'receipt-archive/backfill/{scope}/{identity[:2]}/{identity}.json')
            if node is None:return gap('required-partition-missing')
            keys = {'schema_version','campaign_sha256','lo','hi','epoch','phase','page','expected_count','seen','facts','reason','observation'}
            require(type(node) is dict and set(node) == keys and type(node['schema_version']) is int and node['schema_version'] == 1 and node['campaign_sha256'] == archive.digest(archive.canonical(expected)) and type(node['lo']) is int and type(node['hi']) is int and (node['lo'],node['hi']) == (lo,hi) and type(node['epoch']) is int, 'coverage partition binding differs')
            if node['epoch'] != result['source_epoch'] or node['phase'] not in ('split','observed'):return gap('partition-not-observed')
            require(type(node['expected_count']) is int and node['expected_count'] >= 0 and type(node['page']) is int and type(node['seen']) is list and len(node['seen']) <= 999 and type(node['facts']) is list and 0 < len(node['facts']) <= 1000 and node['page'] == len(node['facts'])+1 and node['reason'] is None, 'coverage partition shape differs')
            offset = 0; identities = set()
            for row in node['seen']:
                require(type(row) is dict and set(row) == {'run_id','attempt','source_sha','created_at'} and all(type(row[k]) is int and row[k] > 0 for k in ('run_id','attempt')) and row['run_id'] not in identities and archive.state_paths.valid_hash(row['source_sha'],40) and lo <= second(row['created_at']) <= hi, 'coverage source identity differs')
                identities.add(row['run_id'])
            for number,fact in enumerate(node['facts'],1):
                require(type(fact) is dict and set(fact) == {'page','total_count','rows_sha256','rows_count'} and type(fact['page']) is int and fact['page'] == number and type(fact['total_count']) is int and fact['total_count'] == node['expected_count'] and type(fact['rows_count']) is int and 0 <= fact['rows_count'] <= page_size and archive.state_paths.valid_hash(fact['rows_sha256'],64), 'coverage page fact differs')
                retained = node['seen'][offset:offset+fact['rows_count']]; offset += fact['rows_count']
                require(archive.digest(archive.canonical(retained)) == fact['rows_sha256'], 'coverage retained page identities differ')
                target = f'{root}/actions/workflows/{policy["receipts"]["workflow_id"]}/runs?branch={quote(policy["base_branch"],safe="")}&created={quote(stamp(lo)+".."+stamp(hi),safe="")}&per_page={page_size}&page={number}'
                response = observe(target)
                require(type(response) is dict and type(response.get('total_count')) is int and type(response.get('workflow_runs')) is list and len(response['workflow_runs']) <= page_size, 'coverage source response malformed')
                rows = []
                for run in response['workflow_runs']:
                    run_identity(run,anchor,policy);require(lo <= second(run['created_at']) <= hi,'coverage source outside partition')
                    encoded=archive.canonical(run)
                    require(run['id'] not in listed_runs or listed_runs[run['id']]==encoded,'coverage conflicting full source identity')
                    listed_runs[run['id']]=encoded
                    rows.append({'run_id':run['id'],'attempt':run['run_attempt'],'source_sha':run['head_sha'],'created_at':run['created_at']})
                if response['total_count'] != fact['total_count'] or archive.canonical(rows) != archive.canonical(retained):return gap('source-identities-changed')
            require(offset == len(node['seen']), 'coverage page total differs')
            if node['phase'] == 'split':
                require(lo < hi and node['expected_count'] >= 1000 and len(node['facts']) == 1, 'coverage split invalid')
                saturated.append((lo,hi,node['expected_count'],node['seen']))
                mid=(lo+hi)//2;frontier.extend([(lo,mid),(mid if hi-lo>1 else hi,hi)])
            else:
                require(node['expected_count'] < 1000 and len(node['seen']) == node['expected_count'] and archive.canonical(node['observation']) == archive.canonical(node['facts'][0]), 'coverage leaf completion differs')
                for row in node['seen']:
                    require(row['run_id'] not in listed or listed[row['run_id']] == row, 'coverage conflicting overlap identity')
                    listed[row['run_id']] = row
        for lo,hi,minimum,observed in saturated:
            descendants={identity:row for identity,row in listed.items() if lo <= second(row['created_at']) <= hi}
            if len(descendants) < minimum:return gap('source-partition-count-inconsistent')
            if any(descendants.get(row['run_id']) != row for row in observed):return gap('source-partition-identities-inconsistent')
        result['source_partition_complete'] = True
        progress = protected('receipt-archive/progress/'+stream+'.json')
        if progress is None:return gap('required-watch-history-missing')
        watch_page_size = progress.get('pagination',{}).get('page_size') if type(progress) is dict and type(progress.get('pagination')) is dict else None
        require(type(watch_page_size) is int and 0 < watch_page_size <= 100, 'coverage watch page size invalid')
        progress = validate_checkpoint(progress,anchor,policy['receipts']['workflow_id'],watch_page_size)
        if not progress['scan']['complete']:return gap('protected-scan-incomplete')
        watched = {}; count = 0
        for number in range(progress['watch']['segments']):
            if number >= 128:return gap('watch-segment-capacity')
            segment = protected(archive.state_paths.pending_segment_path(stream,number))
            if segment is None:return gap('required-watch-segment-missing')
            for row in validate_watch(segment,api.repo,stream,number)['rows']:
                identity=(row['run_id'],row['attempt']);require(identity not in watched,'coverage duplicate watched attempt')
                watched[identity]=row;count+=1
        require(count == progress['watch']['count'],'coverage watched count differs')
        for row in listed.values():
            if watched.get((row['run_id'],row['attempt'])) != {k:row[k] for k in ('run_id','attempt','source_sha')}|{'classification':'pending'}:return gap('required-attempt-not-discovered')
        for row in listed.values():
            if row['attempt'] > len(watched) or any((row['run_id'],attempt) not in watched for attempt in range(1,row['attempt'])):
                return gap('required-prior-attempt-history-missing')
        with tempfile.TemporaryDirectory() as tmp:
            db=Path(tmp)/'projection.sqlite'
            projection=archive.reconstruct_interval(api,policy,db,trust_path,store,approval_path,stream,interval_end=projection_end,history_head=history_head,campaign=campaign,interval_scoped=interval_scoped)
            result['frozen_projection_complete']=projection['projection_complete']
            if not projection['projection_complete']:return gap('required-projection-gap')
            with sqlite3.connect(db) as sql:
                provenances=[archive.document(row[0].encode()) for row in sql.execute('SELECT provenance FROM delivery_provenance')]
            projected={(row['run_id'],row['attempt']) for row in provenances}
        retained_ids=set();withdrawn=0
        for identity,row in watched.items():
            latest=run_identity(archive.document(listed_runs[row['run_id']]) if row['run_id'] in listed_runs else observe(f'{root}/actions/runs/{row["run_id"]}',detail=True),anchor,policy)
            require(latest['id'] == row['run_id'] and latest['head_sha'] == row['source_sha'] and latest['run_attempt'] >= row['attempt'], 'coverage watched immutable identity changed')
            created=second(latest['created_at'])
            if not low <= created <= high:continue
            if (latest['id'],latest['run_attempt']) not in watched:return gap('new-attempt-unresolved')
            retained=archive.retained_execution(api,anchor,store,stream,*identity)
            if retained is not None:
                require(retained['record']['run']['source_sha'] == row['source_sha'],'coverage retained source differs')
                proof=archive.receipts.annotate_reported_trust(retained['record']['proof'],trust_path,api.repo)
                withdrawn+=proof['trust_status']=='withdrawn';retained_ids.add(identity);continue
            outcome=protected(outcome_path(api.repo,stream,row,epoch))
            if outcome is None:return gap('required-attempt-unresolved')
            outcome=validate_outcome(outcome,api.repo,stream,row,epoch)
            if outcome['classification'] != 'non-delivery':return gap('required-attempt-unresolved')
            source=validate_source_fact(outcome['source'],policy,row['source_sha'],trust_path,'profile')
            if outcome['reason']=='source-merge-disabled':require(source.get('merge_enabled') is False and outcome['source']['receipt'] is None,'coverage non-delivery differs')
            else:require(outcome['reason']=='authenticated-shadow','coverage non-delivery reason differs');validate_shadow(outcome['source'],source,row,anchor)
        if not retained_ids <= projected:return gap('required-delivery-not-projected')
        def references(tree):
            journal_path='receipt-archive/discovery/'+stream+'.json'
            require(blob_at(anchor['bootstrap_tree'],journal_path) is None,'coverage pre-bootstrap retained journal')
            raw=blob_at(tree,journal_path)
            if raw is None:
                item_at,_=archive.fixed_reader(api,root)
                require(all(item_at(tree,'receipt-archive/'+name) is None for name in ('index','objects','materials')),'coverage retained journal missing over existing data')
                return set()
            journal=archive.document(raw)
            require(type(journal) is dict and set(journal)=={'schema_version','repository','stream','coverage_from','next_segment','records_count'} and type(journal['schema_version']) is int and journal['schema_version']==1 and journal['repository']==api.repo and journal['stream']==stream and journal['coverage_from']==anchor['coverage_from'] and type(journal['records_count']) is int and type(journal['next_segment']) is int and 0<=journal['records_count']==journal['next_segment']<10**12,'coverage retained journal differs')
            values=set();executions=set()
            for number in range(journal['next_segment']):
                raw=blob_at(tree,archive.state_paths.segment_path(stream,number))
                require(raw is not None,'coverage retained segment missing')
                segment=archive.state_paths.validate_segment(archive.document(raw),api.repo,stream,number)
                require(len(segment['records'])==1,'coverage retained segment count differs')
                row=segment['records'][0];identity=(row['run_id'],row['attempt'])
                require(identity not in executions,'coverage retained execution duplicated');executions.add(identity)
                values.add((*identity,row['artifact_id'],row['record_sha256']))
            return values
        frozen=api.request(root+'/git/commits/'+projection['frozen_head'])
        require(frozen['sha']==projection['frozen_head'] and archive.state_paths.valid_hash(frozen['tree']['sha'],40),'coverage frozen tree differs')
        if references(anchor['tree']) != references(frozen['tree']['sha']):return gap('retained-snapshot-incomplete')
        for target,detail,raw in source_observations:
            if archive.canonical(observe(target,detail=detail,repeat=True)) != raw:return gap('source-changed-during-coverage')
        require(archive.verify_bootstrap(api,approval_path)==anchor and Path(approval_path).read_bytes()==approval_raw and Path(trust_path).read_bytes()==trust_raw,'coverage protected inputs changed')
        result.update(coverage_complete=True,verified_until=interval_end,retained_attempts=len(retained_ids),withdrawn_attempts=withdrawn)
        return result
    except (RuntimeError,OSError):return gap('required-observation-unavailable')
    except ValueError as error:
        if str(error).startswith('GitHub API request failed:'):return gap('required-observation-unavailable')
        if any(word in str(error) for word in ('budget','capacity','bound reached')):return gap('invocation-capacity')
        raise
