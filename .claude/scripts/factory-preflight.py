#!/usr/bin/env python3
"""Report missing activation prerequisites without exposing credentials."""
import argparse
import json
import re
import os
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy', required=True, type=Path)
    args = parser.parse_args()
    policy = json.loads(args.policy.read_text())
    missing = []
    if policy.get('enabled') is not True:
        missing.append('operator-approved policy activation')
    app = policy.get('app_id')
    if type(app) is not int or app <= 0 or os.environ.get('FACTORY_APP_ID') != str(app):
        missing.append('matching dedicated GitHub App ID')
    if os.environ.get('FACTORY_KEY_PRESENT') != 'true':
        missing.append('private key in protected factory-authority environment')
    if not policy.get('required_checks'):
        missing.append('required check producer pins')
    if not policy.get('specs'):
        missing.append('approved spec revision, AC set and path scope')
    producers = policy.get('producers', {})
    for role in ('verification', 'review'):
        definition = producers.get(role, {})
        if type(definition.get('workflow_id')) is not int or definition['workflow_id'] <= 0 or not definition.get('trusted_files'):
            missing.append(f'{role} authenticated workflow and runtime hashes')
        expected = 'factory-verification' if role == 'verification' else 'factory-independent-review'
        if definition.get('event') != 'pull_request_target' or definition.get('check_name') != expected:
            missing.append(f'{role} protected event and candidate-check identity')
        paths = {f'.github/workflows/factory-{role}.yml', '.claude/scripts/factory-producer.py',
                 '.claude/scripts/factory-producer-check.py', '.claude/scripts/factory-coordinator.py',
                 '.claude/scripts/validate-candidate-evidence.py'}
        if not paths <= set(definition.get('trusted_files', {})):
            missing.append(f'{role} complete transitive runtime hashes')
    for sid, approved in policy.get('specs', {}).items():
        acs = approved.get('ac_ids', [])
        if not approved.get('path') or not acs or not approved.get('allowed_paths') or set(approved.get('acceptance_commands', {})) != set(acs):
            missing.append(f'spec {sid} bytes, scope and per-AC acceptance commands')
        if re.fullmatch(r'[A-Za-z0-9./:_-]+@sha256:[0-9a-f]{64}', approved.get('verification_image', '')) is None:
            missing.append(f'spec {sid} digest-pinned verification runtime')
    print(json.dumps({'ready': not missing, 'missing': missing}, indent=2))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
