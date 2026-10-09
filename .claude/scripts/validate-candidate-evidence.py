#!/usr/bin/env python3
"""Validate candidate-bound evidence against a separately authenticated context.

This validates structure and policy consistency, not authenticity. Only a
protected coordinator may obtain context and receipts from trusted APIs.
"""
import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import sys

BINDING = {'schema_version', 'repository', 'pull_request', 'head_sha', 'base_sha', 'spec_sha256', 'policy_sha256'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def object_keys(value, expected, label):
    require(isinstance(value, dict) and set(value) == expected, f'{label}: incorrect fields')


def digest(value, size):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{%d}' % size, value) is not None


def identity(value):
    return isinstance(value, str) and bool(value.strip()) and value == value.strip()


def integer(value):
    return type(value) is int and value > 0


def stamp(value):
    require(isinstance(value, str) and value.endswith('Z'), 'timestamp must be UTC with Z suffix')
    return datetime.fromisoformat(value[:-1] + '+00:00')


def unique_map(values, key, label):
    require(isinstance(values, list), f'{label}: array required')
    result = {}
    for value in values:
        require(isinstance(value, dict) and identity(value.get(key)), f'{label}: invalid identity')
        require(value[key] not in result, f'{label}: duplicate identity')
        result[value[key]] = value
    return result


def validate(context, evidence):
    object_keys(context, BINDING | {'ac_ids', 'implementer', 'allowed_verifiers', 'allowed_reviewers',
                                   'required_checks', 'window_start', 'window_end'}, 'context')
    object_keys(evidence, BINDING | {'generated_at', 'acceptance', 'checks', 'verification', 'review'}, 'evidence')
    require(type(context['schema_version']) is int and context['schema_version'] == 1, 'unsupported schema version')
    require(identity(context['repository']) and integer(context['pull_request']), 'invalid repository or pull request')
    for key in ('head_sha', 'base_sha'):
        require(digest(context[key], 40), f'{key}: commit SHA required')
    for key in ('spec_sha256', 'policy_sha256'):
        require(digest(context[key], 64), f'{key}: SHA-256 required')
    for key in BINDING:
        require(type(evidence[key]) is type(context[key]) and evidence[key] == context[key], f'{key}: candidate binding mismatch')
    acs = context['ac_ids']
    require(isinstance(acs, list) and bool(acs) and all(isinstance(ac, str) and re.fullmatch(r'AC-\d+', ac) for ac in acs), 'nonempty AC set required')
    require(len(set(acs)) == len(acs), 'duplicate expected AC')
    observed = unique_map(evidence['acceptance'], 'id', 'acceptance')
    require(set(observed) == set(acs), 'acceptance must cover exactly the approved AC set')
    for result in observed.values():
        object_keys(result, {'id', 'status', 'artifact_sha256'}, 'acceptance observation')
        require(result['status'] == 'pass' and digest(result['artifact_sha256'], 64), 'passing observation and artifact digest required')
    checks = context['required_checks']
    require(isinstance(checks, dict) and bool(checks) and all(identity(name) and integer(app) for name, app in checks.items()), 'required check producers missing')
    receipts = unique_map(evidence['checks'], 'name', 'check receipts')
    require(set(receipts) == set(checks), 'receipts must cover exactly the required checks')
    run_ids = set()
    for name, receipt in receipts.items():
        object_keys(receipt, {'name', 'head_sha', 'app_id', 'run_id', 'status', 'conclusion'}, 'check receipt')
        require(receipt['head_sha'] == context['head_sha'], 'check receipt is for a different candidate')
        require(integer(receipt['app_id']) and receipt['app_id'] == checks[name], 'untrusted check producer')
        require(integer(receipt['run_id']) and receipt['run_id'] not in run_ids, 'invalid or duplicate check run ID')
        run_ids.add(receipt['run_id'])
        require(receipt['status'] == 'completed' and receipt['conclusion'] == 'success', 'required check not successful')
    require(identity(context['implementer']), 'implementer identity required')
    actors = []
    for role, allowed_key in [('verification', 'allowed_verifiers'), ('review', 'allowed_reviewers')]:
        allowed = context[allowed_key]
        require(isinstance(allowed, list) and bool(allowed) and all(identity(actor) for actor in allowed), 'allowed authority identities required')
        verdict = evidence[role]
        object_keys(verdict, {'actor', 'head_sha', 'verdict', 'unresolved_findings'}, role)
        require(identity(verdict['actor']) and verdict['actor'] in allowed, f'{role}: untrusted actor')
        require(verdict['actor'] != context['implementer'] and verdict['actor'] not in actors, 'independent actors required')
        actors.append(verdict['actor'])
        require(verdict['head_sha'] == context['head_sha'] and verdict['verdict'] == 'pass', f'{role}: invalid candidate verdict')
        require(verdict['unresolved_findings'] == [], f'{role}: unresolved findings')
    start, end, generated = map(stamp, (context['window_start'], context['window_end'], evidence['generated_at']))
    require(start <= generated <= end and start < end, 'evidence outside trusted run window')


def no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f'duplicate JSON key: {key}')
        result[key] = value
    return result


def load(path):
    return json.loads(path.read_text(), object_pairs_hook=no_duplicate_keys,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f'invalid JSON number: {value}')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--context', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    validate(load(args.context), load(args.evidence))
    print('candidate evidence: structurally valid; authenticity must be established by protected coordinator')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, TypeError, OSError) as error:
        print(f'candidate evidence: FAIL: {error}', file=sys.stderr)
        sys.exit(1)
