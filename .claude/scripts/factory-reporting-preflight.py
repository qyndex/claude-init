#!/usr/bin/env python3
"""Verify reporting runner policy and generate protected non-secret config."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys

spec = importlib.util.spec_from_file_location('coordinator', Path(__file__).with_name('factory-coordinator.py'))
coordinator = importlib.util.module_from_spec(spec); spec.loader.exec_module(coordinator)
require = coordinator.require


def policy(api, group_id, ref):
    require(type(group_id) is int and group_id > 0, 'reporting runner group ID required')
    repo = api.get(f'repos/{api.repo}')
    require(repo['full_name'] == api.repo and repo['owner']['type'] == 'Organization' and ref == 'refs/heads/' + repo['default_branch'], 'reporting source is not protected default branch')
    org = repo['owner']['login']
    root = f'orgs/{org}/actions/runner-groups/{group_id}'
    group = api.get(root)
    expected = f"{api.repo}/.github/workflows/factory-digest.yml@refs/heads/{repo['default_branch']}"
    require(group['id'] == group_id and group.get('default') is False and group['visibility'] == 'selected', 'reporting group is broad/default')
    require(group.get('restricted_to_workflows') is True and group.get('selected_workflows') == [expected], 'reporting runner workflow restriction differs')
    require(re.fullmatch(r'[A-Za-z0-9 _.-]{1,64}', group['name']), 'invalid runner group name')
    if not repo['private']:
        require(group.get('allows_public_repositories') is True, 'reporting repository denied by group')
    pages = api.request(root + '/repositories', paginate=True)
    repos = [r for page in pages for r in page['repositories']]
    require(len(repos) == 1 and repos[0]['id'] == repo['id'] and repos[0]['full_name'] == api.repo, 'reporting group repository restriction differs')
    pages = api.request(root + '/runners', paginate=True)
    runners = [r for page in pages for r in page['runners']]
    supported = [r for r in runners if r['status'] == 'online' and r['os'].lower() in {'linux', 'macos', 'osx'} and {'self-hosted', 'factory-reporting'} <= {label['name'] for label in r['labels']}]
    require(bool(supported), 'no supported online reporting runner')
    return {'group': 'org/' + group['name'], 'workflow': expected}


def runtime_config(env):
    required = ('GITHUB_REPOSITORY', 'FACTORY_REPORTING_STATE_DIR', 'FACTORY_REPORTING_CHANNEL', 'FACTORY_REPORTING_TEAM_ID', 'FACTORY_REPORTING_START')
    require(all(env.get(name) for name in required), 'reporting runtime configuration missing')
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', env['GITHUB_REPOSITORY']), 'invalid reporting repository')
    raw = Path(env['FACTORY_REPORTING_STATE_DIR'])
    require(raw.is_absolute() and raw.is_dir() and not raw.is_symlink(), 'state directory must be pre-provisioned absolute directory')
    root = raw.resolve()
    require('_work' not in root.parts and '_temp' not in root.parts, 'state directory belongs to a runner workspace')
    for name in ('GITHUB_WORKSPACE', 'RUNNER_WORKSPACE', 'RUNNER_TEMP'):
        if env.get(name):
            excluded = Path(env[name]).resolve()
            require(not root.is_relative_to(excluded) and not excluded.is_relative_to(root), 'state overlaps checkout/temporary workspace')
    info = root.stat()
    require(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) == 0o700, 'state directory must be privately owned mode 0700')
    database = root / 'reporting.sqlite'
    if database.exists() or database.is_symlink():
        require(database.is_file() and not database.is_symlink() and database.stat().st_uid == os.getuid() and stat.S_IMODE(database.stat().st_mode) == 0o600, 'reporting database ownership/mode differs')
    # Validate schema/identity locally without creating the runtime database.
    require(re.fullmatch(r'T[A-Z0-9]+', env['FACTORY_REPORTING_TEAM_ID']) and re.fullmatch(r'[CG][A-Z0-9]+', env['FACTORY_REPORTING_CHANNEL']), 'Slack IDs required')
    from datetime import datetime
    start = datetime.fromisoformat(env['FACTORY_REPORTING_START'].replace('Z', '+00:00'))
    require(start.tzinfo is not None, 'reporting start needs timezone')
    return {'enabled': True, 'attachments_enabled': env.get('FACTORY_REPORTING_ATTACHMENTS_ENABLED') == 'true', 'repository': env['GITHUB_REPOSITORY'], 'branch': env.get('FACTORY_REPORTING_BRANCH', 'main'),
            'destination': env['FACTORY_REPORTING_CHANNEL'], 'team_id': env['FACTORY_REPORTING_TEAM_ID'],
            'start': env['FACTORY_REPORTING_START'], 'database': str(database), 'watchdog_grace_minutes': 60}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy', action='store_true')
    parser.add_argument('--config-out', type=Path)
    args = parser.parse_args()
    require(bool(args.policy) != bool(args.config_out), 'choose policy or runtime config')
    if args.policy:
        result = policy(coordinator.GitHub(os.environ['GITHUB_REPOSITORY']), int(os.environ['FACTORY_REPORTING_RUNNER_GROUP_ID']), os.environ['GITHUB_REF'])
        if os.environ.get('GITHUB_OUTPUT'):
            with Path(os.environ['GITHUB_OUTPUT']).open('a') as out:
                out.write('group=' + result['group'] + '\n')
        print(json.dumps(result))
    else:
        os.umask(0o077)
        config = runtime_config(os.environ)
        require(not args.config_out.is_symlink(), 'config output symlink denied')
        args.config_out.write_text(json.dumps(config, indent=2) + '\n')
        args.config_out.chmod(0o600)
        print('Protected reporting config prepared; no credential is serialized.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError):
        print('Reporting preflight blocked: verify trusted runner policy/configuration.', file=sys.stderr)
        sys.exit(1)
