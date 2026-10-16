#!/usr/bin/env python3
"""Reporting-only exact administrative writer observations, not attestations."""
import argparse
import importlib.util
import math
from pathlib import Path
import re

_spec = importlib.util.spec_from_file_location('reporting_policy_metadata', Path(__file__).with_name('factory-policy-observation.py'))
metadata = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(metadata)
require = metadata.require
MAX_BYTES = metadata.MAX_BYTES
SIDECAR = 'receipt-policy-observations.json'
FIELDS = metadata.FIELDS | {'branch', 'writer_app_id', 'role'}
PACKET_FIELDS = {'schema_version', 'repository', 'repository_id', 'branch', 'writer_app_id', 'policies'}


def _bounded(value):
    """Bound the queued frontier before canonicalizing arbitrary nested metadata."""
    stack = [value]; nodes = size = 0
    while stack:
        item = stack.pop(); nodes += 1
        if type(item) is dict:
            require(all(type(key) is str for key in item), 'reporting observation JSON keys invalid')
            require(nodes + len(stack) + 2*len(item) <= 8192, 'reporting observation node bound exceeded')
            for key, child in item.items():
                stack.append(key); stack.append(child)
        elif type(item) is list:
            require(nodes + len(stack) + len(item) <= 8192, 'reporting observation node bound exceeded')
            stack.extend(item)
        elif type(item) is str:
            require(len(item) <= MAX_BYTES, 'reporting observation string bound exceeded')
            try:
                size += len(item.encode())
            except UnicodeError as error:
                raise ValueError('reporting observation UTF-8 invalid') from error
        elif type(item) is int:
            require(abs(item) < 2**63, 'reporting observation integer bound exceeded')
        elif type(item) is float:
            require(math.isfinite(item), 'reporting observation number invalid')
        else:
            require(item is None or type(item) is bool, 'reporting observation JSON type invalid')
        require(nodes <= 8192 and size <= MAX_BYTES, 'reporting observation bound exceeded')


def _canonical(value):
    _bounded(value)
    raw = metadata.canonical(value)
    require(len(raw) <= MAX_BYTES, 'reporting observation bound exceeded')
    return raw


def _binding(repository, repository_id, branch, writer_app_id):
    require(type(repository) is str and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository)
            and all(part not in ('.', '..') for part in repository.split('/')), 'reporting observation repository invalid')
    require(type(repository_id) is int and 0 < repository_id < 2**63, 'reporting observation repository ID invalid')
    require(type(writer_app_id) is int and 0 < writer_app_id < 2**63, 'reporting observation writer invalid')
    require(type(branch) is str and 0 < len(branch) <= 200
            and all(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', part) and '..' not in part
                    and not part.endswith(('.', '.lock')) for part in branch.split('/')), 'reporting observation branch invalid')


def _role(repo, policy, branch, writer_app_id):
    require(type(repo) is dict, 'reporting observation repository required')
    _binding(repo.get('full_name'), repo.get('id'), branch, writer_app_id)
    _bounded(policy)
    digest = metadata.identity(repo, policy)
    require(policy['conditions'] == {'ref_name': {'include': ['refs/heads/'+branch], 'exclude': []}},
            'reporting policy scope differs')
    kinds = [rule.get('type') for rule in policy['rules']]
    require(all(type(kind) is str for kind in kinds), 'reporting policy rules invalid')
    if 'update' in kinds:
        require(policy['rules'] == [{'type': 'update'}], 'reporting writer must be update-only')
        return 'update', digest
    require(kinds and len(set(kinds)) == len(kinds) and set(kinds) <= {'deletion', 'non_fast_forward'}
            and all(rule.keys() == {'type'} for rule in policy['rules']), 'reporting protection rules invalid')
    return 'protection', digest


def _actors(value, role, writer_app_id):
    expected = [{'actor_id': writer_app_id, 'actor_type': 'Integration', 'bypass_mode': 'always'}] if role == 'update' else []
    require(type(value) is list and all(type(actor) is dict and actor.keys() == {'actor_id', 'actor_type', 'bypass_mode'}
            and type(actor['actor_id']) is int and 0 < actor['actor_id'] < 2**63 for actor in value)
            and value == expected, 'reporting policy actors differ')


def _record(value, repository, repository_id, branch, writer_app_id):
    require(type(value) is dict and value.keys() == FIELDS, 'complete reporting observation required')
    _canonical(value)
    require(type(value['schema_version']) is int and value['schema_version'] == 1
            and type(value['repository_id']) is int and value['repository_id'] == repository_id
            and value['repository'] == repository and type(value['ruleset_id']) is int and 0 < value['ruleset_id'] < 2**63
            and value['branch'] == branch and type(value['writer_app_id']) is int and value['writer_app_id'] == writer_app_id
            and value['role'] in ('update', 'protection')
            and type(value['metadata_sha256']) is str and re.fullmatch(r'[0-9a-f]{64}', value['metadata_sha256']),
            'reporting observation binding invalid')
    _actors(value['bypass_actors'], value['role'], writer_app_id)
    updated = metadata.timestamp(value['updated_at']); observed = metadata.timestamp(value['observed_at'])
    require((observed - updated).total_seconds() >= 60, 'reporting observation not settled')
    return updated, observed


