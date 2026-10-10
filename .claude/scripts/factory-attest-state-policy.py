#!/usr/bin/env python3
"""Observe no-bypass state policy as an operator; never extract CLI credentials."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess

spec = importlib.util.spec_from_file_location('hosted', Path(__file__).with_name('factory-git-state.py'))
hosted = importlib.util.module_from_spec(spec); spec.loader.exec_module(hosted)


class OperatorAPI:
    def __init__(self, repository):
        hosted.require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository or ''), 'repository required')
        self.repo = repository

    def request(self, path):
        hosted.require(re.fullmatch(re.escape(f'repos/{self.repo}/rulesets/') + r'[0-9]+', path), 'only policy reads allowed')
        result = subprocess.run(['gh', 'api', '--hostname', 'github.com', '--method', 'GET', path],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
        hosted.require(result.returncode == 0 and len(result.stdout) <= 1_000_000, 'operator policy read failed')
        return json.loads(result.stdout, object_pairs_hook=hosted.digest.coordinator.contract.no_duplicate_keys)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--ruleset', type=int, action='append', required=True)
    args = parser.parse_args(); api = OperatorAPI(args.repository)
    hosted.require(all(identity > 0 for identity in args.ruleset), 'ruleset ID invalid')
    print(json.dumps({str(identity): hosted.attest_policy(api, identity) for identity in args.ruleset}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
        raise SystemExit('Operator approval blocked: require visible empty bypass actors, complete policy and a settled timestamp.')
