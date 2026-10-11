#!/usr/bin/env python3
"""Generate a policy-bound activation proposal; never mutate live rules."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
from urllib.parse import quote


def load_module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


contract = load_module('contract', 'validate-candidate-evidence.py')
bounded = load_module('bounded', 'factory-bounded-process.py')
require = contract.require


def get(endpoint):
    result = bounded.run(['gh', 'api', endpoint, '--method', 'GET'],
                         env=dict(os.environ), cwd=Path.cwd(), timeout=30)
    require(result.returncode == 0, 'GitHub rule query failed')
    return json.loads(result.stdout, object_pairs_hook=contract.no_duplicate_keys)


def proposal(policy, ruleset_id, app_id):
    repo, branch = policy.get('repository'), policy.get('base_branch')
    require(isinstance(repo, str) and re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo) and all(part not in {'.', '..'} for part in repo.split('/')), 'valid policy repository required')
    require(isinstance(branch, str) and 0 < len(branch) <= 255 and '\x00' not in branch, 'valid policy base branch required')
    configured_app = policy.get('app_id')
    require(configured_app is None or (type(configured_app) is int and configured_app == app_id), 'policy App ID differs')
    required = policy.get('required_checks')
    require(isinstance(required, dict) and required, 'policy required checks missing')
    require(all(isinstance(name, str) and 0 < len(name) <= 100 and all(ord(char) >= 32 and ord(char) != 127 for char in name) and type(producer) is int and producer > 0 for name, producer in required.items()), 'policy producer pins invalid')
    required = dict(required)
    require('factory-eligibility' not in required or required['factory-eligibility'] == app_id, 'policy eligibility App differs')
    required['factory-eligibility'] = app_id
    applied = get(f'repos/{repo}/rules/branches/{quote(branch, safe="")}')
    require(isinstance(applied, list) and any(type(rule.get('ruleset_id')) is int and rule['ruleset_id'] == ruleset_id for rule in applied if isinstance(rule, dict)), 'selected ruleset does not apply to policy branch')
    live = get(f'repos/{repo}/rulesets/{ruleset_id}')
    require(type(live.get('id')) is int and live['id'] == ruleset_id and live.get('target') == 'branch' and live.get('enforcement') == 'active' and live.get('bypass_actors') == [], 'selected ruleset target/enforcement/bypass invalid')
    body = {key: live[key] for key in ('name', 'target', 'enforcement', 'conditions', 'rules', 'bypass_actors')}
    require(isinstance(body['rules'], list) and any(rule.get('type') == 'pull_request' for rule in body['rules']), 'pull request protection missing')
    rules = [rule for rule in body['rules'] if rule.get('type') == 'required_status_checks']
    require(len(rules) == 1 and rules[0]['parameters'].get('strict_required_status_checks_policy') is True, 'one strict required-check rule required')
    checks = rules[0]['parameters']['required_status_checks']
    require(isinstance(checks, list) and all(isinstance(check, dict) and isinstance(check.get('context'), str) and check['context'] and (check.get('integration_id') is None or (type(check['integration_id']) is int and check['integration_id'] > 0)) for check in checks), 'live required checks invalid')
    existing = {check['context']: check for check in checks}
    require(len(existing) == len(checks), 'duplicate live required contexts')
    for name, producer in required.items():
        if name in existing:
            require(existing[name].get('integration_id') in (None, producer), 'conflicting required producer pin')
            existing[name]['integration_id'] = producer
        else:
            checks.append({'context': name, 'integration_id': producer})
    return body


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--ruleset-id', type=int, required=True)
    parser.add_argument('--app-id', type=int, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(args.ruleset_id > 0 and args.app_id > 0, 'positive ruleset and App IDs required')
    body = proposal(contract.load(args.policy), args.ruleset_id, args.app_id)
    args.output.write_text(json.dumps(body, indent=2) + '\n')
    print('Prepared complete policy-bound ruleset proposal; no live policy changed.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, AttributeError, OSError) as error:
        raise SystemExit(f'factory ruleset planning: FAIL: {error}')
