#!/usr/bin/env python3
"""Report missing activation prerequisites without exposing credentials."""
import argparse
import json
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
        if type(definition.get('workflow_id')) is not int or not definition.get('trusted_files'):
            missing.append(f'{role} authenticated workflow and runtime hashes')
    print(json.dumps({'ready': not missing, 'missing': missing}, indent=2))
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
