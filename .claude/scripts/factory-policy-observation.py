#!/usr/bin/env python3
"""Exact administrative observations; not portable native attestation proof."""
import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys

MAX_BYTES = 262144
SEMANTIC = {'id', 'node_id', 'name', 'source', 'source_type', 'target',
            'enforcement', 'created_at', 'updated_at', 'conditions', 'rules'}
TRANSPORT = {'_links', 'current_user_can_bypass', 'bypass_actors'}
FIELDS = {'schema_version', 'repository', 'repository_id', 'ruleset_id',
          'metadata_sha256', 'updated_at', 'observed_at', 'bypass_actors'}


def require(value, message):
    if not value:
        raise ValueError(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def decode(raw):
    require(type(raw) is bytes and len(raw) <= MAX_BYTES, 'observation input bound exceeded')
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    try:
        value = json.loads(raw, object_pairs_hook=pairs,
                           parse_constant=lambda value: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ValueError('invalid observation JSON') from exc
    require(type(value) is dict, 'JSON object required')
    return value


def timestamp(value):
    require(type(value) is str and len(value) <= 40, 'invalid observation timestamp')
    # GitHub timestamps are aware ISO dates with supported millisecond/microsecond
    # precision. fromisoformat alone silently truncates longer fractions and can
    # normalize invalid offset minutes; reject those representations first.
    match = re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|[+-](?P<hour>[0-9]{2}):(?P<minute>[0-9]{2}))', value)
    require(match is not None and (match['hour'] is None or (int(match['hour']) < 24 and int(match['minute']) < 60)), 'invalid observation timestamp')
    try:
        parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
        return parsed.astimezone(dt.timezone.utc)
    except (ValueError, OverflowError) as exc:
        raise ValueError('invalid observation timestamp') from exc


def identity(repo, rules):
    require(type(repo) is dict and type(repo.get('id')) is int and repo['id'] > 0,
            'repository ID required')
    name = repo.get('full_name')
    require(type(name) is str and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', name)
            and all(part not in ('.', '..') for part in name.split('/')), 'repository identity invalid')
    require(type(rules) is dict and SEMANTIC <= rules.keys()
            and rules.keys() <= SEMANTIC | TRANSPORT, 'complete known ruleset metadata required')
    require(type(rules['id']) is int and rules['id'] > 0 and rules['source'] == name
            and rules['source_type'] == 'Repository' and rules['target'] == 'branch'
            and rules['enforcement'] == 'active', 'foreign or inactive ruleset')
    require(all(type(rules[k]) is str and rules[k] for k in ('name', 'node_id'))
            and type(rules['conditions']) is dict and type(rules['rules']) is list
            and all(type(rule) is dict for rule in rules['rules']), 'malformed ruleset metadata')
    timestamp(rules['created_at']); timestamp(rules['updated_at'])
    projection = {key: rules[key] for key in SEMANTIC}
    for key in ('created_at', 'updated_at'):
        projection[key] = timestamp(rules[key]).isoformat(timespec='microseconds')
    try:
        raw = canonical(projection)
    except (ValueError, TypeError, RecursionError) as exc:
        raise ValueError('invalid ruleset projection') from exc
    require(len(raw) <= MAX_BYTES, 'ruleset metadata bound exceeded')
    return hashlib.sha256(raw).hexdigest()


def failure_diagnostic(repo, rules, observation=None):
    """Bounded component fingerprints, never approval or raw policy/actor output.

    Any diagnostic error returns a fixed inert category. Callers must preserve
    the original validation rejection even if diagnostic construction fails.
    """
    unavailable = {'schema_version': 1, 'reason': 'diagnostic-unavailable'}
    try:
        require(type(rules) is dict, 'rules object required')
        projection = {key: rules[key] for key in SEMANTIC if key in rules}
        # Bound traversal before canonical serialization or per-field hashing.
        stack = [(projection, 0)]; nodes = 0; string_bytes = 0
        while stack:
            value, depth = stack.pop(); nodes += 1
            require(nodes <= 8192 and depth <= 32, 'diagnostic structure bound')
            if type(value) is str:
                require(len(value) <= MAX_BYTES, 'diagnostic string bound')
                string_bytes += len(value.encode('utf-8'))
                require(string_bytes <= MAX_BYTES, 'diagnostic byte bound')
            elif type(value) is dict:
                require(len(value) <= 8192 and all(type(k) is str for k in value), 'diagnostic object bound')
                require(nodes + len(stack) + 2*len(value) <= 8192, 'diagnostic queued node bound')
                stack.extend((child, depth+1) for pair in value.items() for child in pair)
            elif type(value) is list:
                require(len(value) <= 8192, 'diagnostic list bound')
                require(nodes + len(stack) + len(value) <= 8192, 'diagnostic queued node bound')
                stack.extend((child, depth+1) for child in value)
            else:
                require(value is None or type(value) in (int, float, bool), 'diagnostic value type')
                if type(value) is int:
                    require(value.bit_length() <= 256, 'diagnostic number bound')
        require(len(canonical(projection)) <= MAX_BYTES, 'diagnostic serialization bound')
        components = {key: ({'status': 'present', 'sha256': hashlib.sha256(canonical(rules[key])).hexdigest()}
                            if key in rules else {'status': 'missing'}) for key in sorted(SEMANTIC)}
        timestamps = {}
        for key in ('created_at', 'updated_at'):
            try:
                timestamps[key] = {'raw': rules[key], 'utc': timestamp(rules[key]).isoformat()}
            except (KeyError, ValueError, TypeError):
                timestamps[key] = {'status': 'invalid'}
        try:
            actual = identity(repo, rules)
        except (ValueError, KeyError, TypeError):
            actual = None
        expected = observation.get('metadata_sha256') if type(observation) is dict else None
        if type(expected) is not str or re.fullmatch(r'[0-9a-f]{64}', expected) is None:
            expected = None
        name = repo.get('full_name') if type(repo) is dict else None
        if type(name) is not str or re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', name) is None:
            name = None
        repository_id = repo.get('id') if type(repo) is dict else None
        ruleset_id = rules.get('id')
        observed = observation if type(observation) is dict else {}
        try:
            expected_updated = {'raw': observed.get('updated_at'), 'utc': timestamp(observed.get('updated_at')).isoformat()}
        except (ValueError, TypeError):
            expected_updated = {'status': 'invalid'}
        def identifier(value):
            return value if type(value) is int and 0 < value < 2**63 else None
        def same(left, right):
            return left == right if left is not None and right is not None else None
        expected_name = observed.get('repository')
        if type(expected_name) is not str or len(expected_name) > 256 or re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', expected_name) is None:
            expected_name = None
        matches = {'repository': same(name, expected_name),
                   'repository_id': same(identifier(repository_id), identifier(observed.get('repository_id'))),
                   'ruleset_id': same(identifier(ruleset_id), identifier(observed.get('ruleset_id'))),
                   'metadata_sha256': same(actual, expected),
                   'updated_at_raw': same(timestamps['updated_at'].get('raw'), expected_updated.get('raw')),
                   'updated_at_instant': same(timestamps['updated_at'].get('utc'), expected_updated.get('utc'))}
        result = {'schema_version': 1, 'reason': 'validation-rejected',
                  'repository': name,
                  'repository_id': repository_id if type(repository_id) is int and 0 < repository_id < 2**63 else None,
                  'ruleset_id': ruleset_id if type(ruleset_id) is int and 0 < ruleset_id < 2**63 else None,
                  'metadata_sha256': actual, 'expected_metadata_sha256': expected,
                  'components': components, 'timestamps': timestamps,
                  'expected_updated_at': expected_updated, 'matches': matches}
        require(len(canonical(result)) <= 8192, 'diagnostic output bound')
        return result
    except Exception:
        return unavailable


def rejection_category(error):
    """Describe the original authoritative failure; never decide acceptance."""
    categories = {
        'complete observation required': 'observation-incomplete',
        'observation bound exceeded': 'observation-oversize',
        'observation schema invalid': 'observation-schema',
        'observation metadata changed or foreign': 'metadata-mismatch',
        'observation must record empty actors': 'observation-actors',
        'observation unsettled or future': 'observation-clock',
        'invalid observation timestamp': 'timestamp-invalid',
        'timezone required': 'timestamp-invalid',
        'repository ID required': 'repository-invalid',
        'repository identity invalid': 'repository-invalid',
        'complete known ruleset metadata required': 'ruleset-invalid',
        'foreign or inactive ruleset': 'ruleset-invalid',
        'malformed ruleset metadata': 'ruleset-invalid',
        'invalid ruleset projection': 'ruleset-invalid',
        'ruleset metadata bound exceeded': 'ruleset-invalid',
        'visible bypass actors nonempty or malformed': 'visible-actors-invalid',
    }
    if type(error) is ValueError and len(error.args) == 1 and type(error.args[0]) is str and len(error.args[0]) <= 128:
        return categories.get(error.args[0], 'unexpected-validation-error')
    return 'unexpected-validation-error'


def clock(now):
    value = now if now is not None else dt.datetime.now(dt.timezone.utc)
    require(isinstance(value, dt.datetime) and value.tzinfo is not None, 'aware current time required')
    return value.astimezone(dt.timezone.utc)


def capture(repo, rules, *, now=None):
    digest = identity(repo, rules)
    require('bypass_actors' in rules and type(rules['bypass_actors']) is list
            and rules['bypass_actors'] == [], 'actual explicit empty bypass actors required')
    observed = clock(now)
    require(observed >= timestamp(rules['updated_at']) + dt.timedelta(seconds=60), 'ruleset not settled')
    return {'schema_version': 1, 'repository': repo['full_name'], 'repository_id': repo['id'],
            'ruleset_id': rules['id'], 'metadata_sha256': digest,
            'updated_at': rules['updated_at'], 'observed_at': observed.isoformat(), 'bypass_actors': []}


def validate(repo, rules, observation=None, *, now=None):
    digest = identity(repo, rules)
    if 'bypass_actors' in rules:
        require(type(rules['bypass_actors']) is list and rules['bypass_actors'] == [],
                'visible bypass actors nonempty or malformed')
        return {'mode': 'direct', 'metadata_sha256': digest}
    require(type(observation) is dict and observation.keys() == FIELDS, 'complete observation required')
    require(len(canonical(observation)) <= MAX_BYTES, 'observation bound exceeded')
    require(type(observation['schema_version']) is int and observation['schema_version'] == 1
            and type(observation['repository_id']) is int and type(observation['ruleset_id']) is int,
            'observation schema invalid')
    require(observation['repository'] == repo['full_name'] and observation['repository_id'] == repo['id']
            and observation['ruleset_id'] == rules['id'] and observation['metadata_sha256'] == digest
            and timestamp(observation['updated_at']) == timestamp(rules['updated_at']), 'observation metadata changed or foreign')
    require(type(observation['bypass_actors']) is list and observation['bypass_actors'] == [],
            'observation must record empty actors')
    observed = timestamp(observation['observed_at'])
    require(timestamp(rules['updated_at']) + dt.timedelta(seconds=60) <= observed <= clock(now),
            'observation unsettled or future')
    return {'mode': 'operator-observation', 'metadata_sha256': digest,
            'observation_sha256': hashlib.sha256(canonical(observation)).hexdigest()}


def observe(api, repository, ruleset_id, *, now=None):
    require(type(repository) is str and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository)
            and all(part not in ('.', '..') for part in repository.split('/')), 'repository identity invalid')
    require(type(ruleset_id) is int and ruleset_id > 0, 'ruleset ID invalid')
    root = f'repos/{repository}'
    repo = api.get(root)
    rules = api.get(f'{root}/rulesets/{ruleset_id}')
    require(type(repo) is dict and type(rules) is dict
            and repo.get('full_name') == repository and rules.get('id') == ruleset_id, 'foreign API response')
    return capture(repo, rules, now=now)


