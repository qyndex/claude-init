#!/usr/bin/env python3
"""Generate an additive activation ruleset for operator review; never apply it."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app-id', type=int, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
if args.app_id <= 0:
    parser.error('positive dedicated App ID required')
live = json.loads(subprocess.check_output(['gh', 'api', 'repos/qyndex/claude-init/rulesets/19653920'], text=True))
if live['enforcement'] != 'active' or live.get('bypass_actors') != []:
    raise SystemExit('Unexpected live enforcement/bypass policy; operator decision required')
body = {key: live[key] for key in ('name', 'target', 'enforcement', 'conditions', 'rules', 'bypass_actors')}
rules = [rule for rule in body['rules'] if rule['type'] == 'required_status_checks']
if len(rules) != 1 or not rules[0]['parameters']['strict_required_status_checks_policy']:
    raise SystemExit('Missing or ambiguous strict required-check rule')
checks = rules[0]['parameters']['required_status_checks']
for check in checks:
    expected = args.app_id if check['context'] == 'factory-eligibility' else 15368
    if check.get('integration_id') not in (None, expected):
        raise SystemExit('Existing producer pin differs; operator decision required')
    check['integration_id'] = expected
if not any(check['context'] == 'factory-eligibility' for check in checks):
    checks.append({'context': 'factory-eligibility', 'integration_id': args.app_id})
args.output.write_text(json.dumps(body, indent=2) + '\n')
print('Prepared additive producer-pinned ruleset; no live policy changed.')
