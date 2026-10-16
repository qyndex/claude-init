#!/usr/bin/env python3
"""Pure bounded queue-journal contracts; validation grants no storage origin."""
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
        require(type(storage) is dict and len(storage) == 4 and set(storage) == {'state_branch', 'bootstrap_sha', 'initialize', 'policy_approvals'}, 'queue storage fields differ')
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
        self.source = api; self.repo = api.repo; self.config = json.loads(canonical(config)); self.storage = json.loads(canonical(storage))
        self.identity = stream(config); self.calls = self.consumed = 0

    def request(self, path, method='GET', payload=None):
        require(path == 'repos/'+self.repo or path.startswith('repos/'+self.repo+'/'), 'queue storage foreign API')
        require(self.calls < 128, 'queue storage API bound exceeded'); self.calls += 1
        # Production state.API bounds stdout before JSON parse; preserve that transport bound.
        value = self.source.request(path, method, payload)
        size = len(canonical(value)); self.consumed += size
        require(size <= self.state.MAX_STATE*2 and self.consumed <= 33554432, 'queue storage observation bound exceeded')
        return value

    def _load(self):
        repository = self.request('repos/'+self.repo)
        require(type(repository) is dict and repository.get('full_name') == self.repo, 'queue storage repository differs')
        validate_config(self.config, repository=self.repo, default_branch=repository.get('default_branch'))
        try:
            current = self.state.GitState(self, self.storage['state_branch'], self.identity,
                                          self.storage['bootstrap_sha'], self.storage['policy_approvals'],
                                          bootstrap_existing=self.storage['initialize'])
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