class GitHub:
    def get(self, path):
        require(re.fullmatch(r'repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/rulesets/[1-9][0-9]*)?', path),
                'fixed GitHub GET path required')
        location = Path(__file__).with_name('factory-bounded-process.py')
        spec = importlib.util.spec_from_file_location('bounded', location)
        bounded = importlib.util.module_from_spec(spec); spec.loader.exec_module(bounded)
        env = {key: value for key, value in os.environ.items()
               if key in ('PATH', 'HOME', 'GH_TOKEN', 'GITHUB_TOKEN', 'GH_CONFIG_DIR')}
        env.update(GH_HOST='github.com', GH_PROMPT_DISABLED='1', GH_PAGER='cat')
        result = bounded.run(['gh', 'api', '--hostname', 'github.com', '--method', 'GET', path],
                             env=env, cwd=str(Path.cwd()), timeout=30, limit=MAX_BYTES,
                             aggregate_limit=MAX_BYTES)
        require(result.returncode == 0, 'GitHub observation GET failed')
        return decode(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['observe'])
    parser.add_argument('--repository', required=True)
    parser.add_argument('--ruleset-id', type=int, required=True)
    args = parser.parse_args()
    try:
        print(canonical(observe(GitHub(), args.repository, args.ruleset_id)).decode())
    except (ValueError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
