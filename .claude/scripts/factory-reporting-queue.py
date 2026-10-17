#!/usr/bin/env python3
"""Bounded queue journals, protected CAS and read-only reporting observations."""
from datetime import datetime, timezone
import hashlib
import json
import re

MAX_BYTES = 262144
MAX_EVENTS = 1000
CONFIG = {'enabled', 'queue_monitor_enabled', 'repository', 'state_repository', 'branch', 'destination', 'team_id', 'grace_minutes'}
FIELDS = {'schema_version', 'repository', 'branch', 'destination', 'team_id', 'stream', 'events'}
EVENT = {'key', 'kind', 'incident', 'run_id', 'run_attempt', 'cutoff', 'status', 'message_id'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def canonical(value):
    """Serialize already bounded typed values, not an untrusted input boundary."""
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def string(value, pattern, maximum):
    return type(value) is str and len(value) <= maximum and re.fullmatch(pattern, value) is not None


def validate_config(config, *, repository, default_branch):
    """Expected identity must come from protected context, never journal claims."""
    require(type(config) is dict and len(config) == len(CONFIG) and set(config) == CONFIG, 'queue config fields differ')
    require(string(repository, r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', 201) and type(config['repository']) is str and type(config['state_repository']) is str and config['repository'] == config['state_repository'] == repository, 'queue repository differs')
    require(string(default_branch, r'[A-Za-z0-9][A-Za-z0-9._/-]*', 255) and '..' not in default_branch and not default_branch.endswith('/') and type(config['branch']) is str and config['branch'] == default_branch, 'queue default branch differs')
    require(type(config['enabled']) is bool and type(config['queue_monitor_enabled']) is bool, 'queue enable flags invalid')
    require(string(config['destination'], r'[CG][A-Z0-9]+', 32) and string(config['team_id'], r'T[A-Z0-9]+', 32), 'queue destination/team invalid')
    require(type(config['grace_minutes']) is int and 15 <= config['grace_minutes'] <= 1440, 'queue grace invalid')
    return config


def stream(config):
    return hashlib.sha256(canonical(['factory-reporting-queue-v1', config['repository'], config['destination'], config['branch']])).hexdigest()


def event_key(identity, row):
    require(string(identity, r'[0-9a-f]{64}', 64) and type(row) is dict and type(row.get('kind')) is str and row['kind'] in {'stalled', 'drill', 'recovery'}, 'queue event identity invalid')
    fields = ['factory-reporting-queue-event-v1', identity, row['kind']]
    if row['kind'] == 'recovery':
        require(string(row.get('incident'), r'[0-9a-f]{64}', 64), 'queue recovery identity invalid')
        fields.append(row['incident'])
    else:
        require(all(type(row.get(k)) is int and 0 < row[k] < 2**63 for k in ('run_id', 'run_attempt')), 'queue run identity invalid')
        fields.extend((row['run_id'], row['run_attempt']))
    return hashlib.sha256(canonical(fields)).hexdigest()


def cutoff(value):
    require(string(value, r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z', 27), 'queue cutoff invalid')
    try:
        parsed = datetime.fromisoformat(value[:-1]+'+00:00')
    except ValueError as error:
        raise ValueError('queue cutoff invalid') from error
    require(parsed <= datetime.now(timezone.utc), 'queue cutoff future')


def validate_journal(value, config):
    """Shape/invariants only. Protected branch/initialization is a later boundary."""
    validate_config(config, repository=config.get('repository') if type(config) is dict else None, default_branch=config.get('branch') if type(config) is dict else None)
    require(type(value) is dict and len(value) == len(FIELDS) and set(value) == FIELDS, 'queue journal fields differ')
    require(type(value['schema_version']) is int and value['schema_version'] == 1, 'queue journal version differs')
    require(all(type(value[k]) is str and value[k] == config[k] for k in ('repository', 'branch', 'destination', 'team_id')) and string(value['stream'], r'[0-9a-f]{64}', 64) and value['stream'] == stream(config), 'queue journal identity differs')
    rows = value['events']; require(type(rows) is list and len(rows) <= MAX_EVENTS, 'queue journal event capacity exceeded')
    seen = {}; recovered = set(); unfinished = False; open_stalled = set(); size = 1024
    for row in rows:
        require(not unfinished, 'queue unfinished event must reconcile first')
        require(type(row) is dict and len(row) == len(EVENT) and set(row) == EVENT, 'queue event fields differ')
        require(type(row['kind']) is str and row['kind'] in {'stalled', 'drill', 'recovery'} and type(row['status']) is str and row['status'] in {'pending', 'uncertain', 'confirmed'}, 'queue event state invalid')
        cutoff(row['cutoff'])
        require(string(row['key'], r'[0-9a-f]{64}', 64) and row['key'] == event_key(value['stream'], row) and row['key'] not in seen, 'queue event key duplicate or differs')
        if row['kind'] == 'recovery':
            require(row['run_id'] is None and row['run_attempt'] is None and row['incident'] in seen and seen[row['incident']]['kind'] != 'recovery' and seen[row['incident']]['status'] == 'confirmed' and row['incident'] not in recovered, 'queue recovery unjustified')
            require(row['cutoff'] >= seen[row['incident']]['cutoff'], 'queue recovery clock differs')
            recovered.add(row['incident'])
            if row['status'] == 'confirmed':
                open_stalled.discard(row['incident'])
        else:
            require(type(row['incident']) is str and row['incident'] == row['key'], 'queue incident differs')
            if row['kind'] == 'stalled':
                require(not open_stalled, 'queue prolonged incident duplicated')
                open_stalled.add(row['key'])
        if row['status'] == 'confirmed':
            require(string(row['message_id'], r'[0-9]+\.[0-9]{1,6}', 32), 'queue confirmed receipt invalid')
        else:
            require(row['message_id'] is None, 'queue unfinished event has receipt')
            unfinished = True
        # Flat typed fields are bounded before canonical serialization; no arbitrary graph traversal.
        size += 256 + sum(len(row[k]) for k in ('key', 'kind', 'incident', 'cutoff', 'status')) + (len(row['message_id']) if row['message_id'] else 0)
        require(size <= MAX_BYTES, 'queue journal byte capacity exceeded')
        seen[row['key']] = row
    require(len(canonical(value)) <= MAX_BYTES, 'queue journal byte capacity exceeded')
    return value


def load_journal(raw, config):
    require(type(raw) is bytes and 0 < len(raw) <= MAX_BYTES, 'queue journal input size invalid')
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'queue duplicate JSON key')
            result[key] = value
        return result
    try:
        value = json.loads(raw, object_pairs_hook=pairs)
    except (ValueError, UnicodeError, RecursionError) as error:
        raise ValueError('queue journal JSON invalid') from error
    return validate_journal(value, config)


def validate_transition(expected, desired, config):
    """One immutable intent append or one monotonic receipt-state transition."""
    validate_journal(desired, config)
    before = [] if expected is None else validate_journal(expected, config)['events']
    after = desired['events']
    require(len(before) <= len(after) <= len(before)+1, 'queue transition drops or replaces intent')
    changes = 0
    for old, new in zip(before, after):
        require(all(old[k] == new[k] for k in EVENT-{'status', 'message_id'}), 'queue transition changes immutable intent')
        if old != new:
            require((old['status'], new['status']) in {('pending', 'uncertain'), ('pending', 'confirmed'), ('uncertain', 'confirmed')}, 'queue transition regresses receipt state')
            changes += 1
    if len(after) > len(before):
        require(changes == 0 and after[-1]['status'] == 'pending' and after[-1]['message_id'] is None, 'queue transition must durably append pending intent')
    else:
        require(changes <= 1, 'queue transition changes multiple effects')


class QueueStore:
    """Existing protected GitState origin, isolated path and bounded real CAS.

    A caller snapshot is a precondition, never origin. This does not provide the
    separate Spec014 exclusive-writer/archive-origin guarantees or activate them.
    """
    def __init__(self, api, config, storage):
        import importlib.util
        from pathlib import Path
        validate_config(config, repository=api.repo, default_branch=config.get('branch') if type(config) is dict else None)
        require(type(storage) is dict and set(storage) in ({'state_branch', 'bootstrap_sha', 'initialize', 'policy_approvals'}, {'state_branch', 'bootstrap_sha', 'initialize', 'policy_approvals', 'state_view'}), 'queue storage fields differ')
        branch = storage['state_branch']
        require(string(branch, r'[A-Za-z0-9][A-Za-z0-9._/-]*', 255) and '..' not in branch and not branch.endswith('/'), 'queue state branch invalid')
        require(string(storage['bootstrap_sha'], r'[0-9a-f]{40}', 40) and type(storage['initialize']) is bool, 'queue bootstrap configuration invalid')
        approvals = storage['policy_approvals']; require(type(approvals) is dict and len(approvals) <= 16, 'queue policy approvals bound exceeded')
        fields = {'schema_version', 'repository', 'ruleset_id', 'policy_sha256', 'policy_updated_at', 'observed_at', 'bypass_actors'}
        for key, value in approvals.items():
            require(string(key, r'[0-9]{1,20}', 20) and type(value) is dict and len(value) == len(fields) and set(value) == fields, 'queue policy approval fields differ')
            require(type(value['schema_version']) is int and value['schema_version'] == 1 and type(value['ruleset_id']) is int and 0 < value['ruleset_id'] < 2**63 and str(value['ruleset_id']) == key, 'queue policy approval identity invalid')
            require(string(value['repository'], r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', 201) and string(value['policy_sha256'], r'[0-9a-f]{64}', 64), 'queue policy approval binding invalid')
            require(all(type(value[k]) is str and len(value[k]) <= 40 for k in ('policy_updated_at', 'observed_at')) and type(value['bypass_actors']) is list and not value['bypass_actors'], 'queue policy approval shape invalid')
        module = importlib.util.spec_from_file_location('queue_git_state', Path(__file__).with_name('factory-git-state.py'))
        self.state = importlib.util.module_from_spec(module); module.loader.exec_module(self.state)
        self.state.state_view_config(storage.get('state_view'))
        self.source = api; self.repo = api.repo; self.config = json.loads(canonical(config)); self.storage = json.loads(canonical(storage))
        self.identity = stream(config); self.calls = self.consumed = 0
        self.immutable = {}; self.cached_bytes = 0

    def request(self, path, method='GET', payload=None):
        require(path == 'repos/'+self.repo or path.startswith('repos/'+self.repo+'/'), 'queue storage foreign API')
        immutable = self.storage.get('state_view') is not None and method == 'GET' and payload is None and re.fullmatch(
            re.escape('repos/'+self.repo+'/git/')+r'(?:commits|trees|blobs)/[0-9a-f]{40}', path) is not None
        if immutable and path in self.immutable:return json.loads(self.immutable[path])
        require(self.calls < 128, 'queue storage API bound exceeded'); self.calls += 1
        # Production state.API bounds stdout before JSON parse; preserve that transport bound.
        value = self.source.request(path, method, payload)
        encoded = canonical(value); size = len(encoded); self.consumed += size
        require(size <= self.state.MAX_STATE*2 and self.consumed <= 33554432, 'queue storage observation bound exceeded')
        if immutable:
            if len(self.immutable) < 128 and self.cached_bytes+size <= 33554432:
                self.immutable[path] = encoded; self.cached_bytes += size
            return json.loads(encoded)
        return value

    def _load(self):
        repository = self.request('repos/'+self.repo)
        require(type(repository) is dict and repository.get('full_name') == self.repo, 'queue storage repository differs')
        validate_config(self.config, repository=self.repo, default_branch=repository.get('default_branch'))
        try:
            current = self.state.GitState(self, self.storage['state_branch'], self.identity,
                                          self.storage['bootstrap_sha'], self.storage['policy_approvals'],
                                          bootstrap_existing=self.storage['initialize'], state_view=self.storage.get('state_view'))
        except ValueError as error:
            if str(error) == 'missing checkpoint requires exact protected bootstrap revision; never reset silently':
                raise ValueError('queue initialization drift; exact reviewed bootstrap required') from error
            raise
        if current.bytes is None:
            require(self.storage['initialize'], 'queue journal missing; reviewed initialization required')
            journal = None
        else:
            journal = load_journal(current.bytes, self.config)
        return current, journal

    def read(self):
        self.calls = self.consumed = 0
        current, journal = self._load()
        return {'head': current.head, 'journal': journal}

    def checkpoint(self, expected, desired):
        import subprocess
        validate_transition(expected, desired, self.config)
        expected = None if expected is None else json.loads(canonical(expected))
        desired = json.loads(canonical(desired)); self.calls = self.consumed = 0; uncertain = False
        for attempt in range(3):
            current, journal = self._load()
            if journal == desired:
                return {'status': 'already-applied', 'head': current.head, 'uncertain_write_reconciled': uncertain}
            require(journal == expected, 'queue journal conflict; reconcile immutable intent')
            try:
                current.checkpoint(canonical(desired))
            except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired):
                uncertain = True
            try:
                observed, actual = self._load()
            except (ValueError, RuntimeError, OSError, subprocess.TimeoutExpired) as error:
                if isinstance(error, ValueError) and str(error).startswith('queue initialization drift;'):
                    raise
                raise ValueError('queue write uncertain; protected ref/journal reconciliation required') from error
            if actual == desired:
                return {'status': 'applied', 'head': observed.head, 'uncertain_write_reconciled': uncertain}
            require(actual == expected, 'queue journal conflict; reconcile immutable intent')
        raise ValueError('queue three CAS attempts exhausted; no assumed success')


_QUEUE_PATHS = {
    'factory-hosted-digest.yml': ('schedule', 'workflow_dispatch'),
    'factory-hosted-feedback.yml': ('schedule', 'workflow_dispatch'),
    'factory-reporting-alerts.yml': ('schedule', 'workflow_dispatch', 'workflow_run'),
}
_QUEUE_STATUSES = ('queued', 'in_progress', 'requested', 'waiting', 'pending')


class _QueueObservationError(ValueError):
    pass


def _observed(condition, category='metadata-invalid'):
    if not condition:
        raise _QueueObservationError(category)


class _QueueReader:
    """One read-only bounded observation; no caller health or run identities."""
    def __init__(self, api, config, storage, now):
        _observed(isinstance(now, datetime) and now.tzinfo is not None and now.utcoffset() is not None, 'clock-invalid')
        self.store = QueueStore(api, config, storage)
        self.repo = api.repo; self.config = self.store.config; self.storage = self.store.storage
        self.now = now.astimezone(timezone.utc)
        _observed(self.now <= datetime.now(timezone.utc), 'clock-invalid')
        self.root = 'repos/'+self.repo
        _observed(self.config['enabled'] is True and self.config['queue_monitor_enabled'] is True, 'queue-probe-disabled')
        self.repository = self.repository_metadata()

    def request(self, path, method='GET', payload=None):
        _observed(method == 'GET' and payload is None, 'observer-write-forbidden')
        return self.store.request(path, method, payload)

    def repository_metadata(self):
        item = self.request(self.root)
        _observed(type(item) is dict and type(item.get('id')) is int and 0 < item['id'] < 2**63 and item.get('full_name') == self.repo and item.get('default_branch') == self.config['branch'] and item.get('archived') is False and type(item.get('private')) is bool, 'repository-invalid')
        return {key: item[key] for key in ('id', 'full_name', 'default_branch', 'archived', 'private')}

    def time(self, raw):
        _observed(string(raw, r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})', 40), 'metadata-clock-invalid')
        _observed(raw.endswith('Z') or (int(raw[-5:-3]) < 24 and int(raw[-2:]) < 60), 'metadata-clock-invalid')
        value = datetime.fromisoformat(raw.replace('Z', '+00:00')).astimezone(timezone.utc)
        _observed(value <= self.now, 'metadata-clock-invalid')
        return value

    def worker_health(self):
        identity = hashlib.sha256(canonical([self.repo, self.config['destination'], self.config['branch']])).hexdigest()
        state = self.store.state
        view = state.GitState(self, self.storage['state_branch'], identity, self.storage['bootstrap_sha'], self.storage['policy_approvals'], state_view=self.storage.get('state_view'))
        _observed(view.bytes is not None, 'protected-health-missing')
        item = json.loads(view.bytes, object_pairs_hook=state.digest.coordinator.contract.no_duplicate_keys)
        state.validate(item, self.repo, identity)
        cursor = self.time(item['tables']['digest_cursors'][0]['cutoff'])
        due = self.time(state.slack.due(self.now))
        pending = sum(row['status'] != 'confirmed' for row in item['tables']['digest_batches'])
        return {'checkpoint_sha': view.head, 'delivered_cutoff': cursor.isoformat(), 'expected_cutoff': due.isoformat(), 'pending_batches': pending, 'current': cursor >= due}

    def run_fact(self, run, workflow, filename, status):
        fields = {'id', 'run_attempt', 'workflow_id', 'path', 'repository', 'head_repository', 'head_branch', 'head_sha', 'event', 'status', 'conclusion', 'created_at', 'updated_at', 'run_started_at'}
        _observed(type(run) is dict and fields <= set(run))
        _observed(all(type(run[k]) is int and 0 < run[k] < 2**63 for k in ('id', 'run_attempt', 'workflow_id')))
        _observed(run['workflow_id'] == workflow and run['path'] == '.github/workflows/'+filename and run['head_branch'] == self.config['branch'] and run['event'] in _QUEUE_PATHS[filename] and run['status'] == status and run['conclusion'] is None)
        _observed(all(type(run[k]) is dict and type(run[k].get('id')) is int and run[k]['id'] == self.repository['id'] and run[k].get('full_name') == self.repo for k in ('repository', 'head_repository')))
        _observed(string(run['head_sha'], r'[0-9a-f]{40}', 40))
        created, updated = self.time(run['created_at']), self.time(run['updated_at'])
        started = None if run['run_started_at'] is None else self.time(run['run_started_at'])
        _observed(created <= updated and (started is None or created <= started), 'metadata-clock-invalid')
        return {'run_id': run['id'], 'attempt': run['run_attempt'], 'workflow_id': workflow, 'status': status, 'head_sha': run['head_sha'], 'created': created, 'updated': updated, 'started': started}

    def runs(self):
        from urllib.parse import quote
        approved = {}; found = {}
        for filename in _QUEUE_PATHS:
            meta = self.request(self.root+'/actions/workflows/'+filename)
            _observed(type(meta) is dict and type(meta.get('id')) is int and 0 < meta['id'] < 2**63 and meta.get('path') == '.github/workflows/'+filename and meta.get('state') == 'active', 'workflow-invalid')
            identity = meta['id']; _observed(identity not in approved, 'workflow-ambiguous'); approved[identity] = filename
            for status in _QUEUE_STATUSES:
                total = None; listed = []
                for page in (1, 2):
                    path = self.root+'/actions/workflows/'+str(identity)+'/runs?branch='+quote(self.config['branch'], safe='')+'&status='+status+'&per_page=100&page='+str(page)
                    response = self.request(path)
                    _observed(type(response) is dict and type(response.get('total_count')) is int and 0 <= response['total_count'] < 1000 and type(response.get('workflow_runs')) is list, 'run-list-invalid-or-saturated')
                    count = response['total_count']; rows = response['workflow_runs']
                    _observed(count <= 200 and len(rows) <= 100, 'run-list-capacity')
                    if total is None:
                        total = count
                    _observed(count == total and len(rows) == min(100, max(0, total-100*(page-1))), 'run-list-incomplete-or-changed')
                    listed.extend(rows)
                    if page*100 >= total:
                        break
                _observed(len(listed) == total, 'run-list-incomplete-or-changed')
                for row in listed:
                    fact = self.run_fact(row, identity, filename, status)
                    _observed(fact['run_id'] not in found and len(found) < 16, 'active-run-duplicate-or-capacity')
                    found[fact['run_id']] = fact
        return approved, found

    def jobs(self, runs):
        result = {}; count = 0
        for identity, run in runs.items():
            response = self.request(self.root+'/actions/runs/'+str(identity)+'/attempts/'+str(run['attempt'])+'/jobs?per_page=100&page=1')
            _observed(type(response) is dict and type(response.get('total_count')) is int and 0 <= response['total_count'] <= 100 and type(response.get('jobs')) is list and len(response['jobs']) == response['total_count'], 'job-list-incomplete-or-capacity')
            count += response['total_count']; _observed(count <= 64, 'job-capacity')
            activity = max(run['created'], run['updated'], run['started'] or run['created']); facts = {}; executed = False
            for job in response['jobs']:
                fields = {'id', 'run_id', 'run_attempt', 'head_sha', 'status', 'created_at', 'started_at', 'steps'}
                _observed(type(job) is dict and fields <= set(job) and type(job['id']) is int and 0 < job['id'] < 2**63 and job['id'] not in facts)
                _observed(type(job['run_id']) is int and job['run_id'] == identity and type(job['run_attempt']) is int and job['run_attempt'] == run['attempt'] and job['head_sha'] == run['head_sha'])
                _observed(job['status'] in (*_QUEUE_STATUSES, 'completed') and type(job['steps']) is list and len(job['steps']) <= 100)
                created = self.time(job['created_at']); started = None if job['started_at'] is None else self.time(job['started_at'])
                _observed(created >= run['created'] and (started is None or started >= created), 'metadata-clock-invalid')
                activity = max(activity, created, started or created); executed |= started is not None or job['status'] in ('in_progress', 'completed')
                steps = []
                for step in job['steps']:
                    _observed(type(step) is dict and step.get('status') in (*_QUEUE_STATUSES, 'completed'))
                    start = None if step.get('started_at') is None else self.time(step['started_at'])
                    if start is not None:
                        _observed(start >= created, 'metadata-clock-invalid'); activity = max(activity, start)
                    executed |= step['status'] in ('in_progress', 'completed'); steps.append((step['status'], start))
                facts[job['id']] = (job['status'], created, started, steps)
            result[identity] = {'facts': facts, 'last_activity': activity, 'executed': executed}
        return result

    def observe(self):
        before = self.worker_health(); workflows, runs = self.runs(); jobs = self.jobs(runs)
        _observed(self.runs() == (workflows, runs) and self.jobs(runs) == jobs, 'metadata-observation-changed')
        _observed(self.worker_health() == before and self.repository_metadata() == self.repository, 'protected-health-or-repository-changed')
        stalled = []
        for identity, run in runs.items():
            detail = jobs[identity]
            if (self.now-detail['last_activity']).total_seconds() >= self.config['grace_minutes']*60:
                stalled.append({'run_id': identity, 'run_attempt': run['attempt'], 'workflow_id': run['workflow_id'], 'status': run['status'], 'created_at': run['created'].isoformat(), 'last_activity_at': detail['last_activity'].isoformat(), 'execution_observed': detail['executed']})
        status = 'stalled' if stalled else 'metadata-current' if before['current'] and before['pending_batches'] == 0 else 'unknown'
        return {'status': status, 'reporting_health': before, 'stalled': sorted(stalled, key=lambda row:row['run_id']), 'coverage_complete': status != 'unknown'}


def observe_queue(api, config, storage, now):
    """No caller health, writes or Slack reads; metadata-current is not recovery."""
    import subprocess
    result = {'status': 'unknown', 'scope': 'queue-metadata', 'coverage_complete': False,
              'receipt_verified': False, 'recovery_eligible': False, 'deployment_context': 'unknown', 'stalled': []}
    try:
        result.update(_QueueReader(api, config, storage, now).observe())
        if result['status'] == 'unknown':
            result['reason'] = 'protected-reporting-health-not-current'
    except _QueueObservationError as error:
        result['reason'] = str(error)
    except (ValueError, KeyError, TypeError, RuntimeError, OSError, subprocess.TimeoutExpired, RecursionError, OverflowError):
        result['reason'] = 'observation-unavailable-or-invalid'
    return result


def run_queue(api, client, config, storage, reporting, now, *, drill_run=None):
    """Protected queue outbox; no workflow/CLI activation or caller health proof."""
    import importlib.util
    from pathlib import Path
    fields = {'enabled', 'repository', 'state_repository', 'branch', 'destination', 'team_id', 'start', 'attachments_enabled'}
    require(type(reporting) is dict and len(reporting) == len(fields) and set(reporting) == fields, 'queue reporting context fields differ')
    require(type(config) is dict, 'queue configuration must be an object')
    validate_config(config, repository=api.repo, default_branch=config.get('branch'))
    require(config['enabled'] is True and config['queue_monitor_enabled'] is True and reporting['enabled'] is True and type(reporting['attachments_enabled']) is bool, 'queue reporting policy disabled or invalid')
    require(all(type(reporting[k]) is str and reporting[k] == config[k] for k in ('repository', 'state_repository', 'branch', 'destination', 'team_id')), 'queue reporting identity differs')
    require(isinstance(now, datetime) and now.tzinfo is not None and now.utcoffset() is not None and now.astimezone(timezone.utc) <= datetime.now(timezone.utc), 'queue delivery clock invalid')
    now = now.astimezone(timezone.utc)
    start = reporting['start']
    require(string(start, r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})', 40) and (start.endswith('Z') or (int(start[-5:-3]) < 24 and int(start[-2:]) < 60)), 'queue reporting origin invalid')
    start_time = datetime.fromisoformat(start.replace('Z', '+00:00')).astimezone(timezone.utc)
    require(start_time <= now, 'queue reporting origin future')
    reporting = json.loads(canonical(reporting))
    class DeliveryAPI:
        repo = api.repo
        calls = consumed = 0
        def __init__(self):
            self.immutable = {}; self.cached_bytes = 0
            self.archive = type(storage) is dict and type(storage.get('state_view')) is dict and storage['state_view'].get('mode') == 'archive'
        def request(self, path, method='GET', payload=None):
            require(path == 'repos/'+self.repo or path.startswith('repos/'+self.repo+'/'), 'queue delivery foreign API')
            immutable = self.archive and method == 'GET' and payload is None and re.fullmatch(
                re.escape('repos/'+self.repo+'/git/')+r'(?:commits|trees|blobs)/[0-9a-f]{40}', path) is not None
            if immutable and path in self.immutable:return json.loads(self.immutable[path])
            require(self.calls < 512, 'queue delivery API bound exceeded'); self.calls += 1
            value = api.request(path, method, payload)
            encoded = canonical(value); size = len(encoded); self.consumed += size
            require(size <= 16000000 and self.consumed <= 67108864, 'queue delivery API byte bound exceeded')
            if immutable:
                require(len(self.immutable) < 512 and self.cached_bytes+size <= 67108864, 'queue immutable cache bound exceeded')
                self.immutable[path] = encoded; self.cached_bytes += size
                return json.loads(encoded)
            return value
    class DeliverySlack:
        calls = consumed = 0
        def account(self, size):
            self.calls += 1; self.consumed += size
            require(self.calls <= 512 and self.consumed <= 8000000, 'queue Slack observation bound exceeded')
        def call(self, method, body):
            require(method in {'auth.test', 'conversations.history', 'chat.postMessage', 'files.info'}, 'queue Slack method forbidden')
            require(self.calls < 512, 'queue Slack observation bound exceeded')
            value = client.call(method, body); size = len(canonical(value))
            require(size <= 2000000, 'queue Slack response bound exceeded'); self.account(size)
            return value
        def transfer(self, url, data=None, **kwargs):
            require(data is None and self.calls < 512, 'queue recovery upload forbidden')
            value = client.transfer(url, **kwargs)
            require(type(value) is bytes and len(value) <= 1000000, 'queue file response bound exceeded'); self.account(len(value))
            return value
    source = DeliveryAPI(); remote = DeliverySlack(); store = QueueStore(source, config, storage)
    spec = importlib.util.spec_from_file_location('queue_alert_runtime', Path(__file__).with_name('factory-reporting-alerts.py'))
    runtime = importlib.util.module_from_spec(spec); spec.loader.exec_module(runtime)
    watch = dict(reporting, state_branch=storage['state_branch'], bootstrap_sha=storage['bootstrap_sha'], policy_approvals=storage['policy_approvals'], watchdog_grace_minutes=config['grace_minutes'], state_view=storage.get('state_view'))
    identity = stream(config)
    class Notice(runtime.Alert):
        event_type = 'factory_reporting_queue_v1'
        def format_text(self):
            row = self.row
            if row['kind'] == 'drill':
                detail = 'Queue alert verification drill; this is not an actual reporting outage.'
            elif row['kind'] == 'stalled':
                detail = 'Eligible reporting workflow has no observed progress past queue grace: https://github.com/'+config['repository']+'/actions/runs/'+str(row['run_id'])+' (attempt '+str(row['run_attempt'])+'). Concurrency owner and deployment cause are unknown.'
            else:
                detail = 'Queue recovery: current protected digest receipt and worker metadata verified. Incident '+row['incident'][:12]
            return 'Factory reporting queue — '+config['repository']+'\n'+detail
    def notice(row):
        result = Notice(remote, config, row)
        require(string(result.bot, r'B[A-Z0-9]+', 32), 'queue bot identity invalid')
        return result
    def worker():
        state = runtime.state
        key = hashlib.sha256(canonical([source.repo, config['destination'], config['branch']])).hexdigest()
        current = state.GitState(source, storage['state_branch'], key, storage['bootstrap_sha'], storage['policy_approvals'], state_view=storage.get('state_view'))
        require(current.bytes is not None, 'queue worker checkpoint missing')
        body = json.loads(current.bytes, object_pairs_hook=state.digest.coordinator.contract.no_duplicate_keys)
        state.validate(body, source.repo, key)
        require(body['tables']['digest_origins'][0]['origin'] == state.digest.stamp(start_time), 'queue reporting origin differs from protected worker')
        return hashlib.sha256(current.bytes).hexdigest(), body
    def verified_worker():
        before, body = worker()
        health = runtime.w.inspect(watch, source, remote, now)
        require(health['status'] == 'current' and health['latest_receipt_verified'] is True and health['pending_batches'] == 0, 'queue recovery requires current exact delivery receipt')
        after, current = worker(); require(before == after, 'queue worker changed during receipt proof')
        batches = [row for row in current['tables']['digest_batches'] if row['status'] == 'confirmed']
        require(bool(batches), 'queue recovery current receipt missing')
        latest = max(batches, key=lambda row:runtime.state.digest.instant(row['cutoff']))
        adapter = runtime.state.slack.transport(remote, watch, latest)
        require(adapter.lookup(latest['key']).get('receipt') == json.loads(latest['receipt']), 'queue recovery receipt differs')
        require(worker()[0] == before, 'queue worker changed during receipt proof')
        return before
    worker()  # Bind protected origin before initialization or any other effect.
    document = store.read()['journal']
    if document is None:
        empty = {'schema_version':1, 'repository':config['repository'], 'branch':config['branch'], 'destination':config['destination'], 'team_id':config['team_id'], 'stream':identity, 'events':[]}
        store.checkpoint(None, empty); document = empty
    def persist(value):
        nonlocal document
        store.checkpoint(document, value); document = value
    reconciled = 0
    for index, row in enumerate(document['events']):
        if row['status'] != 'confirmed':
            receipt = notice(row).lookup()
            next_document = json.loads(canonical(document))
            next_document['events'][index].update(status='confirmed' if receipt else 'uncertain', message_id=receipt)
            persist(next_document)
            require(receipt is not None, 'queue send uncertain; no automatic resend')
            reconciled += 1
    def emit(row, guard=None):
        value = json.loads(canonical(document)); value['events'].append(row); persist(value)
        if guard is not None:
            guard()
        try:
            receipt = notice(row).send()
        except Exception:
            value = json.loads(canonical(document)); value['events'][-1]['status'] = 'uncertain'; persist(value)
            raise
        value = json.loads(canonical(document)); value['events'][-1].update(status='confirmed', message_id=receipt); persist(value)
        return {'notifications':1, 'reconciled':reconciled}
    def row(kind, run=None, attempt=None, incident=None):
        value = {'kind':kind, 'run_id':run, 'run_attempt':attempt, 'cutoff':now.isoformat(timespec='microseconds').replace('+00:00','Z'), 'status':'pending', 'message_id':None, 'incident':incident}
        value['key'] = event_key(identity, value); value['incident'] = incident or value['key']
        return value
    if drill_run is not None:
        require(type(drill_run) is int and 0 < drill_run < 2**63, 'queue drill run invalid')
        root = 'repos/'+source.repo
        repository = source.request(root); workflow = source.request(root+'/actions/workflows/factory-reporting-queue.yml'); actual = source.request(root+'/actions/runs/'+str(drill_run))
        require(all(type(value) is dict for value in (repository, workflow, actual)), 'queue drill metadata must be objects')
        require(all(type(actual.get(field)) is int and 0 < actual[field] < 2**63 for field in ('id', 'workflow_id', 'run_attempt')), 'queue drill execution identity invalid')
        require(type(repository.get('id')) is int and 0 < repository['id'] < 2**63, 'queue drill repository identity invalid')
        require(type(workflow.get('id')) is int and 0 < workflow['id'] < 2**63 and workflow.get('path') == '.github/workflows/factory-reporting-queue.yml' and workflow.get('state') == 'active', 'queue drill workflow differs')
        require(actual.get('id') == drill_run and actual.get('workflow_id') == workflow['id'] and actual.get('path') == workflow['path'] and actual.get('event') == 'workflow_dispatch' and actual.get('status') == 'in_progress' and actual.get('conclusion') is None and actual.get('head_branch') == config['branch'] and string(actual.get('head_sha'), r'[0-9a-f]{40}', 40), 'queue drill execution differs')
        require(repository.get('full_name') == source.repo and repository.get('default_branch') == config['branch'] and type(repository.get('id')) is int and all(type(actual.get(k)) is dict and type(actual[k].get('id')) is int and actual[k]['id'] == repository['id'] and actual[k].get('full_name') == source.repo for k in ('repository','head_repository')), 'queue drill repository differs')
        require(type(actual.get('run_attempt')) is int and 0 < actual['run_attempt'] < 2**63, 'queue drill attempt invalid')
        pending = row('drill', drill_run, actual['run_attempt'])
    else:
        observation = observe_queue(source, config, storage, now)
        require(observation['status'] != 'unknown', 'queue metadata unknown; no notification or recovery proof')
        recovered = {r['incident'] for r in document['events'] if r['kind'] == 'recovery'}
        active = [r for r in document['events'] if r['kind'] != 'recovery' and r['key'] not in recovered]
        if observation['status'] == 'stalled':
            if any(r['kind'] == 'stalled' for r in active):
                for item in active:
                    require(notice(item).lookup() == item['message_id'], 'queue incident receipt no longer verifiable')
                return {'notifications':0, 'reconciled':reconciled}
            selected = observation['stalled'][0]; pending = row('stalled', selected['run_id'], selected['run_attempt'])
        elif active:
            incident = active[0]; require(notice(incident).lookup() == incident['message_id'], 'queue incident receipt no longer verifiable')
            binding = verified_worker(); pending = row('recovery', incident=incident['key'])
            def recheck():
                require(observe_queue(source, config, storage, now)['status'] == 'metadata-current', 'queue recovery metadata changed')
                require(verified_worker() == binding, 'queue worker changed before recovery post')
            return emit(pending, recheck)
        else:
            return {'notifications':0, 'reconciled':reconciled}
    for existing in document['events']:
        if existing['key'] == pending['key']:
            require(notice(existing).lookup() == existing['message_id'], 'queue existing receipt no longer verifiable')
            return {'notifications':0, 'reconciled':reconciled}
    return emit(pending)


def build_config(env):
    """Only named protected variables; never serialize credentials or user input."""
    def value(key, limit=255):
        text = env.get(key)
        require(type(text) is str and len(text) <= limit, 'queue protected variable absent or too large')
        return text
    def flag(key):
        text = value(key, 5); require(text in {'true', 'false'}, 'queue protected boolean invalid')
        return text == 'true'
    require(flag('FACTORY_REPORTING_ENABLED') and flag('FACTORY_REPORTING_QUEUE_ENABLED') and value('FACTORY_REPORTING_PROFILE') == 'github-hosted', 'queue protected policy disabled')
    config = {'enabled':True, 'queue_monitor_enabled':True, 'repository':value('GITHUB_REPOSITORY'), 'state_repository':value('FACTORY_REPORTING_STATE_REPOSITORY'), 'branch':value('FACTORY_REPORTING_BRANCH'), 'destination':value('FACTORY_REPORTING_CHANNEL'), 'team_id':value('FACTORY_REPORTING_TEAM_ID')}
    grace = value('FACTORY_REPORTING_QUEUE_GRACE_MINUTES', 4)
    require(re.fullmatch(r'[0-9]{2,4}', grace) is not None, 'queue protected grace invalid')
    config['grace_minutes'] = int(grace)
    validate_config(config, repository=config['repository'], default_branch=config['branch'])
    raw = value('FACTORY_REPORTING_POLICY_APPROVALS', MAX_BYTES)
    require(len(raw.encode()) <= MAX_BYTES, 'queue approvals byte bound exceeded')
    def pairs(items):
        result = {}
        for key, item in items:
            require(key not in result, 'queue approval JSON duplicate key'); result[key] = item
        return result
    try:
        approvals = json.loads(raw, object_pairs_hook=pairs)
    except (ValueError, RecursionError, UnicodeError) as error:
        raise ValueError('queue approval JSON invalid') from error
    storage = {'state_branch':value('FACTORY_REPORTING_STATE_BRANCH'), 'bootstrap_sha':value('FACTORY_REPORTING_QUEUE_BOOTSTRAP_SHA'), 'initialize':flag('FACTORY_REPORTING_QUEUE_INITIALIZE'), 'policy_approvals':approvals}
    # Constructor validates the complete bounded storage shape without any IO.
    class Identity:
        repo = config['repository']
    QueueStore(Identity(), config, storage)
    start = value('FACTORY_REPORTING_START', 40)
    require(string(start, r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|[+-][0-9]{2}:[0-9]{2})', 40) and (start.endswith('Z') or (int(start[-5:-3]) < 24 and int(start[-2:]) < 60)), 'queue protected start invalid')
    try:
        require(datetime.fromisoformat(start.replace('Z', '+00:00')).astimezone(timezone.utc) <= datetime.now(timezone.utc), 'queue protected start future')
    except (ValueError, OverflowError) as error:
        raise ValueError('queue protected start invalid') from error
    reporting = {key:config[key] for key in ('enabled', 'repository', 'state_repository', 'branch', 'destination', 'team_id')}
    reporting.update(start=start, attachments_enabled=flag('FACTORY_REPORTING_ATTACHMENTS_ENABLED'))
    writer_flag=env.get('FACTORY_REPORTING_APP_WRITER_ENABLED','false')
    require(writer_flag in ('true','false'),'reporting writer flag invalid')
    if writer_flag=='true':
        import importlib.util
        from pathlib import Path
        spec=importlib.util.spec_from_file_location('queue_config_transport',Path(__file__).with_name('factory-reporting-transport.py'))
        transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
        context=transport.attach_reporting_context(dict(reporting,state_branch=storage['state_branch']))
        storage['state_view']=context['state_view']
    return {'config':config, 'storage':storage, 'reporting':reporting}


def execution_context(env, config, checkout_sha, drill):
    """Validate immutable protected invocation before creating clients or effects."""
    require(type(drill) is bool and env.get('GITHUB_ACTIONS') == 'true' and env.get('RUNNER_ENVIRONMENT') == 'github-hosted' and env.get('GITHUB_SERVER_URL') == 'https://github.com' and env.get('GITHUB_API_URL') == 'https://api.github.com', 'queue execution platform differs')
    require(env.get('GITHUB_REF') == 'refs/heads/'+config['branch'] and env.get('GITHUB_WORKFLOW_REF') == config['repository']+'/.github/workflows/factory-reporting-queue.yml@refs/heads/'+config['branch'], 'queue protected workflow ref differs')
    require(string(checkout_sha, r'[0-9a-f]{40}', 40) and checkout_sha == env.get('GITHUB_SHA') == env.get('GITHUB_WORKFLOW_SHA'), 'queue protected checkout differs')
    event = env.get('GITHUB_EVENT_NAME')
    require(type(event) is str and event in {'schedule', 'workflow_dispatch'} and (not drill or event == 'workflow_dispatch'), 'queue execution event differs')
    values = []
    for key in ('GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT'):
        text = env.get(key)
        require(string(text, r'[1-9][0-9]{0,18}', 19) and int(text) < 2**63, 'queue execution identity invalid')
        values.append(int(text))
    return event, values[0], values[1]


class RoutedAPI:
    """Actions GET uses the workflow token; state transport keeps its existing key."""
    def __init__(self, repository, actions, state):
        require(actions.repo == state.repo == repository, 'queue credential repository differs')
        self.repo = repository; self.actions = actions; self.state = state
    def request(self, path, method='GET', payload=None):
        require(type(path) is str and (path == 'repos/'+self.repo or path.startswith('repos/'+self.repo+'/')) and '..' not in path and '%' not in path.replace('%2F', '') and '#' not in path and '\\' not in path, 'queue credential foreign endpoint')
        if path.startswith('repos/'+self.repo+'/actions/'):
            require(method == 'GET' and payload is None, 'queue Actions API is read only')
            return self.actions.request(path, method, payload)
        return self.state.request(path, method, payload)


def protected_entry(env, api, client, checkout_sha, now, *, drill=False):
    built = build_config(env); config = built['config']
    event, run_id, attempt = execution_context(env, config, checkout_sha, drill)
    require(api.repo == config['repository'], 'queue protected API repository differs')
    prefix = 'repos/'+api.repo
    repository = api.request(prefix)
    workflow = api.request(prefix+'/actions/workflows/factory-reporting-queue.yml')
    run = api.request(prefix+'/actions/runs/'+str(run_id))
    require(all(type(row) is dict for row in (repository, workflow, run)), 'queue protected metadata invalid')
    require(type(repository.get('id')) is int and 0 < repository['id'] < 2**63 and repository.get('full_name') == api.repo and repository.get('default_branch') == config['branch'], 'queue protected repository differs')
    require(type(workflow.get('id')) is int and 0 < workflow['id'] < 2**63 and workflow.get('path') == '.github/workflows/factory-reporting-queue.yml' and workflow.get('state') == 'active', 'queue protected workflow differs')
    require(all(type(run.get(key)) is int and 0 < run[key] < 2**63 for key in ('id', 'workflow_id', 'run_attempt')) and run['id'] == run_id and run['workflow_id'] == workflow['id'] and run['run_attempt'] == attempt, 'queue protected run identity differs')
    require(run.get('path') == workflow['path'] and run.get('event') == event and run.get('status') == 'in_progress' and run.get('conclusion') is None and run.get('head_branch') == config['branch'] and run.get('head_sha') == checkout_sha, 'queue protected source differs')
    require(all(type(run.get(key)) is dict and type(run[key].get('id')) is int and run[key]['id'] == repository['id'] and run[key].get('full_name') == api.repo for key in ('repository', 'head_repository')), 'queue protected run repository differs')
    return run_queue(api, client, config, built['storage'], built['reporting'], now, drill_run=run_id if drill else None)


def main():
    import argparse, importlib.util, os, subprocess
    from pathlib import Path
    parser = argparse.ArgumentParser(); parser.add_argument('--drill', action='store_true'); args = parser.parse_args()
    writer_flag=os.environ.get('FACTORY_REPORTING_APP_WRITER_ENABLED','false')
    require(writer_flag in ('true','false'),'reporting writer flag invalid')
    api=None
    if writer_flag=='true':
        spec=importlib.util.spec_from_file_location('queue_transport',Path(__file__).with_name('factory-reporting-transport.py'))
        transport=importlib.util.module_from_spec(spec);spec.loader.exec_module(transport)
        api=transport.create_api(os.environ)
    built = build_config(os.environ)
    checkout = subprocess.run(['git', 'rev-parse', '--verify', 'HEAD'], check=True, capture_output=True, text=True, timeout=10).stdout.strip()
    execution_context(os.environ, built['config'], checkout, args.drill)
    module = importlib.util.spec_from_file_location('queue_entry_state', Path(__file__).with_name('factory-git-state.py'))
    state = importlib.util.module_from_spec(module); module.loader.exec_module(state)
    if writer_flag=='false':
        actions = state.API(built['config']['repository'], os.environ.get('GH_TOKEN'))
        writer = state.API(built['config']['repository'], os.environ.get('FACTORY_REPORTING_STATE_TOKEN') or os.environ.get('GH_TOKEN'))
        api = RoutedAPI(built['config']['repository'], actions, writer)
    result = protected_entry(os.environ, api, state.slack.http_client(built['reporting']), checkout, datetime.now(timezone.utc), drill=args.drill)
    print(json.dumps(result, sort_keys=True)); return 0


if __name__ == '__main__':
    import sys
    try:
        sys.exit(main())
    except Exception:
        print('Queue monitor blocked; preserve intent and inspect protected run before retry.', file=sys.stderr)
        sys.exit(2)
