#!/usr/bin/env python3
"""Apply an externally authenticated, exact-source audit registry to gated facts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys


def require(condition):
    if not condition:
        raise ValueError('invalid or unauthenticated audit policy')


def unique(items):
    result = {}
    for key, value in items:
        require(key not in result)
        result[key] = value
    return result


def decode(raw):
    def invalid_constant(_):
        raise ValueError('nonfinite JSON constant')
    return json.loads(raw, object_pairs_hook=unique, parse_constant=invalid_constant)


def relative(value):
    require(isinstance(value, str) and re.fullmatch(r'[A-Za-z0-9_./-]+', value)
            and not value.startswith('/') and all(part not in {'', '.', '..'} for part in value.split('/')))
    return value


def digest_source(root, path):
    """Walk directory descriptors without following any candidate symlinks."""
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        parts = relative(path).split('/')
        for part in parts[:-1]:
            following = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = following
        file = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=descriptor)
        try:
            info = os.fstat(file)
            require(stat.S_ISREG(info.st_mode) and info.st_size <= 8_000_000)
            with os.fdopen(file, 'rb', closefd=False) as stream:
                raw = stream.read(8_000_001)
            require(len(raw) <= 8_000_000)
            return hashlib.sha256(raw).hexdigest()
        finally:
            os.close(file)
    finally:
        os.close(descriptor)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy', required=True)
    parser.add_argument('--expected-sha256', required=True)
    parser.add_argument('--source-root', required=True)
    args = parser.parse_args()
    try:
        require(re.fullmatch(r'[a-f0-9]{64}', args.expected_sha256) is not None)
        root = Path(args.source_root)
        require(root.is_absolute() and root.resolve(strict=True) == root and root.is_dir())
        path = Path(args.policy)
        require(not path.is_symlink() and path.resolve(strict=True) == path.absolute())
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            require(stat.S_ISREG(info.st_mode) and info.st_size <= 64_000)
            with os.fdopen(fd, 'rb', closefd=False) as stream:
                raw = stream.read(64_001)
            require(len(raw) <= 64_000 and hashlib.sha256(raw).hexdigest() == args.expected_sha256)
        finally:
            os.close(fd)
        policy = decode(raw)
        require(isinstance(policy, dict) and set(policy) == {'schema_version', 'exceptions'}
                and type(policy['schema_version']) is int and policy['schema_version'] == 1
                and isinstance(policy['exceptions'], list) and 1 <= len(policy['exceptions']) <= 32)
        approved = {}
        fields = {'rule', 'path', 'line', 'sha256', 'rationale', 'approval_ref'}
        for record in policy['exceptions']:
            require(isinstance(record, dict) and set(record) == fields
                    and isinstance(record['rule'], str) and re.fullmatch(r'[A-Za-z0-9_.:/-]{1,512}', record['rule'])
                    and type(record['line']) is int and 1 <= record['line'] <= 2_147_483_647
                    and isinstance(record['sha256'], str) and re.fullmatch(r'[a-f0-9]{64}', record['sha256'])
                    and all(isinstance(record[key], str) and 0 < len(record[key].strip()) <= 4096
                            for key in ('rationale', 'approval_ref')))
            key = (record['rule'], relative(record['path']), record['line'])
            require(key not in approved and digest_source(root, key[1]) == record['sha256'])
            approved[key] = record
        fact_bytes = sys.stdin.buffer.read(16_000_001)
        require(len(fact_bytes) <= 16_000_000)
        facts = decode(fact_bytes)
        require(isinstance(facts, list) and len(facts) <= 100_000)
        accepted = set()
        rejected = 0
        for fact in facts:
            require(isinstance(fact, dict) and set(fact) == {'rule', 'locations', 'numeric_high', 'level'}
                    and type(fact['numeric_high']) is bool and fact['level'] in {'error', 'warning', 'note', 'none'})
            key = None
            try:
                locations = fact['locations']
                require(isinstance(locations, list) and len(locations) == 1)
                location = locations[0]['physicalLocation']
                require(isinstance(location, dict))
                artifact = location['artifactLocation']
                require(isinstance(artifact, dict) and set(artifact) <= {'uri', 'uriBaseId'})
                require('uriBaseId' not in artifact or artifact['uriBaseId'] == '%SRCROOT%')
                line = location['region']['startLine']
                require(type(line) is int and line > 0)
                key = (fact['rule'], relative(artifact['uri']), line)
            except (ValueError, KeyError, TypeError):
                pass
            # Suppression metadata is never consulted. Every numeric-high result
            # and every additional/duplicate unapproved error still blocks.
            if fact['numeric_high'] or fact['level'] != 'error' or key not in approved or key in accepted:
                rejected += 1
            else:
                accepted.add(key)
        if rejected:
            print(f'{rejected} unapproved high/critical findings; accepted exact-source audit exceptions: {len(accepted)}', file=sys.stderr)
            return 1
        if accepted:
            print(f'SARIF accepted exact-source audit exceptions: {len(accepted)}; unapproved high/critical findings: 0; NOT a clean security scan')
        else:
            print('SARIF clean of high/critical findings; accepted exact-source audit exceptions: 0')
        return 0
    except (ValueError, OSError, KeyError, TypeError, OverflowError):
        print('Audit policy blocked: invalid approval, registry, source or gated facts', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