def capture(repo, policy, branch, writer_app_id, *, now=None):
    role, digest = _role(repo, policy, branch, writer_app_id)
    require('bypass_actors' in policy, 'actual explicit reporting actors required')
    _actors(policy['bypass_actors'], role, writer_app_id)
    observed = metadata.clock(now)
    require((observed - metadata.timestamp(policy['updated_at'])).total_seconds() >= 60, 'reporting policy must settle')
    result = {'schema_version': 1, 'repository': repo['full_name'], 'repository_id': repo['id'],
              'ruleset_id': policy['id'], 'branch': branch, 'writer_app_id': writer_app_id, 'role': role,
              'metadata_sha256': digest, 'updated_at': policy['updated_at'], 'observed_at': observed.isoformat(),
              'bypass_actors': [dict(actor) for actor in policy['bypass_actors']]}
    _record(result, repo['full_name'], repo['id'], branch, writer_app_id)
    return result


def validate(repo, policy, branch, writer_app_id, observation=None, *, now=None):
    role, digest = _role(repo, policy, branch, writer_app_id)
    current = metadata.clock(now)
    require((current - metadata.timestamp(policy['updated_at'])).total_seconds() >= 60, 'reporting policy must settle')
    if 'bypass_actors' in policy:
        _actors(policy['bypass_actors'], role, writer_app_id)
        return {'mode': 'direct', 'metadata_sha256': digest}
    updated, observed = _record(observation, repo['full_name'], repo['id'], branch, writer_app_id)
    require(observation['ruleset_id'] == policy['id'] and observation['role'] == role
            and observation['metadata_sha256'] == digest and updated == metadata.timestamp(policy['updated_at']),
            'reporting observation metadata changed or foreign')
    require(observed <= current, 'reporting observation future timestamp')
    return {'mode': 'operator-observation', 'metadata_sha256': digest,
            'observation_sha256': metadata.hashlib.sha256(_canonical(observation)).hexdigest()}


def load(path, repository, repository_id, branch, writer_app_id, *, now=None):
    _binding(repository, repository_id, branch, writer_app_id)
    try:
        with Path(path).open('rb') as stream:
            raw = stream.read(MAX_BYTES + 1)
    except OSError as error:
        raise ValueError('protected reporting observations unavailable') from error
    try:
        packet = metadata.decode(raw)
    except (ValueError, TypeError) as error:
        raise ValueError('reporting observation document invalid') from error
    _canonical(packet)
    require(packet.keys() == PACKET_FIELDS and type(packet['schema_version']) is int and packet['schema_version'] == 1
            and packet['repository'] == repository and type(packet['repository_id']) is int and packet['repository_id'] == repository_id
            and packet['branch'] == branch and type(packet['writer_app_id']) is int and packet['writer_app_id'] == writer_app_id
            and type(packet['policies']) is dict and 0 < len(packet['policies']) <= 16, 'reporting observation document binding differs')
    for identity, value in packet['policies'].items():
        require(type(identity) is str and re.fullmatch(r'[1-9][0-9]{0,18}', identity), 'reporting observation identity invalid')
        _, observed = _record(value, repository, repository_id, branch, writer_app_id)
        require(observed <= metadata.clock(now), 'reporting observation future timestamp')
        require(int(identity) == value['ruleset_id'], 'reporting observation identity differs')
    return packet['policies']


def observe(api, repository, ruleset_id, branch, writer_app_id, *, now=None):
    _binding(repository, 1, branch, writer_app_id)
    require(type(ruleset_id) is int and 0 < ruleset_id < 2**63, 'reporting ruleset identity invalid')
    repo = api.get('repos/'+repository)
    policy = api.get('repos/'+repository+'/rulesets/'+str(ruleset_id))
    require(type(repo) is dict and repo.get('full_name') == repository and type(policy) is dict
            and type(policy.get('id')) is int and policy['id'] == ruleset_id, 'reporting observed scope differs')
    return capture(repo, policy, branch, writer_app_id, now=now)


def main():
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--ruleset-id', type=int, required=True)
    parser.add_argument('--branch', required=True)
    parser.add_argument('--writer-app-id', type=int, required=True)
    args = parser.parse_args()
    print(_canonical(observe(metadata.GitHub(), args.repository, args.ruleset_id, args.branch, args.writer_app_id)).decode())


if __name__ == '__main__':
    main()
