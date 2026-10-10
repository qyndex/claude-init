#!/usr/bin/env python3
"""Read-only reporting health probe for a scheduler outside GitHub Actions."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

spec = importlib.util.spec_from_file_location('watchdog_state', Path(__file__).with_name('factory-git-state.py'))
state = importlib.util.module_from_spec(spec); spec.loader.exec_module(state)
require = state.require


def inspect(config, api, client, now):
    require(config.get('enabled') is True and now.tzinfo is not None, 'watchdog configuration/clock required')
    grace = config.get('watchdog_grace_minutes', 60)
    require(type(grace) is int and 0 <= grace <= 1440, 'invalid watchdog grace')
    require(api.repo == config['state_repository'], 'foreign watchdog state source')
    stream = hashlib.sha256(state.canonical([config['repository'], config['destination'], config['branch']]).encode()).hexdigest()
    checkpoint = state.GitState(api, config['state_branch'], stream, config.get('bootstrap_sha'), config.get('policy_approvals'))
    require(checkpoint.bytes is not None, 'reporting checkpoint uninitialized')
    document = json.loads(checkpoint.bytes, object_pairs_hook=state.digest.coordinator.contract.no_duplicate_keys)
    state.validate(document, config['repository'], stream)
    cursor = state.digest.instant(document['tables']['digest_cursors'][0]['cutoff'])
    require(cursor <= now.astimezone(timezone.utc), 'reporting cursor is in the future')
    target = state.digest.instant(state.slack.due(now))
    batches = document['tables']['digest_batches']
    confirmed = [batch for batch in batches if batch['status'] == 'confirmed']
    verified = False
    if confirmed:
        latest = max(confirmed, key=lambda batch: state.digest.instant(batch['cutoff']))
        adapter = state.slack.transport(client, config, latest)
        require(adapter.lookup(latest['key']).get('receipt') == json.loads(latest['receipt']), 'latest delivered report no longer verifiable')
        verified = True
    missed = cursor < target and now.astimezone(timezone.utc) >= target + timedelta(minutes=grace)
    pending = sum(batch['status'] != 'confirmed' for batch in batches)
    return {'schema_version': 1, 'repository': config['repository'], 'checkpoint_sha': checkpoint.head,
            'status': 'missed' if missed else 'grace' if cursor < target else 'current',
            'missed_delivery': missed, 'expected_cutoff': state.digest.stamp(target),
            'delivered_cutoff': state.digest.stamp(cursor), 'pending_batches': pending,
            'latest_receipt_verified': verified}


def heartbeat(url, result, opener=None):
    """Signal only fully current, remotely verified delivery to an external timer."""
    require(result.get('status') == 'current' and result.get('latest_receipt_verified') is True,
            'watchdog heartbeat requires current verified delivery')
    parsed = urllib.parse.urlsplit(url or '')
    require(parsed.scheme == 'https' and parsed.netloc == 'hc-ping.com' and
            not parsed.query and not parsed.fragment, 'unsupported heartbeat URL')
    identity = parsed.path.removeprefix('/')
    require(str(uuid.UUID(identity)) == identity, 'heartbeat URL identity invalid')
    # No report content, PR/spec details, credentials or diagnostic bodies leave GitHub.
    request = urllib.request.Request(url, data=b'', method='POST')
    opener = opener or urllib.request.build_opener(state.slack.NoRedirect())
    try:
        with opener.open(request, timeout=15) as response:
            require(response.status == 200 and response.read(1025) == b'OK', 'heartbeat not acknowledged')
    except (urllib.error.URLError, TimeoutError):
        raise ValueError('heartbeat not acknowledged') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--heartbeat', action='store_true')
    args = parser.parse_args(); config = state.digest.coordinator.contract.load(args.config)
    token = os.environ.get('FACTORY_REPORTING_STATE_TOKEN') or os.environ.get('GH_TOKEN')
    result = inspect(config, state.API(config['state_repository'], token), state.slack.http_client(config), datetime.now(timezone.utc))
    if args.heartbeat:
        heartbeat(os.environ.get('FACTORY_REPORTING_HEARTBEAT_URL'), result)
    print(state.canonical(result)); return int(result['missed_delivery'])


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, TypeError, OSError, sqlite3.Error, subprocess.SubprocessError):
        print('{"schema_version":1,"status":"blocked","healthy":false}', file=sys.stderr)
        sys.exit(2)
